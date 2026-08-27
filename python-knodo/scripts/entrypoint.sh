#!/usr/bin/env bash
# knodo-agent + openvscode-server 双进程入口
#
# 决策流程:
#   1. 若 $HOME/.knodo/agent/config/agent.env 存在且 API_TOKEN 非空 → 复用（持久化场景）
#   2. 否则若 BACKEND_WS_URL + API_TOKEN 环境变量齐备 → 直接渲染 env（长期凭证）
#   3. 否则若 KNODO_INSTALL_URL 环境变量存在 → 调 knodo 官方安装脚本激活（首次 / 24h 内）
#   4. 否则 fail
#
# 不论走哪条路径, 最后都后台拉起 knodo-agent, 然后 exec openvscode-server 占住 PID 1。
# 容器退出时两个进程一起死, 这对 dev container 是预期行为。

set -euo pipefail

# ---- 阶段 0: 修复 volume 权限 (root only, 然后降权) ----
# 远端 daemon 创建的 named volume 默认 root 拥有, openvscode-server 写不进去
# 这里以 root 身份 mkdir + chown, 然后 exec sudo -u openvscode-server 重跑本脚本
if [ "$(id -u)" -eq 0 ]; then
    mkdir -p /home/workspace/.knodo/agent/bin \
             /home/workspace/.knodo/agent/config \
             /home/workspace/.knodo/agent/logs \
             /home/workspace/.knodo/agent/run \
             /home/workspace/.knodo/agent/downloads \
             /home/workspace/.knodo/agent/claude \
             /home/workspace/.knodo/agent/codex \
             /home/workspace/.knodo/data
    # 改所有权 (已有文件也改, 适配旧 volume)
    chown -R openvscode-server:openvscode-server /home/workspace/.knodo 2>/dev/null || true
    # 显式设 HOME 再降权, 避免被 sudo 切到 /root
    export HOME=/home/workspace
    exec sudo -u openvscode-server -E "$0" "$@"
fi

# ---- 用户/路径 (从这行开始是 openvscode-server 身份) ----
# 跟原 python/ 镜像保持一致: openvscode-server 用户, HOME=/home/workspace
export HOME="${HOME:-/home/workspace}"
AGENT_ROOT="${HOME}/.knodo/agent"
AGENT_BIN_DIR="${AGENT_ROOT}/bin"
AGENT_CONFIG_DIR="${AGENT_ROOT}/config"
AGENT_LOG_DIR="${AGENT_ROOT}/logs"
AGENT_RUN_DIR="${AGENT_ROOT}/run"
AGENT_DATA_DIR="${HOME}/.knodo/data"
AGENT_ENV_FILE="${AGENT_CONFIG_DIR}/agent.env"
AGENT_CLI="${AGENT_BIN_DIR}/knodo-agent"
AGENT_DAEMON="${AGENT_BIN_DIR}/knodo-agentd"
KNODO_AGENT_PORT="${KNODO_AGENT_PORT:-9910}"

# ---- 日志辅助 ----
log()  { printf '[entrypoint] %s\n' "$*"; }
warn() { printf '[entrypoint][WARN] %s\n' "$*" >&2; }
fail() { printf '[entrypoint][ERROR] %s\n' "$*" >&2; exit 1; }

mkdir -p "${AGENT_CONFIG_DIR}" "${AGENT_LOG_DIR}" "${AGENT_RUN_DIR}" "${AGENT_DATA_DIR}"

# ---- 探测当前状态 ----
agent_already_provisioned() {
    [ -x "${AGENT_DAEMON}" ] && [ -f "${AGENT_ENV_FILE}" ] \
        && grep -qE "^API_TOKEN='[^']+'" "${AGENT_ENV_FILE}" 2>/dev/null
}

env_credentials_supplied() {
    [ -n "${BACKEND_WS_URL:-}" ] && [ -n "${API_TOKEN:-}" ]
}

install_url_supplied() {
    [ -n "${KNODO_INSTALL_URL:-}" ]
}

# ---- 路径 1: 复用已配置状态 ----
if agent_already_provisioned; then
    log "已检测到 ${AGENT_ENV_FILE} 且 API_TOKEN 非空, 复用现有配置"
# ---- 路径 2: 用长期凭证直接渲染 env ----
elif env_credentials_supplied; then
    log "BACKEND_WS_URL + API_TOKEN 已注入, 渲染 agent.env"
    /usr/local/bin/render-agent-env.sh
# ---- 路径 3: 调 knodo 官方安装脚本激活 ----
elif install_url_supplied; then
    log "首次启动, 使用 KNODO_INSTALL_URL 激活"
    /usr/local/bin/install-knodo-agent.sh "${KNODO_INSTALL_URL}"
    if ! agent_already_provisioned; then
        fail "knodo 安装脚本跑完但 ${AGENT_ENV_FILE} 没生成, 请检查日志 ${AGENT_LOG_DIR}/stderr.log"
    fi
    log "激活完成, 凭证已存到 ${AGENT_ENV_FILE}"
    log "建议运行 ./scripts/extract-knodo-credentials.sh --write-backup 备份长期凭证"
else
    fail "缺少 knodo 凭证: 请设置 KNODO_INSTALL_URL (首次激活) 或 BACKEND_WS_URL+API_TOKEN (长期凭证)"
fi

# ---- 拉起 agent (后台, supervised 模式) ----
log "启动 knodo-agent (端口 ${KNODO_AGENT_PORT})"
if [ -x "${AGENT_CLI}" ]; then
    "${AGENT_CLI}" start -d
else
    # 兜底: 没有管理 CLI 时直接拉 daemon, 让它自愈
    warn "未找到 ${AGENT_CLI}, 走裸 daemon 路径, 不会自动重启"
    nohup "${AGENT_DAEMON}" >>"${AGENT_LOG_DIR}/stdout.log" 2>>"${AGENT_LOG_DIR}/stderr.log" &
    disown || true
fi

# 健康检查 (最多 15s)
log "等待 knodo-agent 健康检查..."
for i in $(seq 1 15); do
    if curl -fsS "http://127.0.0.1:${KNODO_AGENT_PORT}/health" >/dev/null 2>&1; then
        log "knodo-agent 已就绪"
        break
    fi
    sleep 1
    if [ "$i" -eq 15 ]; then
        warn "knodo-agent 启动超时, 继续启动 openvscode-server (agent 错误请查 ${AGENT_LOG_DIR}/stderr.log)"
    fi
done

# ---- 前台 exec openvscode-server (PID 1) ----
log "启动 openvscode-server"
exec "${OPENVSCODE}" --host 0.0.0.0 --port 3000 --without-connection-token "${@}"
