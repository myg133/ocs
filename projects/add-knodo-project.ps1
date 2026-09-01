# =============================================================================
# add-knodo-project.ps1 - 一键生成新项目骨架
#
# 用法:
#   cd D:\MyCodes\docker\ocs\projects
#   .\add-knodo-project.ps1 -Name anspire-bi-frontend -Base njs
#
# 效果:
#   - 创建 projects/<name>/ 目录
#   - 生成 docker-compose.yml (用 base image myg133/openvscode-server:<base>-knodo)
#   - 生成 .env.example (按端口约定自动选)
#   - 生成 README.md
#
# ⚠️ 跑前准备:
#   1. 在 NFS server 上: mkdir -p /data-volumes/<name>/{knodo,project} && chmod 777
#   2. 在 DNSPod 加 A 记录 (子域跟 *.localdev 泛域匹配)
# =============================================================================

param(
    [Parameter(Mandatory = $true)][string]$Name,   # 项目名 (kebab-case, e.g. anspire-bi-frontend)
    [Parameter(Mandatory = $true)][ValidateSet('python', 'njs')][string]$Base  # base 类型: python 或 njs (对应镜像标签 python-knodo / njs-knodo)
)

$ErrorActionPreference = 'Stop'

# ---- router name = 项目名第二段 (e.g. anspire-search-frontend -> 'search') ----
# Traefik router name 必须项目特定 (避免冲突), 但域名变量统一用 OCS_HOST
$routerName = ($Name -split '-') | Select-Object -Skip 1 | Select-Object -First 1
if (-not $routerName) { $routerName = $Name }
$RouterName = $routerName.Substring(0, 1).ToUpper() + $routerName.Substring(1).ToLower()

# ---- 项目目录 ----
$projectDir = Join-Path (Get-Location) $Name
if (Test-Path $projectDir) {
    Write-Error "项目目录已存在: $projectDir"
    exit 1
}
New-Item -ItemType Directory -Path $projectDir -Force | Out-Null

# ---- docker-compose.yml 模板 ----
$compose = @"
# =============================================================================
# $Name 项目部署
# 基于 base image: myg133/openvscode-server:$Base-knodo
# 自动生成于 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# =============================================================================

services:
  openvscode-server:
    image: myg133/openvscode-server:$Base-knodo
    container_name: ocs-$Name
    restart: unless-stopped
    # host 端口不暴露, 外部访问全走 Traefik
    # 调试: docker exec -it ocs-$Name bash
    #       docker exec ocs-$Name curl 127.0.0.1:9910/health
    environment:
      - KNODO_INSTALL_URL=`${KNODO_INSTALL_URL:-}
      - BACKEND_WS_URL=`${BACKEND_WS_URL:-}
      - API_TOKEN=`${API_TOKEN:-}
      - KNODO_AGENT_PORT=9910
      # === 清空 base image 继承的公司代理 (172.25.93.8:10808) ===
      # base image (myg133/openvscode-server:base-latest) 烤了 HTTP_PROXY 等 env,
      # 走公司代理到 knodo CDN 慢 (155 KB/s). 显式清空让 curl 直连 (1.12 MB/s, 7x 加速)
      # 大写 + 小写都要清 (curl 优先用小写)
      - HTTP_PROXY=
      - HTTPS_PROXY=
      - http_proxy=
      - https_proxy=
      - NO_PROXY=localhost,127.0.0.1,anchnet.knodo.vip
      - no_proxy=localhost,127.0.0.1,anchnet.knodo.vip
    volumes:
      - knodo-state:/home/workspace/.knodo
      - project-data:/home/workspace/project
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.$routerName.rule=Host(`${OCS_HOST:?OCS_HOST required})"
      - "traefik.http.routers.$routerName.entrypoints=websecure"
      - "traefik.http.routers.$routerName.tls=true"
      - "traefik.http.services.$routerName.loadbalancer.server.port=3000"
    networks:
      - traefik-net
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://127.0.0.1:3000/healthz || exit 0"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 60s

volumes:
  knodo-state:
    driver: local
    driver_opts:
      type: nfs
      o: addr=172.25.93.9,rw,sync,hard,intr,noatime
      device: ":/data-volumes/$Name/knodo"
  project-data:
    driver: local
    driver_opts:
      type: nfs
      o: addr=172.25.93.9,rw,sync,hard,intr,noatime
      device: ":/data-volumes/$Name/project"

networks:
  traefik-net:
    external: true
    name: traefik-net
"@

# ---- .env.example 模板 ----
$envExample = @"
# $Name 项目 .env 模板
# 复制: cp .env.example .env

# knodo 首次激活 URL (24h 有效, 激活后写到 NFS volume 自动复用)
KNODO_INSTALL_URL=https://anchnet.knodo.vip/api/v1/public/install/local/<YOUR_TOKEN>?origin=https%3A%2F%2Fanchnet.knodo.vip

# Traefik 路由域名 (所有项目统一用 OCS_HOST)
# 泛域 *.localdev.anspire.cn 已签 cert
OCS_HOST=$routerName.localdev.anspire.cn
"@

# ---- README.md 模板 ----
$readme = @"
# $Name

OCS + knodo 项目部署 ($Base)。

## 架构

- Base image: \`myg133/openvscode-server:$Base-knodo\`
- 域名: \`$routerName.localdev.anspire.cn\`
- 端口: $ovssPort (UI) / $knodoPort (knodo-agent)
- 存储: NFS \`172.25.93.9:/data-volumes/$Name/{knodo,project}\`

## 部署

\`\`\`bash
# 1. NFS server 建目录
ssh 172.25.93.9 "mkdir -p /data-volumes/$Name/{knodo,project} && chmod 777 /data-volumes/$Name/"

# 2. 准备 .env
cp .env.example .env
vi .env

# 3. 拉 base + 启动
docker pull myg133/openvscode-server:$Base-knodo
docker compose up -d
\`\`\`
"@

# ---- 写入文件 ----
Set-Content -Path (Join-Path $projectDir 'docker-compose.yml') -Value $compose -Encoding UTF8
Set-Content -Path (Join-Path $projectDir '.env.example') -Value $envExample -Encoding UTF8
Set-Content -Path (Join-Path $projectDir 'README.md') -Value $readme -Encoding UTF8

Write-Host ""
Write-Host "项目骨架已生成: $projectDir" -ForegroundColor Green
Write-Host ""
Write-Host "下一步:" -ForegroundColor Cyan
Write-Host "  1. cd $Name"
Write-Host "  2. cp .env.example .env && vi .env  (填 KNODO_INSTALL_URL + OCS_HOST)"
Write-Host "  3. 服务器: ssh 172.25.93.9 \"mkdir -p /data-volumes/$Name/{knodo,project} && chmod 777 /data-volumes/$Name/\""
Write-Host "  4. 服务器: cd /path/to/projects/$Name && docker pull myg133/openvscode-server:$Base-knodo && docker compose up -d"
Write-Host ""
Write-Host "域名自动分配: $routerName.localdev.anspire.cn" -ForegroundColor Yellow
Write-Host "Traefik router: $routerName" -ForegroundColor Yellow
Write-Host "NFS 路径: /data-volumes/$Name/{knodo,project}" -ForegroundColor Yellow
