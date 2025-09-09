FROM myg133/openvscode-server:base-latest

# 使用下面命令安装系统级依赖，也可以在项目级镜像中进行构建
USER root
RUN sudo apt-get update \
    && sudo apt-get install -y --no-install-recommends unzip \
# 清理缓存
    && sudo apt-get clean && sudo rm -rf /var/cache/apt/* && sudo rm -rf /var/lib/apt/lists/* && sudo rm -rf /tmp/*
ENV DENO_INSTALL=/opt/deno
ENV PATH=$DENO_INSTALL/bin:$PATH
RUN curl -fsSL https://deno.land/install.sh | sudo -E sh -s -- -y --no-modify-path
USER openvscode-server


SHELL ["/bin/bash", "-c"]
RUN ${OPENVSCODE} --install-extension denoland.vscode-deno
