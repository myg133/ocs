# anspire-open-llm-dify-plugin (Dify LLM Plugin)

OCS + knodo 项目部署。

## 架构

- **Base image**: `myg133/openvscode-server:py-knodo` (推到 Docker Hub 的 OCS + knodo Python base)
- **域名**: `diffy.localdev.anspire.cn` (走泛域 `*.localdev.anspire.cn` cert)
- **端口**: 3000 (UI) / 9910 (knodo-agent)，host 端口 3200/9920（错开 base 默认）
- **存储**: NFS `172.25.93.9:/data-volumes/anspire-open-llm-dify-plugin/{knodo,project}`
- **反代**: Traefik v3.7 静态 wildcard cert (ZeroSSL)

## 部署

```bash
# 1. 准备 .env
cp .env.example .env
vi .env                     # 填 KNODO_INSTALL_URL + DIFFY_HOST

# 2. 拉 base image (server 端)
docker pull myg133/openvscode-server:py-knodo

# 3. 起容器
docker compose up -d

# 4. 看日志
docker logs ocs-anspire-open-llm-dify-plugin -f
```

## 验证

```bash
# knodo-agent 健康
curl http://localhost:9920/health

# OCS UI (走 Traefik 域名)
curl -k https://diffy.localdev.anspire.cn

# knodo 集成测试
docker exec ocs-anspire-open-llm-dify-plugin bash /usr/local/bin/test-knodo-integration.sh
```

## Base 镜像更新

base 镜像 (`py-knodo`) 改了之后：

```bash
# 1. server 端拉新 base
docker pull myg133/openvscode-server:py-knodo

# 2. 重启容器 (用新 base 启动)
docker compose up -d --force-recreate
```

## 文件

- `docker-compose.yml` — 容器编排
- `.env.example` — 环境变量模板
- NFS volume 数据**不在 git**，由 NFS server 持有
