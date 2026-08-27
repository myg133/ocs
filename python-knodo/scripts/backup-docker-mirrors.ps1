# Docker Desktop mirror 临时切换辅助脚本
# 用途: 临时清空 registry-mirrors 让 docker 直连 docker.io 拉私有镜像
# 用法:
#   .\backup-docker-mirrors.ps1 -Backup    # 备份当前配置
#   .\backup-docker-mirrors.ps1 -Clear     # 清空 mirrors (之后手动 Apply & restart)
#   .\backup-docker-mirrors.ps1 -Restore   # 还原
#   .\backup-docker-mirrors.ps1 -Status    # 看当前状态

param(
    [switch]$Backup,
    [switch]$Clear,
    [switch]$Restore,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'

# Docker Desktop Windows 配置文件路径
$possiblePaths = @(
    "$env:APPDATA\Docker\settings.json",
    "$env:LOCALAPPDATA\Docker\settings.json"
)

$configPath = $null
foreach ($p in $possiblePaths) {
    if (Test-Path -Path $p -PathType Leaf) {
        $configPath = $p
        break
    }
}

$backupDir = "$PSScriptRoot\.docker-config-backup"
$backupFile = "$backupDir\settings.json.bak"

if (-not (Test-Path $backupDir)) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
}

if ($Status) {
    if (-not $configPath) {
        Write-Host "[!] 找不到 Docker Desktop 配置文件, 请手动检查" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[*] 配置文件: $configPath"
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    if ($cfg.'registry-mirrors') {
        Write-Host "[*] 当前 registry-mirrors:"
        $cfg.'registry-mirrors' | ForEach-Object { Write-Host "    - $_" }
    } else {
        Write-Host "[*] 当前无 registry-mirrors 配置 (直连 docker.io)"
    }
    exit 0
}

if ($Backup) {
    if (-not $configPath) {
        Write-Host "[!] 找不到配置文件" -ForegroundColor Red
        exit 1
    }
    Copy-Item -Path $configPath -Destination $backupFile -Force
    Write-Host "[OK] 备份到: $backupFile"
    exit 0
}

if ($Clear) {
    if (-not $configPath) {
        Write-Host "[!] 找不到配置文件" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path $backupFile)) {
        Copy-Item -Path $configPath -Destination $backupFile -Force
        Write-Host "[*] 自动备份到: $backupFile"
    }
    $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
    $cfg | Add-Member -NotePropertyName 'registry-mirrors' -NotePropertyValue @() -Force
    $json = $cfg | ConvertTo-Json -Depth 10
    Set-Content -Path $configPath -Value $json -Encoding UTF8
    Write-Host "[OK] 已清空 registry-mirrors, 现在去 Docker Desktop 点 Apply & restart"
    Write-Host "    (点完之后等 30s~2min, Docker Desktop 图标稳定后再 build)"
    exit 0
}

if ($Restore) {
    if (-not (Test-Path $backupFile)) {
        Write-Host "[!] 找不到备份: $backupFile" -ForegroundColor Red
        exit 1
    }
    if (-not $configPath) {
        Write-Host "[!] 找不到配置文件" -ForegroundColor Red
        exit 1
    }
    Copy-Item -Path $backupFile -Destination $configPath -Force
    Write-Host "[OK] 已还原, 现在去 Docker Desktop 点 Apply & restart"
    exit 0
}

# 没有任何参数, 打 usage
Write-Host @"
用法:
    .\backup-docker-mirrors.ps1 -Status     看当前 mirrors
    .\backup-docker-mirrors.ps1 -Backup     备份
    .\backup-docker-mirrors.ps1 -Clear      清空 (然后手动 Apply & restart)
    .\backup-docker-mirrors.ps1 -Restore    还原 (然后手动 Apply & restart)
"@
