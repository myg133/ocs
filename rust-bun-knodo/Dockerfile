# =============================================================================
# rust-bun-knodo Dockerfile
#
# 技术栈: rust + bun (svelte/sveltekit)
#
# 分层原则 (变化频率从低到高, 高频改动放后面, 不污染前面 layer 缓存):
#   1. 系统级依赖 (rustup / bun / git / jq)   ← 几乎不变, 装一次缓存很久
#   2. HOME + base env                       ← 几乎不变
#   3. rust + bun 扩展                       ← 偶尔变 (加/减/换扩展)
#   4. knodo 集成脚本 (COPY)                 ← 改 bug 频繁, 放最末
#   5. ENTRYPOINT                            ← 引用上面的脚本路径, 跟着变
# =============================================================================

FROM myg133/openvscode-server:base-latest

# =============================================================================
# Layer 1: 系统级依赖
# =============================================================================
USER root

# rustup: Rust 工具链 (rustc / cargo)
# 不直接装 rustlang, 用 rustup-init 脚本装, 默认装 stable
# CARGO_HOME / RUSTUP_HOME 显式设, 方便 bind mount 持久化
ENV CARGO_HOME=/home/workspace/.cargo \
    RUSTUP_HOME=/home/workspace/.rustup \
    PATH=/home/workspace/.cargo/bin:$PATH

# bun: 现代 JS/TS runtime (svelte/sveltekit 用)
# 官方 install 脚本: https://bun.sh/install
ENV BUN_INSTALL=/home/workspace/.bun \
    PATH=/home/workspace/.bun/bin:$PATH

RUN curl -fsSL --proto '=https' --tlsv1.2 https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal --no-modify-path ; \
    curl -fsSL https://bun.sh/install | bash

# knodo 安装脚本 require_cmd curl/tar/sha256sum (基础镜像已有)
# git: knodo 脚本 ensure_git_available 兜底装
# jq:  旁路渲染 env 时方便 (不强依赖)
# 条件式装: 已存在跳过, 不污染 layer hash
RUN command -v git >/dev/null 2>&1 || (apt-get update && apt-get install -y --no-install-recommends git) ; \
    command -v jq  >/dev/null 2>&1 || (apt-get update && apt-get install -y --no-install-recommends jq) ; \
    rm -rf /var/lib/apt/lists/*

# HOME 统一到 /home/workspace (跟 pod.yaml/docker-compose 挂载路径对齐)
# 跟 python-knodo/njs-knodo 一致
ENV HOME=/home/workspace

# =============================================================================
# Layer 2: rust + svelte 扩展 (vsix 从 marketplace 拉, 单 RUN 完成)
# =============================================================================
USER openvscode-server

# 旁路公司代理 (扩展大, 代理拖慢会超时)
ENV NO_PROXY=* \
    no_proxy=* \
    HTTPS_PROXY= \
    HTTP_PROXY=

SHELL ["/bin/bash", "-c"]
# 单个 RUN 把 6 个扩展都装了 (5 rust + 1 svelte), 失败重试 5 次; 任一扩展最终失败才报错
# rust 扩展:
#   rust-lang.rust:           rust 官方扩展 (rust-analyzer, inlay hints, debugging)
#   tamasfe.even-better-toml:  Cargo.toml 语法高亮 (rust 项目必备)
#   serayuzgur.crates:         Cargo.toml 依赖管理
#   fill-labs.dependi:         依赖视图 (Cargo.toml + package.json)
#   vadimcn.vscode-lldb:      native debugger (rust 编译产物调试)
# svelte/sveltekit 扩展:
#   svelte.svelte-vscode:     svelte 官方扩展 (语法高亮 + IntelliSense)
#   (sveltekit 走普通 TS/HTML 扩展, 已经在 base-latest 里有)
RUN set -e; \
    for ext in \
        rust-lang.rust \
        tamasfe.even-better-toml \
        serayuzgur.crates \
        fill-labs.dependi \
        vadimcn.vscode-lldb \
        svelte.svelte-vscode; do \
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
# 跟 python-knodo/njs-knodo 完全一致的 5 个 shell 脚本 (knodo 集成跟 base image 技术栈无关)
# =============================================================================
USER root
COPY --chown=openvscode-server:openvscode-server scripts/entrypoint.sh          /usr/local/bin/entrypoint.sh
COPY --chown=openvscode-server:openvscode-server scripts/install-knodo-agent.sh /usr/local/bin/install-knodo-agent.sh
COPY --chown=openvscode-server:openvscode-server scripts/render-agent-env.sh    /usr/local/bin/render-agent-env.sh
COPY --chown=openvscode-server:openvscode-server scripts/test-knodo-integration.sh /usr/local/bin/test-knodo-integration.sh
COPY --chown=openvscode-server:openvscode-server scripts/extract-knodo-credentials.sh /usr/local/bin/extract-knodo-credentials.sh
RUN chmod 0755 \
        /usr/local/bin/entrypoint.sh \
        /usr/local/bin/install-knodo-agent.sh \
        /usr/local/bin/render-agent-env.sh \
        /usr/local/bin/test-knodo-integration.sh \
        /usr/local/bin/extract-knodo-credentials.sh

# =============================================================================
# 入口 (以 root 启动, entrypoint 内部降权到 openvscode-server)
# =============================================================================
USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
