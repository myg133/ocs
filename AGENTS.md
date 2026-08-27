# OCS + knodo 本地开发环境

`gitpod/openvscode-server` 镜像家族 + knodo 本地 Agent 集成。本仓库是个人 dev container 镜像矩阵, 用来在 docker 主机上跑 openvscode-server IDE + 接受 knodo 云端 (anchnet.knodo.vip) 的远程调度。

## 镜像矩阵

| 目录 | 镜像 tag | 用途 | 状态 |
|---|---|---|---|
| `base/` | `myg133/openvscode-server:base-latest` | 基础镜像 (跟 gitpod upstream 一致 + 10 扩展) | 已用 |
| `python/` | `myg133/openvscode-server:python` | Python dev (uv + 5 扩展) | 已用 |
| `njs/` | `myg133/openvscode-server:nextjs` | Node.js / 前端 dev (nvm + Node 22) | 已用 |
| `rust/` | `myg133/openvscode-server:rust` | Rust dev | 现有 |
| `deno/` | `myg133/openvscode-server:deno` | Deno dev | 现有 |
| `go/` | `myg133/openvscode-server:go` | Go dev | 现有 |
| **`python-knodo/`** | **`myg133/openvscode-server:python-knodo`** | **Python + knodo agent 集成** | **已实现 (单 container, 待拆 sidecar)** |
| **`njs-knodo/`** | **`myg133/openvscode-server:njs-knodo`** | **Node.js + knodo agent 集成** | **已实现 (单 container, 待拆 sidecar)** |

knodo 变体的命名规则: `<lang>-knodo`, 跟原 `<lang>` 镜像并存。

## 最终架构 (Traefik + DNSPod + NFS + Sidecar)

### 组件拓扑

```
浏览器 → 443/80
         ↓
[ Traefik ]   (DNSPod DNS-01 拿证书)
         ↓
[ py-knodo / njs-knodo Pod ]   (单容器, sidecar 拆分中)
   ├─ container: openvscode-server (3000)
   └─ container: knodo-agent      (9910, WebSocket 出站连 knodo 云)
         ↓
[ NFS 172.25.93.9:/data-volumes ]
   ├─ py-knodo/{project, knodo-state, openvscode-state}
   └─ njs-knodo/{project, knodo-state, openvscode-state}
```

### 端口

| 端口 | 服务 | 暴露方式 |
|---|---|---|
| 80 | Traefik HTTP (重定向到 HTTPS) | 公网/内网 |
| 443 | Traefik HTTPS (TLS 终止) | 公网/内网 |
| 3000 | openvscode-server (主) | 走 Traefik, 域名路由 |
| 9910 | knodo-agent (管理 API) | 暂定 `127.0.0.1:9910`, 不走 Traefik |

### DNS / TLS

- **DNS provider**: 腾讯云 DNSPod (用户自有域名)
- **TLS 证书**: Let's Encrypt, **DNS-01 挑战** 走 `dnspod` provider (Traefik 内置)
- **A 记录**: 指向**内网 IP** (不是公网), 纯内网访问, 流量不出公网
- **Traefik 配置**: `provider: dnspod`, `DNSPOD_API_KEY=id,token` 走 `.env` 注入
- **ACME 邮箱**: 走 `.env` 注入, 别硬编码

### 存储

- **NFS server**: `172.25.93.9` (跟 docker daemon 同机)
- **NFS share**: `/data-volumes`
- **挂载方式**: docker compose `local` driver + `type: nfs` 选项 (v4 协议, 自动 uid 映射)
- **NFS 性能调优**: `rsize=8192,wsize=8192,hard,intr,noatime`
- **路径布局**:
  ```
  /data-volumes/
  ├── py-knodo/{project, knodo, openvscode}
  └── njs-knodo/{project, knodo, openvscode}
  ```
- **部署前准备**: NFS server 上 `mkdir -p` + `chmod 777` 这 6 个子目录

### Sidecar 拆分 (TODO)

当前 knodo 变体是**单 container 跑两个进程** (knodo-agent 后台 + openvscode 前台)。
**计划改造**: 拆成 sidecar 两个 container, 共享 PID/network/filesystem namespace。

- `knodo-only.sh`: 只跑 knodo-agent
- `ovss-only.sh`: 只跑 openvscode-server
- 当前 `entrypoint.sh` 的"智能激活 + 权限修复"逻辑要分到两个脚本里

### 配置注入层级

| 项 | 注入方式 | 备注 |
|---|---|---|
| `KNODO_INSTALL_URL` (首次 24h) | `.env` → `environment` | 用完可删 |
| `BACKEND_WS_URL` + `API_TOKEN` (长期) | `.env` (named volume 丢时兜底) | 正常情况下写到 `agent.env` |
| `HTTP_PROXY` / `HTTPS_PROXY` | `.env` (可选) | |
| `DNSPOD_API_KEY` (Traefik) | Traefik 自己的 `.env` | 严格分离 |
| `ACME_EMAIL` (Traefik) | Traefik 自己的 `.env` | 严格分离 |

## 镜像构建关键点

### Dockerfile 分层原则 (python-knodo/njs-knodo 都用这模式)

```
Layer 1: 系统依赖 (git/jq/nvm)        ← 几乎不变, 装一次缓存很久
Layer 2: 扩展 (5-7 个, 单 RUN + 重试)  ← 偶尔变
Layer 3: knodo 4 个脚本 COPY            ← 改 bug 频繁, 放最末
Layer 4: ENTRYPOINT
```

### 关键设计

- **旁路公司代理** (`172.25.93.8:10808`): 装大扩展 (debugpy) 时设 `NO_PROXY=*`
- **扩展重试 5 次**: 单个失败不影响其他, 避免一个挂全挂
- **降权到 openvscode-server**: ENTRYPOINT 启动时是 root (为了 chown named volume), 内部 `exec sudo -u openvscode-server` 降权
- **HOME=/home/workspace**: 跟 pod.yaml / docker-compose 挂载路径对齐

## 踩过的坑 (lessons learned)

### 1. Named volume 默认 root 拥有, openvscode-server 写不进去

**症状**: `mkdir: cannot create directory '/home/workspace/.knodo/agent': Permission denied`

**原因**: docker daemon 是 root, 创建的 named volume 默认 root 拥有, 容器内 `openvscode-server` (UID 1000) 写不进去

**修法** (在 `entrypoint.sh` 阶段 0):
```bash
if [ "$(id -u)" -eq 0 ]; then
    mkdir -p /home/workspace/.knodo/agent/{bin,config,logs,run,downloads,claude,codex}
    mkdir -p /home/workspace/.knodo/data
    chown -R openvscode-server:openvscode-server /home/workspace/.knodo
    export HOME=/home/workspace
    exec sudo -u openvscode-server -E "$0" "$@"
fi
```

对应 Dockerfile 必须 `USER root` (entrypoint 自己降权)。

### 2. Docker daemon 在远端, 本机只是 CLI

**症状**: docker-compose 里的 `./project` 相对路径**不是 Windows 路径**, 是 daemon 端路径, 远端 daemon 时挂不上

**修法**:
- 简单: 不挂项目目录, 进 openvscode 终端 `git clone`
- 复杂: 写 daemon 端绝对路径, 例如 `/opt/projects/my-app`

### 3. Docker 镜像站不代理 user 镜像

**症状**: `myg133/openvscode-server:base-latest` 拉不到, 镜像站 (`docker.xuanyuan.me` 等) 返回 403

**原因**: 国内镜像站只代理官方库和热门镜像, 不代理用户私有镜像

**修法**:
- **A**: 远端 daemon 上 `vim /etc/docker/daemon.json` 临时清空 `registry-mirrors`, build 完还原
- **B**: 本地先 build base (`docker build -f base.Dockerfile`), 镜像走本地缓存
- **C**: 改 FROM 到 `gitpod/openvscode-server:latest` 直接 (会丢 base 里的扩展和 settings, 慎用)

### 4. 大扩展 (debugpy) 装超时

**症状**: `ms-python.debugpy` 装到 96s 后报 `aborted`, 其他 4 个 Python 扩展正常装

**原因**: 公司代理 `172.25.93.8:10808` 拖慢下载, 大扩展触发超时

**修法** (Dockerfile Layer 2):
```dockerfile
ENV NO_PROXY=* no_proxy=* HTTPS_PROXY= HTTP_PROXY=
RUN for ext in ...; do
    for i in 1 2 3 4 5; do
        if ${OPENVSCODE} --install-extension "$ext"; then break; fi
        sleep 10
    done
done
```

### 5. nvm 路径别用 `/opt/nvm/bin`

原 `njs/Dockerfile` 写 `ENV NVM_DIR=/opt/nvm/bin` 是错的, nvm install.sh 期望 `NVM_DIR` 是父目录, nvm.sh 会放在 `$NVM_DIR/nvm.sh`。正确写法: `NVM_DIR=/opt/nvm`。

### 6. knodo install URL 24h 有效

- 首次激活用 `KNODO_INSTALL_URL` 写到 `agent.env` (named volume)
- 长期凭证 (`BACKEND_WS_URL` + `API_TOKEN`) 自动从 activate 响应里 `eval` 出来
- 后续重启读 `agent.env` 复用, 跟 install URL 无关
- 24h 限制**只对 install URL 本身**, 不影响后续运行
- **凭证备份**: `scripts/extract-knodo-credentials.sh --write-backup` 写到 `.env.knodo-backup` (加 `.gitignore`)

### 7. entrypoint 三种凭证路径互斥

```bash
# 优先级 (高到低)
1. $HOME/.knodo/agent/config/agent.env 存在 + API_TOKEN 非空 → 复用 (named volume 持久化生效)
2. BACKEND_WS_URL + API_TOKEN env 都有 → render-agent-env.sh 旁路渲染
3. KNODO_INSTALL_URL env 存在 → install-knodo-agent.sh 调 knodo 官方 curl|bash
4. 都没有 → fail
```

## 部署文档 (knodo 变体)

### 本地测试 (docker-compose)

```bash
cd D:\MyCodes\docker\ocs\<lang>-knodo
cp .env.example .env
# 填 KNODO_INSTALL_URL
docker compose up -d
docker compose logs -f
# 浏览器: http://localhost:3000 (python) / 3001 (njs, 错开端口)
```

### K8s → Compose + Traefik (计划中)

k8s 路线放弃, 改用 compose + Traefik + NFS。`traefik-stack/` 目录待建。

## 待补充信息 (TODO)

部署前要问业务方 / 自己去 DNSPod 拿的:

- [ ] **主域名**: DNSPod 上自有的那个 (e.g., `example.com`)
- [ ] **子域名规则**: 默认建议 `py-knodo.<主域>` / `njs-knodo.<主域>`
- [ ] **docker 主机内网 IP**: A 记录指向的 IP (e.g., `192.168.1.50`)
- [ ] **DNSPod API Token**: 用户自己加到 Traefik 的 `.env`, 不入库
- [ ] **ACME 邮箱**: Let's Encrypt 注册用, 走 Traefik 的 `.env`
- [ ] **NFS 子目录预创建**: 在 172.25.93.9 上手动 `mkdir -p /data-volumes/{py,njs}-knodo/{project,knodo,openvscode}` + `chmod 777`
- [ ] **DNSPod A 记录**: 手动在控制台加 1 条 A 记录指向内网 IP (5 秒的事, 不自动化)
- [ ] **traefik-stack/ 目录**: docker-compose.yml + traefik.yml + dynamic/middlewares.yml 还没建
- [ ] **sidecar 拆分**: 当前 `entrypoint.sh` 还是单 container 双进程, 待拆成 `knodo-only.sh` + `ovss-only.sh`
- [ ] **9910 端口方案**: 暂定 `127.0.0.1:9910:9910` (loopback only), 远程监控需求看后续

## 关键命令速查

```bash
# build knodo 镜像
cd D:\MyCodes\docker\ocs\<lang>-knodo
docker build -t myg133/openvscode-server:<lang>-knodo . --no-cache

# 提取凭证备份
./scripts/extract-knodo-credentials.sh --write-backup

# 验证 knodo 集成
docker compose exec openvscode-server bash /usr/local/bin/test-knodo-integration.sh

# knodo-agent 管理
docker compose exec openvscode-server bash -c '$HOME/.knodo/agent/bin/knodo-agent status'
docker compose exec openvscode-server bash -c '$HOME/.knodo/agent/bin/knodo-agent logs'

# 临时清空 docker mirror (build user 镜像时)
# 在远端 daemon 上:
sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
sudo vi /etc/docker/daemon.json   # 删 registry-mirrors 数组
sudo systemctl restart docker
# build 完还原:
sudo cp /etc/docker/daemon.json.bak /etc/docker/daemon.json
sudo systemctl restart docker
```

## 文件模板 (knodo 变体通用)

```
<lang>-knodo/
├── Dockerfile                # 4 层: 系统依赖 → 扩展 → knodo 脚本 → ENTRYPOINT
├── docker-compose.yml        # 端口 3000+9910, named volume, env 注入
├── ovscs.pod.yaml            # K8s 部署 (弃用, 但保留)
├── .env.example              # KNODO_INSTALL_URL + 凭证占位
├── .env.knodo-backup         # (gitignore) 长期凭证备份
├── .gitignore                # 排除 .env / 探查脚本
├── .dockerignore             # 排除部署/测试文件
├── settings.json
├── README.md
└── scripts/
    ├── entrypoint.sh              # 智能激活 + 权限修复 + 降权
    ├── knodo-only.sh              # (TODO) 拆 sidecar 后用
    ├── ovss-only.sh               # (TODO) 拆 sidecar 后用
    ├── install-knodo-agent.sh     # 调 knodo 官方 curl|bash
    ├── render-agent-env.sh        # 旁路渲染 env
    ├── test-knodo-integration.sh  # 8 项验证
    ├── extract-knodo-credentials.sh  # 备份凭证
    └── backup-docker-mirrors.ps1  # Windows 端临时清空 mirror
```
