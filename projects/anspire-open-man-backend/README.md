# anspire-open-man-backend (管理后台后端)

OCS + knodo 项目部署 (Python)。

## 架构

- **Base image**: `myg133/openvscode-server:python-knodo`
- **域名**: `admin-backend.localdev.anspire.cn` (走泛域 `*.localdev.anspire.cn` cert)
- **存储**: NFS `172.25.93.9:/data-volumes/anspire-open-man-backend/{knodo,project}`
- **反代**: Traefik v3.7 静态 wildcard cert (ZeroSSL)

## 部署

```bash
# 1. NFS 准备 (server 上)
mkdir -p /data-volumes/anspire-open-man-backend/{knodo,project}
chmod 777 /data-volumes/anspire-open-man-backend/

# 2. 准备 .env
cp .env.example .env
vi .env   # 填 KNODO_INSTALL_URL + OCS_HOST

# 3. 拉 base + 启动
docker pull myg133/openvscode-server:python-knodo
docker compose up -d
```

## 验证

```bash
# knodo-agent 健康 (容器内)
docker exec ocs-anspire-open-man-backend curl 127.0.0.1:9910/health

# OCS UI (走 Traefik 域名)
curl -k https://admin-backend.localdev.anspire.cn

# knodo 集成测试
docker exec ocs-anspire-open-man-backend bash /usr/local/bin/test-knodo-integration.sh

# Traefik 是不是发现 router
docker logs traefik --since 1m 2>&1 | grep admin-backend | tail -5
```

## Base 镜像更新

```bash
docker pull myg133/openvscode-server:python-knodo
docker compose up -d --force-recreate
```
