#!/usr/bin/env bash
# 从运行中的容器里提取 knodo 长期凭证, 备份到本地
# 用法:
#   ./scripts/extract-knodo-credentials.sh                  # 直接打印
#   ./scripts/extract-knodo-credentials.sh --write-env      # 追加/更新到 .env
#   ./scripts/extract-knodo-credentials.sh --write-backup   # 写到 .env.knodo-backup (推荐)

set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-ocs-py-knodo}"
ENV_FILE_INSIDE='$HOME/.knodo/agent/config/agent.env'
OUTPUT=""
WRITE_TARGET=""

while [ $# -gt 0 ]; do
    case "$1" in
        --write-env)    WRITE_TARGET=".env" ;;
        --write-backup) WRITE_TARGET=".env.knodo-backup" ;;
        -h|--help)
            sed -n '2,8p' "$0"
            exit 0
            ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

# 检查容器在不在
if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "[错误] 容器 ${CONTAINER_NAME} 不存在, 先 docker compose up -d" >&2
    exit 1
fi

# 从容器里读 agent.env
AGENT_ENV=$(docker exec "${CONTAINER_NAME}" sh -c "cat ${ENV_FILE_INSIDE}" 2>/dev/null) || {
    echo "[错误] 读不到 ${ENV_FILE_INSIDE}, 容器可能还没激活完" >&2
    exit 1
}

BACKEND_WS_URL=$(printf '%s' "${AGENT_ENV}" | grep -E '^BACKEND_WS_URL=' | head -1 | cut -d"'" -f2)
API_TOKEN=$(printf '%s' "${AGENT_ENV}" | grep -E '^API_TOKEN=' | head -1 | cut -d"'" -f2)

if [ -z "${BACKEND_WS_URL}" ] || [ -z "${API_TOKEN}" ]; then
    echo "[错误] agent.env 里没找到 BACKEND_WS_URL / API_TOKEN" >&2
    exit 1
fi

# 输出
printf '\n=== knodo 长期凭证 (请妥善保管) ===\n'
printf 'BACKEND_WS_URL=%s\n' "${BACKEND_WS_URL}"
printf 'API_TOKEN=%s\n'      "${API_TOKEN}"
printf '====================================\n'

# 写到 .env
if [ -n "${WRITE_TARGET}" ]; then
    if [ -f "${WRITE_TARGET}" ]; then
        # 删掉旧值再追加
        tmp=$(mktemp)
        grep -v -E '^(BACKEND_WS_URL|API_TOKEN)=' "${WRITE_TARGET}" > "${tmp}" || true
        mv "${tmp}" "${WRITE_TARGET}"
    fi
    {
        printf '\n# 长期凭证 (extract-knodo-credentials.sh 自动写入, %s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'BACKEND_WS_URL=%s\n' "${BACKEND_WS_URL}"
        printf 'API_TOKEN=%s\n'      "${API_TOKEN}"
    } >> "${WRITE_TARGET}"
    echo "[OK] 已写入 ${WRITE_TARGET}"
    echo "     下次容器启动 (如果 named volume 丢了) 会自动用这两个凭证, 不再需要 KNODO_INSTALL_URL"
fi
