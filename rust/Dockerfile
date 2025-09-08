FROM myg133/openvscode-server:base-latest

# 使用下面命令安装系统级依赖，也可以在项目级镜像中进行构建
USER root
RUN sudo apt-get update \
    && sudo apt-get install -y --no-install-recommends \
    curl build-essential gcc make \
# 清理缓存
    && sudo apt-get clean \
    && sudo rm -rf /var/cache/apt/* \
    && sudo rm -rf /var/lib/apt/lists/* \
    && sudo rm -rf /tmp/*
ENV RUSTUP_HOME=/opt/rust/rustup
ENV CARGO_HOME=/opt/rust/cargo
ENV PATH=/opt/rust/cargo/bin:$PATH
RUN curl https://sh.rustup.rs -sSf | sudo -E sh -s -- --default-toolchain stable -y --no-modify-path
USER openvscode-server
# 安装插件
SHELL ["/bin/bash", "-c"]
RUN ${OPENVSCODE} --install-extension rust-lang.rust-analyzer && \
    ${OPENVSCODE} --install-extension tamasfe.even-better-toml && \
    ${OPENVSCODE} --install-extension vadimcn.vscode-lldb


