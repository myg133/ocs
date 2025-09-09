FROM myg133/openvscode-server:base-latest

# 使用下面命令安装系统级依赖，也可以在项目级镜像中进行构建
ARG NODE_VERSION=22
USER root
ENV NVM_DIR=/opt/nvm/bin
ENV PATH=$NVM_DIR:$PATH
ENV PROFILE=/etc/bash.bashrc
RUN sudo -E mkdir -p $NVM_DIR
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | sudo -E bash
RUN sudo -E bash -c "source $NVM_DIR/nvm.sh && nvm install $NODE_VERSION"
USER openvscode-server

SHELL ["/bin/bash", "-c"]
RUN ${OPENVSCODE} --install-extension PulkitGangwar.nextjs-snippets && \
    ${OPENVSCODE} --install-extension esbenp.prettier-vscode && \
    ${OPENVSCODE} --install-extension dbaeumer.vscode-eslint && \
    ${OPENVSCODE} --install-extension bradlc.vscode-tailwindcss
