#!/usr/bin/env bash
# knodo-agent 首次激活包装器
#
# 不重写 knodo 安装逻辑, 直接 pipe 给官方脚本, 但提前注入环境变量强制走容器友好的路径:
#   - KNODO_AGENT_PORT    : 显式端口, 避免默认值被占用时炸
#   - LOCAL_AGENT_RUN_MODE: 'detached' 模式, 跳过 systemd/launchd 注册, 用 setsid+supervised 自愈
#   - HOME                : 由 entrypoint 统一设到 /home/workspace
#
# 副作用:
#   - 装完后会试注册 systemd service (root+sudo 可用时会成功写文件), 实际 systemctl 会失败,
#     脚本会自动 warn 并回退到内建后台模式, 不影响功能
#   - agentd/claude/codex 三个二进制会从云端拉 (SHA256 校验, 增量更新)

set -euo pipefail

KNODO_INSTALL_URL="${1:-${KNODO_INSTALL_URL:-}}"
[ -n "${KNODO_INSTALL_URL}" ] || { echo "[ERROR] 需要 knodo 安装 URL" >&2; exit 1; }

# 必须从 entrypoint 继承过来
: "${HOME:?HOME 必须由 entrypoint 设置}"
: "${KNODO_AGENT_PORT:=9910}"
export KNODO_AGENT_PORT

# 强制 supervised (detached) 模式, 跳 systemd/launchd
export LOCAL_AGENT_RUN_MODE=detached

# 关闭交互式 prompt (knodo 安装脚本不读这个, 但保险)
export DEBIAN_FRONTEND=noninteractive
export CI=1

# 准备 knodo 脚本要求的目录 (脚本自己会 mkdir, 但提前建好避免权限坑)
mkdir -p "${HOME}/.knodo/agent/bin" \
         "${HOME}/.knodo/agent/config" \
         "${HOME}/.knodo/agent/logs" \
         "${HOME}/.knodo/agent/run" \
         "${HOME}/.knodo/data"

# 调 knodo 官方安装脚本
# shellcheck disable=SC2086
curl -fsSL --connect-timeout 10 --max-time 600 "${KNODO_INSTALL_URL}" | bash
