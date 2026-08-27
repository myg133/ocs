# =============================================================================
# njs-knodo Dockerfile (Node.js / 前端变体)
#
# 分层原则 (变化频率从低到高):
#   1. 系统级依赖 (git / jq) + nvm + Node.js  ← 几乎不变
#   2. HOME + base env
#   3. 前端扩展安装 (单 RUN + 重试)         ← 偶尔变
#   4. knodo 集成脚本 (COPY)                ← 改 bug 频繁
#   5. ENTRYPOINT
# =============================================================================

FROM myg133/openvscode-server:base-latest

# =============================================================================
# Layer 1: 系统级依赖 + nvm + Node.js
# =============================================================================
USER root

# knodo 脚本 require_cmd curl/tar/sha256sum 基础镜像已有
# git:  nvm 装包时要用
# jq:   旁路渲染 env 时方便
RUN command -v git >/dev/null 2>&1 || (apt-get update && apt-get install -y --no-install-recommends git) ; \
    command -v jq  >/dev/null 2>&1 || (apt-get update && apt-get install -y --no-install-recommends jq) ; \
    rm -rf /var/lib/apt/lists/*

# ---- nvm + Node.js ----
ENV NVM_DIR=/opt/nvm
ENV NVM_VERSION=v0.40.3
ARG NODE_VERSION=22
# 装 nvm → 装指定 Node 版本 → 设默认 → 全局 rc 让任何 shell 都能用 node/npm
RUN mkdir -p $NVM_DIR && \
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh | bash && \
    bash -c "source $NVM_DIR/nvm.sh && \
             nvm install $NODE_VERSION && \
             nvm alias default $NODE_VERSION && \
             nvm use default" && \
    printf '\n# nvm\nexport NVM_DIR="%s"\n[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"\n' "$NVM_DIR" > /etc/profile.d/nvm.sh && \
    printf '\n[ -s "$NVM_DIR/nvm.sh" ] && \\. "$NVM_DIR/nvm.sh"\n' >> /etc/bash.bashrc

# HOME 统一到 /home/workspace (跟 pod.yaml/docker-compose 挂载路径对齐)
ENV HOME=/home/workspace

# =============================================================================
# Layer 2: 前端 / Node.js 扩展 (单 RUN + 重试)
# =============================================================================
# 旁路公司代理 (扩展大, 代理拖慢会超时)
USER openvscode-server
ENV NO_PROXY=* \
    no_proxy=* \
    HTTPS_PROXY= \
    HTTP_PROXY=
SHELL ["/bin/bash", "-c"]
# 7 个扩展, 涵盖: Next.js / 格式化 / lint / Tailwind / 路径补全 / HTML 标签 / CSS 跳转
RUN set -e; \
    for ext in \
        PulkitGangwar.nextjs-snippets \
        esbenp.prettier-vscode \
        dbaeumer.vscode-eslint \
        bradlc.vscode-tailwindcss \
        christian-kohler.path-intellisense \
        formulahendry.auto-rename-tag \
        pranaygp.vscode-css-peek; do \
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
