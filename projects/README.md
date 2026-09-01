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

## ⚠️ 代理配置: 在 .env 配, 统一大写

`myg133/openvscode-server:base-latest` 这个 base image **烤了** `HTTP_PROXY=http://172.25.93.8:10808` 等公司代理 env。**所有** knodo 容器继承，**knodo 官方 install 脚本走代理到 CDN 只有 155 KB/s**（30+ 分钟下载）。

**修法**: 在 `.env` 里用同名大写 env vars 覆盖 base image 烤的（docker-compose 注入的 env vars 优先级 > image 内置 env vars）。**不要**在 `docker-compose.yml` 写清空行（会跟 .env 抢）。

**默认 .env 模板已配好**（每个项目的 `.env.example` 都有这段）：

```bash
# 统一大写, 默认留空走直连 (1.12 MB/s)
HTTP_PROXY=
HTTPS_PROXY=
NO_PROXY=localhost,127.0.0.1,anchnet.knodo.vip,*.localdev.anspire.cn
```

**关键**:
- **大小写统一**（全大写），别混用
- `docker-compose.yml` 的 `environment:` 段**不写**任何代理 env（让 .env 接管）
- 想走公司代理: 取消注释 + 填值（仍受公司代理限速影响）

**`docker-compose.yml` 的 environment 段只配这 4 个 knodo 凭证**：

```yaml
environment:
  - KNODO_INSTALL_URL=${KNODO_INSTALL_URL:-}
  - BACKEND_WS_URL=${BACKEND_WS_URL:-}
  - API_TOKEN=${API_TOKEN:-}
  - KNODO_AGENT_PORT=9910
```
