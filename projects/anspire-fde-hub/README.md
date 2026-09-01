# anspire-fde-hub (Frontend Hub, Rust + Svelte)

OCS + knodo 项目部署 (Rust 后端 + Bun/Svelte/SvelteKit 前端)。

## 架构

- **Base image**: `myg133/openvscode-server:rust-bun-knodo` (内置 rustup + bun + 6 个扩展)
- **域名**: `fde-hub.localdev.anspire.cn` (走泛域 `*.localdev.anspire.cn` cert)
- **存储**: NFS `172.25.93.9:/data-volumes/anspire-fde-hub/{knodo,project}`
- **反代**: Traefik v3.7 静态 wildcard cert (ZeroSSL)

## 部署

```bash
# 0. (已做过) 从集中式路径拷 knodo-agent 二进制
# 详细: 跑之前 session 给的拷贝命令
# cp -a /data-volumes/knodo-bins/agent/{bin,runtime,downloads} /data-volumes/anspire-fde-hub/knodo/.knodo/agent/

# 1. 准备 .env
cd projects/anspire-fde-hub
cp .env.example .env
vi .env   # 填 KNODO_INSTALL_URL + OCS_HOST

# 2. 拉 base + 启动
docker pull myg133/openvscode-server:rust-bun-knodo
docker compose up -d
```

## 验证

```bash
# knodo-agent 健康 (容器内, 跳过 download 走秒级激活)
docker exec ocs-anspire-fde-hub curl 127.0.0.1:9910/health

# OCS UI (走 Traefik 域名)
curl -k https://fde-hub.localdev.anspire.cn

# knodo 集成测试
docker exec ocs-anspire-fde-hub bash /usr/local/bin/test-knodo-integration.sh

# 验证 rust + bun 在容器内可用
docker exec ocs-anspire-fde-hub bash -c 'which rustc cargo bun && rustc --version && bun --version'

# Traefik 是不是发现 router
docker logs traefik --since 1m 2>&1 | grep fde-hub | tail -5
```

## Base 镜像更新

```bash
docker pull myg133/openvscode-server:rust-bun-knodo
docker compose up -d --force-recreate
```

## 文件

- `docker-compose.yml` — 容器编排
- `.env.example` — 环境变量模板
- NFS volume 数据**不在 git**，由 NFS server 持有
