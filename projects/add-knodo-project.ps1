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
    [Parameter(Mandatory = $true)][ValidateSet('py', 'njs')][string]$Base  # base 类型: py 或 njs
)

$ErrorActionPreference = 'Stop'

# ---- 端口分配 (自动找空闲端口, 从 3200/3300 起) ----
$existingDirs = Get-ChildItem -Directory | Where-Object { $_.Name -ne 'add-knodo-project.ps1' }
$pyCount = ($existingDirs | Where-Object { (Get-Content "$($_.Name)\docker-compose.yml" -ErrorAction SilentlyContinue) -match ':py-knodo' }).Count
$njsCount = ($existingDirs | Where-Object { (Get-Content "$($_.Name)\docker-compose.yml" -ErrorAction SilentlyContinue) -match ':njs-knodo' }).Count

if ($Base -eq 'py') {
    $ovssPort = 3200 + $pyCount * 100   # 3200, 3400, 3600, ...
} else {
    $ovssPort = 3300 + $njsCount * 100  # 3300, 3500, 3700, ...
}
$knodoPort = $ovssPort + 20              # 3200 -> 9920, 3300 -> 9930

# ---- slug = 项目名第一段, 大写 (e.g. anspire-bi-frontend -> ANSPIRE) ----
$slug = ($Name -split '-')[0].ToUpper()
$routerName = $Name -split '-' | Select-Object -Skip 1 | Select-Object -First 1
if (-not $routerName) { $routerName = $slug.ToLower() }
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
    ports:
      # host 端口 (自动分配: $ovssPort / $knodoPort)
      - "`${OVSS_HOST_PORT:-$ovssPort}:3000"
      - "`${KNODO_HOST_PORT:-$knodoPort}:9910"
    environment:
      - KNODO_INSTALL_URL=`${KNODO_INSTALL_URL:-}
      - BACKEND_WS_URL=`${BACKEND_WS_URL:-}
      - API_TOKEN=`${API_TOKEN:-}
      - KNODO_AGENT_PORT=9910
      - HTTP_PROXY=`${HTTP_PROXY:-}
      - HTTPS_PROXY=`${HTTPS_PROXY:-}
      - NO_PROXY=`${NO_PROXY:-}
    volumes:
      - knodo-state:/home/workspace/.knodo
      - project-data:/home/workspace/project
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.$routerName.rule=Host(`${$slug`HOST:?$slug`HOST required})"
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

# Traefik 路由域名 (泛域 *.localdev.anspire.cn 已签 cert)
$($slug)HOST=$routerName.localdev.anspire.cn

# host 端口 (跟其他项目错开)
OVSS_HOST_PORT=$ovssPort
KNODO_HOST_PORT=$knodoPort
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
Write-Host "  2. cp .env.example .env && vi .env  (填 KNODO_INSTALL_URL + $slug`HOST)"
Write-Host "  3. 服务器: ssh 172.25.93.9 \"mkdir -p /data-volumes/$Name/{knodo,project} && chmod 777 /data-volumes/$Name/\""
Write-Host "  4. 服务器: cd /path/to/projects/$Name && docker pull myg133/openvscode-server:$Base-knodo && docker compose up -d"
Write-Host ""
Write-Host "端口自动分配: OVS=$ovssPort / knodo=$knodoPort" -ForegroundColor Yellow
Write-Host "域名自动分配: $routerName.localdev.anspire.cn" -ForegroundColor Yellow
Write-Host "Traefik router: $routerName" -ForegroundColor Yellow
Write-Host "NFS 路径: /data-volumes/$Name/{knodo,project}" -ForegroundColor Yellow
