#!/usr/bin/env bash
# 直接从环境变量渲染 agent.env, 跳过 knodo 安装脚本和 activate 接口
#
# 适用场景: 已有长期凭证 (BACKEND_WS_URL + API_TOKEN), 想避免 24h install URL 流程
# 前置条件: 二进制已预装 (build 阶段烤进去, 或从别处 cp 过来)
#   - $HOME/.knodo/agent/bin/knodo-agentd
#   - $HOME/.knodo/agent/bin/knodo-agent  (管理 CLI, 来自 knodo 脚本的 write_management_cli 段)
#   - $HOME/.knodo/agent/claude/claude    (Claude Code bundle, 可选)
#   - $HOME/.knodo/agent/codex/codex      (Codex bundle, 可选)
#   - $HOME/.knodo/agent/bin/claude       (wrapper, 可选)
#   - $HOME/.knodo/agent/bin/codex        (wrapper, 可选)

set -euo pipefail

: "${HOME:?HOME 必须由 entrypoint 设置}"
: "${BACKEND_WS_URL:?缺少 BACKEND_WS_URL}"
: "${API_TOKEN:?缺少 API_TOKEN}"

KNODO_AGENT_PORT="${KNODO_AGENT_PORT:-9910}"

AGENT_ROOT="${HOME}/.knodo/agent"
AGENT_BIN_DIR="${AGENT_ROOT}/bin"
AGENT_CONFIG_DIR="${AGENT_ROOT}/config"
AGENT_LOG_DIR="${AGENT_ROOT}/logs"
AGENT_RUN_DIR="${AGENT_ROOT}/run"
AGENT_DATA_DIR="${HOME}/.knodo/data"
AGENT_ENV_FILE="${AGENT_CONFIG_DIR}/agent.env"
AGENT_DAEMON="${AGENT_BIN_DIR}/knodo-agentd"
CLAUDE_DIR="${AGENT_ROOT}/claude"
CODEX_DIR="${AGENT_ROOT}/codex"
CLAUDE_LAUNCHER="${CLAUDE_DIR}/claude"
CODEX_LAUNCHER="${CODEX_DIR}/codex"

[ -x "${AGENT_DAEMON}" ] || { echo "[ERROR] 缺 daemon: ${AGENT_DAEMON} (请先预装)" >&2; exit 1; }

mkdir -p "${AGENT_CONFIG_DIR}" "${AGENT_LOG_DIR}" "${AGENT_RUN_DIR}" \
         "${AGENT_DATA_DIR}" "${AGENT_ROOT}/downloads"

# 探测 Claude / Codex 是否存在, 决定 wrapper 路径
CLAUDE_CLI_PATH_VALUE="${CLAUDE_LAUNCHER}"
CODEX_CLI_PATH_VALUE="${CODEX_LAUNCHER}"
[ -x "${CLAUDE_LAUNCHER}" ] || CLAUDE_CLI_PATH_VALUE=""
[ -x "${CODEX_LAUNCHER}" ]  || CODEX_CLI_PATH_VALUE=""

# 写 env 文件 (字段顺序跟 knodo 脚本 render_env_file 保持一致)
cat >"${AGENT_ENV_FILE}" <<EOF
BACKEND_WS_URL='${BACKEND_WS_URL}'
API_TOKEN='${API_TOKEN}'
PORT='${KNODO_AGENT_PORT}'
LOCAL_AGENT_SLOT='blue'
LOCAL_AGENT_BLUE_PORT='${KNODO_AGENT_PORT}'
LOCAL_AGENT_GREEN_PORT='${KNODO_AGENT_PORT}'
LOCAL_AGENT_PRIMARY_PORT='${KNODO_AGENT_PORT}'
LOCAL_AGENT_SECONDARY_PORT='${KNODO_AGENT_PORT}'
LOG_DIR='${AGENT_LOG_DIR}'
LOG_MAX_FILES='20'
LOCAL_AGENT_MODE='true'
NODE_USE_SYSTEM_CA='1'
DATA_CONTAINER_DIR='${AGENT_DATA_DIR}'
LOCAL_AGENT_EXECUTABLE_PATH='${AGENT_DAEMON}'
LOCAL_AGENT_BUILD_VERSION='${LOCAL_AGENT_BUILD_VERSION:-baked}'
CONSOLE_LOG_LEVEL='${CONSOLE_LOG_LEVEL:-silent}'
CLAUDE_CLI_PATH='${CLAUDE_CLI_PATH_VALUE}'
CLAUDE_CODE_VERSION='${CLAUDE_CODE_VERSION:-baked}'
CODEX_CLI_PATH='${CODEX_CLI_PATH_VALUE}'
CODEX_VERSION='${CODEX_VERSION:-baked}'
LOCAL_AGENT_ENV_FILE='${AGENT_ENV_FILE}'
LOCAL_AGENT_PLATFORM='${LOCAL_AGENT_PLATFORM:-linux-x64}'
LOCAL_AGENT_BINARY_SHA256='${LOCAL_AGENT_BINARY_SHA256:-baked}'
CLAUDE_BUNDLE_SHA256='${CLAUDE_BUNDLE_SHA256:-baked}'
CODEX_BUNDLE_SHA256='${CODEX_BUNDLE_SHA256:-baked}'
EOF

# 代理 (可选, 全部以单引号写入避免解析问题)
if [ -n "${HTTP_PROXY:-}" ]; then
    printf "HTTP_PROXY='%s'\n" "${HTTP_PROXY}" >>"${AGENT_ENV_FILE}"
    printf "http_proxy='%s'\n" "${HTTP_PROXY}" >>"${AGENT_ENV_FILE}"
fi
if [ -n "${HTTPS_PROXY:-}" ]; then
    printf "HTTPS_PROXY='%s'\n" "${HTTPS_PROXY}" >>"${AGENT_ENV_FILE}"
    printf "https_proxy='%s'\n" "${HTTPS_PROXY}" >>"${AGENT_ENV_FILE}"
fi
if [ -n "${NO_PROXY:-}" ]; then
    printf "NO_PROXY='%s'\n" "${NO_PROXY}" >>"${AGENT_ENV_FILE}"
    printf "no_proxy='%s'\n" "${NO_PROXY}" >>"${AGENT_ENV_FILE}"
fi

# 写 Claude / Codex wrapper (如果二进制存在)
if [ -n "${CLAUDE_CLI_PATH_VALUE}" ]; then
    cat >"${AGENT_BIN_DIR}/claude" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec "${CLAUDE_CLI_PATH_VALUE}" "\$@"
WRAPPER
    chmod +x "${AGENT_BIN_DIR}/claude"
fi

if [ -n "${CODEX_CLI_PATH_VALUE}" ]; then
    cat >"${AGENT_BIN_DIR}/codex" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec "${CODEX_CLI_PATH_VALUE}" "\$@"
WRAPPER
    chmod +x "${AGENT_BIN_DIR}/codex"
fi

echo "[render-agent-env] 已写入 ${AGENT_ENV_FILE}"
