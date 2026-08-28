# OCS + knodo 业务项目层

**每个业务项目一个子目录**，从 base image 拉起，**不维护 Dockerfile**。

## 架构

```
ocs/  (this repo)
├── python-knodo/        # base image 源: myg133/openvscode-server:py-knodo
├── njs-knodo/           # base image 源: myg133/openvscode-server:njs-knodo
├── traefik-stack/       # 反代 + 静态 wildcard cert
├── projects/            # ← 业务项目层 (本目录)
│   ├── anspire-open-llm-dify-plugin/   # FROM :py-knodo
│   ├── anspire-search-frontend/        # FROM :njs-knodo
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
#    - image: myg133/openvscode-server:<py-knodo|njs-knodo>
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
