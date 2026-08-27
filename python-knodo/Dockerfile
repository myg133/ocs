# =============================================================================
# python-knodo Dockerfile
#
# 分层原则 (变化频率从低到高, 高频改动放后面, 不污染前面 layer 缓存):
#   1. 系统级依赖 (uv / git / jq)     ← 几乎不变, 装一次缓存很久
#   2. HOME + base env                 ← 几乎不变
#   3. Python 扩展安装                 ← 偶尔变 (加/减/换扩展)
#   4. knodo 集成脚本 (COPY)           ← 改 bug 频繁, 放最末
#   5. ENTRYPOINT                      ← 引用上面的脚本路径, 跟着变
# =============================================================================

FROM myg133/openvscode-server:base-latest

# =============================================================================
# Layer 1: 系统级依赖
# =============================================================================
USER root
ENV XDG_BIN_HOME=/opt/uv/bin \
    PATH=$XDG_BIN_HOME:$PATH

# uv: Python 包管理 (跟原 python 镜像一致)
RUN curl -LsSf https://astral.sh/uv/install.sh | sudo -E sh -s -- --no-modify-path

# knodo 安装脚本 require_cmd curl/tar/sha256sum (基础镜像已有)
# git: knodo 脚本 ensure_git_available 兜底装
# jq:  旁路渲染 env 时方便 (不强依赖)
# 条件式装: 已存在跳过, 不污染 layer hash
RUN command -v git >/dev/null 2>&1 || (apt-get update && apt-get install -y --no-install-recommends git) ; \
    command -v jq  >/dev/null 2>&1 || (apt-get update && apt-get install -y --no-install-recommends jq) ; \
    rm -rf /var/lib/apt/lists/*

# HOME 统一到 /home/workspace (跟 pod.yaml/docker-compose 挂载路径对齐)
ENV HOME=/home/workspace

# =============================================================================
# Layer 2: Python 扩展 (vsix 从 marketplace 拉, 单 RUN 完成)
# =============================================================================
# 旁路公司代理 (debugpy/jupyter 扩展大, 代理拖慢会超时)
USER openvscode-server
ENV NO_PROXY=* \
    no_proxy=* \
    HTTPS_PROXY= \
    HTTP_PROXY=
SHELL ["/bin/bash", "-c"]
# 单个 RUN 把 5 个扩展都装了, 失败重试 5 次; 任一扩展最终失败才报错
RUN set -e; \
    for ext in \
        ntluong95.positron-python-package-manager \
        detachhead.basedpyright \
        ms-python.debugpy \
        ms-toolsai.jupyter \
        ms-python.isort; do \
        ok=0; \
        for i in 1 2 3 4 5; do \
            if ${OPENVSCODE} --install-extension "$ext"; then \
                ok=1; break; \
            fi; \
            echo "[retry $i/5] $ext 装失败, 10s 后重试"; \
            sleep 10; \
        done; \
        [ "$ok" = "1" ] || { echo "[FATAL] $ext 5 次重试都失败"; exit 1; }; \
    done

# =============================================================================
# Layer 3: knodo 集成脚本 (放最后, 改这里只重 build 这 1 个 layer)
# =============================================================================
USER root
COPY --chown=openvscode-server:openvscode-server scripts/entrypoint.sh          /usr/local/bin/entrypoint.sh
COPY --chown=openvscode-server:openvscode-server scripts/install-knodo-agent.sh /usr/local/bin/install-knodo-agent.sh
COPY --chown=openvscode-server:openvscode-server scripts/render-agent-env.sh    /usr/local/bin/render-agent-env.sh
COPY --chown=openvscode-server:openvscode-server scripts/test-knodo-integration.sh /usr/local/bin/test-knodo-integration.sh
RUN chmod 0755 \
        /usr/local/bin/entrypoint.sh \
        /usr/local/bin/install-knodo-agent.sh \
        /usr/local/bin/render-agent-env.sh \
        /usr/local/bin/test-knodo-integration.sh

# =============================================================================
# 入口 (以 root 启动, entrypoint 内部降权到 openvscode-server)
# =============================================================================
USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
