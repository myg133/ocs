FROM myg133/openvscode-server:base-latest

# 使用下面命令安装系统级依赖，也可以在项目级镜像中进行构建
USER root
ENV GO_HOME=/opt/go
ENV PATH=$GO_HOME/bin:$PATH
RUN curl -L https://golang.google.cn/dl/go1.25.1.linux-amd64.tar.gz -o /tmp/go.tar.gz
RUN rm -rf $GO_HOME && tar -C /opt -xzf /tmp/go.tar.gz
USER openvscode-server
# 安装插件
SHELL ["/bin/bash", "-c"]
RUN ${OPENVSCODE} --install-extension golang.go
