# OCS + knodo 业务项目层

**每个业务项目一个子目录**，从 base image 拉起，**不维护 Dockerfile**。

## 架构

```
ocs/  (this repo)
├── python-knodo/        # base image 源: myg133/openvscode-server:python-knodo
├── njs-knodo/           # base image 源: myg133/openvscode-server:njs-knodo
├── traefik-stack/       # 反代 + 静态 wildcard cert
├── projects/            # ← 业务项目层 (本目录)
│   ├── anspire-open-llm-dify-plugin/   # FROM :python-knodo
│   ├── anspire-search-frontend/        # FROM :njs-knodo
│   ├── anspire-open-man-backend/       # FROM :python-knodo
│   └── <future-project>/
└── AGENTS.md            # 项目架构 + 部署文档
```

## 目录约定

每个业务项目子目录**只放 3 个文件**：

| 文件 | 作用 |
|---|---|
| `docker-compose.yml` | 容器编排（image 用 base，labels 走 Traefik，volumes 走 NFS） |
| `.env.example` | 环境变量模板（cp 成 .env 后填值） |
| `README.md` | 项目说明（架构 / 部署 / 验证） |

**无 Dockerfile**——base 镜像更新时 `docker pull + restart` 就行。

## 新建项目流程

```powershell
# 1. 复制模板目录
cd D:\MyCodes\docker\ocs\projects
Copy-Item anspire-open-llm-dify-plugin -Recurse -Destination <new-project>

# 2. 改 docker-compose.yml
#    - image: myg133/openvscode-server:<python-knodo|njs-knodo>
#    - container_name: ocs-<new-project>
#    - traefik label: 改 router 名 / Host
#    - volumes: 改 NFS 路径

# 3. 改 .env.example
#    - OCS_HOST=<slug>.localdev.anspire.cn  (所有项目统一用 OCS_HOST)
#    - 改端口 (避免跟现有项目冲突)

# 4. 改 README.md

# 5. 提交
git add projects/<new-project>
git commit -m "feat: 新建 <new-project> 项目"
git push

# 6. 服务器上: 准备 NFS 目录 + cp .env + docker compose up -d
```

## 端口分配约定

**所有项目统一用内部 3000 / 9910，host 端口不暴露**——外部访问全走 Traefik。

- 容器内 `3000` = openvscode-server
- 容器内 `9910` = knodo-agent
- 外部访问走 Traefik + 泛域 cert
- 调试用 `docker exec <container> curl 127.0.0.1:3000` / `9910`

## 域名分配约定

- 全部走泛域 `*.localdev.anspire.cn`（Traefik 静态 cert 已签）
- 每项目用简短 slug: `diffy.localdev.anspire.cn` / `search.localdev.anspire.cn`
- 内部走 `traefik-net` 共享网络，Traefik 容器（host network 80/443/8080）自动发现

## NFS 路径约定

```
/data-volumes/<project-name>/
├── knodo/      # knodo-agent 状态 (entrypoint 写入)
└── project/    # 项目代码 (clone 进去)
```

部署前**先在 NFS server 上**建好：

```bash
mkdir -p /data-volumes/<project-name>/{knodo,project}
chmod 777 /data-volumes/<project-name>/
```

## 模板生成器

`add-knodo-project.ps1 <name> <base>` 一键生成项目骨架（base = `py` 或 `njs`）。

## ⚠️ 代理配置: 大写在 .env 配, 小写自动引用大写

`myg133/openvscode-server:base-latest` 这个 base image **烤了** `HTTP_PROXY=http://172.25.93.8:10808` 等公司代理 env。**所有** knodo 容器继承，**knodo 官方 install 脚本走代理到 CDN 只有 155 KB/s**（30+ 分钟下载）。

**修法** (3 对 6 个 env vars, 大小写用 `${大写}` 模式同步):

**1) `.env` 配大写 (source of truth)**:
```bash
HTTP_PROXY=
HTTPS_PROXY=
NO_PROXY=localhost,127.0.0.1,anchnet.knodo.vip,*.localdev.anspire.cn
```

**2) `docker-compose.yml` 的 environment 段把大写传过去, 小写引用大写**:
```yaml
environment:
  - HTTPS_PROXY=${HTTPS_PROXY:-}
  - https_proxy=${HTTPS_PROXY:-}      # 小写引用大写, 永远一致
  - HTTP_PROXY=${HTTP_PROXY:-}
  - http_proxy=${HTTP_PROXY:-}
  - NO_PROXY=${NO_PROXY:-}
  - no_proxy=${NO_PROXY:-}
```

**核心原理**:
- **大写在 .env 配** (HTTP_PROXY/HTTPS_PROXY/NO_PROXY), 是 source of truth
- **小写在 compose env 段用 `${大写}` 引用**, 永远跟大写一致, 不会分裂
- docker-compose 把 .env 注入的同名大写 env vars 直接覆盖 base image 烤的
- 默认 .env 3 个 key 全留空 → 容器里 6 个 env vars 全是空 → curl 直连 (1.12 MB/s, 7x 加速)

**关键**:
- 改大写 (`.env` 里 `HTTPS_PROXY=...`) → 容器里 6 个 env vars 一起变, 大小写永远同步
- 想走公司代理: 取消 `.env` 里的注释 + 填值
- `https_proxy` 跟 `HTTPS_PROXY` **永远相等**, 因为小写直接用 `${HTTPS_PROXY}` 引用大写
- curl 优先读小写, fallback 大写, **结果都是同一个值**, 大小写不敏感

**判定口诀**:
- 容器行为跟 .env 写的对不上: 看 `docker exec <container> env | grep -i proxy` 6 个 key 是否都设了
- 大写空但小写非空 (或反之): compose env 段写错了, 小写必须用 `${大写}` 引用 (不是单独 `${小写}`)
- 改完 docker-compose.yml 必须 `up -d --force-recreate` (env 只在 create 时注入)
