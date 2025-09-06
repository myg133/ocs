FROM gitpod/openvscode-server:latest

ENV OPENVSCODE_SERVER_ROOT="/home/.openvscode-server"
ENV OPENVSCODE="${OPENVSCODE_SERVER_ROOT}/bin/openvscode-server"

# 使用下面命令安装系统级依赖，也可以在项目级镜像中进行构建
# USER root
# RUN # install depl
# USER openvscode-server

SHELL ["/bin/bash", "-c"]
RUN mkdir -p "${HOME}/project" && \
    ${OPENVSCODE} --install-extension gitpod.gitpod-theme && \
    ${OPENVSCODE} --install-extension donjayamanne.githistory && \
    ${OPENVSCODE} --install-extension mhutchie.git-graph && \
    ${OPENVSCODE} --install-extension jackiotyu.git-worktree-manager && \
    ${OPENVSCODE} --install-extension EditorConfig.EditorConfig && \
    ${OPENVSCODE} --install-extension oderwat.indent-rainbow && \
    ${OPENVSCODE} --install-extension Gruntfuggly.todo-tree && \
    ${OPENVSCODE} --install-extension dracula-theme.theme-dracula && \
    ${OPENVSCODE} --install-extension PKief.material-icon-theme && \
    ${OPENVSCODE} --install-extension formulahendry.code-runner
