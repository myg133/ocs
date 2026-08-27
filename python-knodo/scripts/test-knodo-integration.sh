#!/usr/bin/env bash
# 在跑着的容器里执行: 验证 knodo-agent 是否正常工作
# 用法: docker compose exec openvscode-server bash /usr/local/bin/test-knodo-integration.sh
#      或: docker compose exec openvscode-server bash  # 然后手动跑下面这些命令

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

pass() { printf "${GREEN}[PASS]${NC} %s\n" "$*"; }
fail() { printf "${RED}[FAIL]${NC} %s\n" "$*" >&2; exit 1; }
info() { printf "${YELLOW}[INFO]${NC} %s\n" "$*"; }

info "==== knodo-agent 集成测试 ===="

# 1. agentd 存在 + 可执行
[ -x "$HOME/.knodo/agent/bin/knodo-agentd" ] \
    && pass "knodo-agentd 二进制存在: $($HOME/.knodo/agent/bin/knodo-agentd --version 2>&1 | head -1 || echo '无 version 输出')" \
    || fail "knodo-agentd 缺失, 安装没跑成功"

# 2. 管理 CLI 存在
[ -x "$HOME/.knodo/agent/bin/knodo-agent" ] \
    && pass "管理 CLI 存在" \
    || fail "管理 CLI 缺失"

# 3. agent.env 写好且有 API_TOKEN
ENV_FILE="$HOME/.knodo/agent/config/agent.env"
[ -f "$ENV_FILE" ] || fail "agent.env 不存在"
grep -qE "^API_TOKEN='[^']+'" "$ENV_FILE" \
    && pass "agent.env 含 API_TOKEN" \
    || fail "agent.env 缺 API_TOKEN"

# 4. 关键字段都有
for field in BACKEND_WS_URL PORT LOG_DIR; do
    if grep -qE "^${field}=" "$ENV_FILE"; then
        pass "agent.env 含 ${field}"
    else
        fail "agent.env 缺 ${field}"
    fi
done

# 5. 健康检查
PORT=$(grep -E "^PORT=" "$ENV_FILE" | head -1 | cut -d"'" -f2)
PORT="${PORT:-9910}"
if curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    pass "健康检查 OK (端口 ${PORT})"
    curl -fsS "http://127.0.0.1:${PORT}/health"
    echo
else
    fail "健康检查失败: http://127.0.0.1:${PORT}/health"
fi

# 6. agent 状态
info "==== knodo-agent status ===="
$HOME/.knodo/agent/bin/knodo-agent status || true

# 7. 关键路径
info "==== 关键路径 ===="
for p in "$HOME/.knodo/agent/bin" "$HOME/.knodo/agent/config" "$HOME/.knodo/agent/logs" "$HOME/.knodo/agent/run" "$HOME/.knodo/data"; do
    [ -d "$p" ] && pass "存在: $p" || fail "缺失: $p"
done

# 8. 可选: claude / codex wrapper
[ -x "$HOME/.knodo/agent/bin/claude" ] && pass "Claude wrapper 存在" || info "Claude wrapper 缺失 (可选)"
[ -x "$HOME/.knodo/agent/bin/codex" ]  && pass "Codex wrapper 存在"  || info "Codex wrapper 缺失 (可选)"

info "==== 测试完成 ===="
