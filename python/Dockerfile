FROM myg133/openvscode-server:base-latest

# 使用下面命令安装系统级依赖，也可以在项目级镜像中进行构建
USER root
ENV XDG_BIN_HOME=/opt/uv/bin
ENV PATH=$XDG_BIN_HOME:$PATH
RUN curl -LsSf https://astral.sh/uv/install.sh | sudo -E sh -s -- --no-modify-path
USER openvscode-server
# 安装插件
SHELL ["/bin/bash", "-c"]
RUN ${OPENVSCODE} --install-extension ntluong95.positron-python-package-manager && \
    ${OPENVSCODE} --install-extension detachhead.basedpyright && \
    ${OPENVSCODE} --install-extension ms-python.debugpy && \
    ${OPENVSCODE} --install-extension ms-toolsai.jupyter && \
    ${OPENVSCODE} --install-extension ms-python.isort
