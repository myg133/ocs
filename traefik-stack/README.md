# Traefik 反向代理 + DNSPod 自动证书

`myg133/openvscode-server:<lang>-knodo` 系列容器的统一入口, HTTPS 走 Let's Encrypt (DNS-01 挑战, DNSPod API 自动加 TXT 记录)。

## 文件结构

```
traefik-stack/
├── docker-compose.yml      # Traefik 服务
├── traefik.yml             # 静态配置 (entrypoints, DNS-01, providers)
├── dynamic/
│   └── middlewares.yml     # 共享中间件 (headers / rate-limit)
├── .env.example            # DNSPOD_API_KEY + ACME_EMAIL + 域名
└── README.md
```

## 一次性准备

### 1. DNSPod 加 A 记录 (手动, 5 秒)

登录 https://console.dnspod.cn → 你的域名 → 记录管理:

| 主机记录 | 记录类型 | 记录值 | 备注 |
|---|---|---|---|
| `py-knodo` | A | `172.25.93.9` (你的 docker 主机内网 IP) | py-knodo 子域 |
| `njs-knodo` | A | `172.25.93.9` | njs-knodo 子域 |

> 记录值是**内网 IP**, 流量不出公网, 外部客户端访问不到, 安全。
> Let's Encrypt 验证只看 TXT 记录 (DNS-01), 不看 A 记录指向哪。

### 2. 拿腾讯云 CAM 密钥 (不是 DNSPod 老 token)

https://console.cloud.tencent.com/cam/capi → 新建密钥

权限**别**给 `QcloudDNSPodFullAccess` (太大), 自定义策略只给 DNSPod 这 3 个 API:
- `DescribeRecordList` (查记录)
- `CreateRecord` (加 _acme-challenge TXT)
- `DeleteRecord` (删 _acme-challenge TXT)

拿到:
- `SecretId` (类似 `AKIDxxxxxxxxxxxxx`)
- `SecretKey` (一长串字符)

### 3. 创建共享 Docker network

让 Traefik 和 knodo 容器在同一个 network 上, Traefik 才能通过 DNS 发现它们:

```powershell
docker network create traefik-net
```

**只创建一次**, 之后所有 knodo compose 都要用这个 network 名。

### 4. 配置 .env

```bash
cp .env.example .env
# 编辑 .env, 填:
#   DNSPOD_API_KEY=<你的 id,token>
#   ACME_EMAIL=<你的邮箱>
#   DOMAIN=<你的主域名, 例如 yourname.cn>
#   PY_KNODO_HOST=py-knodo.<主域>
#   NJS_KNODO_HOST=njs-knodo.<主域>
```

### 5. 启 Traefik

```bash
docker compose --env-file .env up -d
docker compose logs -f
```

**期望日志**:
```
INFO  Traefik 已启动
... (DNSPod API 调用 + acme 证书申请)
```

**首次启动慢 (1-2 分钟)**: 申请第一个证书会触发 DNS-01 挑战。

## 验证

### 1. Dashboard

```bash
# 浏览器开 (仅本机)
open http://localhost:8080
```

**期望**: 看到 Traefik dashboard, 列出 routers / services / middlewares。

### 2. 证书状态

```bash
# 容器内查证书
docker exec traefik ls -la /letsencrypt/
docker exec traefik cat /letsencrypt/acme.json | head -30
```

**期望**: `acme.json` 里有 `py-knodo.your-domain.com` 的证书条目。

### 3. HTTPS 路由

```bash
# 等 Traefik 起来 + 证书申请完, 跑
curl -I https://py-knodo.your-domain.com
curl -I https://njs-knodo.your-domain.com
```

**期望**:
```
HTTP/2 200
server: openvscode-server (或类似)
strict-transport-security: max-age=31536000
```

## 启动 knodo 容器

Traefik 起来后, 启 knodo 容器 (它们要 join `traefik-net` network):

```powershell
cd D:\MyCodes\docker\ocs\python-knodo
docker compose up -d

cd D:\MyCodes\docker\ocs\njs-knodo
docker compose up -d
```

每个 compose 都已经配好 labels 和 network, 起来后 Traefik 自动发现并加路由。

## 排错

### 1. "TencentCloud auth error 401/403"

- 检查 `.env` 里 `TENCENTCLOUD_SECRET_ID` / `TENCENTCLOUD_SECRET_KEY` 是不是复制完整 (没空格没换行)
- 确认 CAM 子账号绑定的自定义策略有 DNSPod 资源的相关 API 权限 (`DescribeRecordList` / `CreateRecord` / `DeleteRecord`)
- 看 Traefik 日志: `docker logs traefik | grep -i tencent`

### 2. "no such host: py-knodo.example.com" (DNS 不解析)

- DNSPod A 记录没加, 或刚加还没传播 (DNSPod 通常秒级)
- 验证: `nslookup py-knodo.your-domain.com 119.29.29.29` (用 DNSPod DNS 查询)

### 3. "Gateway Timeout" / 502

- knodo 容器没 join `traefik-net`, 或没起
- 看 Traefik dashboard → routers 状态
- 看 knodo 容器 logs: `docker logs ocs-py-knodo`

### 4. 证书申请卡住

- DNSPod API 调用失败 (看 Traefik 日志)
- DNS 记录加了但没传完 (等 60s `delayBeforeCheck`)
- 域名本身有问题 (A 记录 / 解析 / DNSPod 状态)

## 升级

```bash
docker compose pull
docker compose up -d
```

Traefik 镜像小, 升级不影响证书 (证书在 `traefik-certs` volume 里)。

## 清理

```bash
# 停 + 删容器 (保留证书和 network)
docker compose down

# 彻底删证书 (下次重启要重新申请, 一般不要)
docker volume rm traefik-certs
```
