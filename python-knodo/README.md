# python-knodo: OCS + knodo-agent 集成镜像

`myg133/openvscode-server:python-knodo` —— 在原 Python OCS 镜像基础上集成 knodo 本地 Agent,
让 openvscode-server 容器变成一个可被 knodo 云端远程调度的"带 AI 的开发机"。

## 文件结构

```
python-knodo/
├── Dockerfile                       # 基于 base-latest, 烤 3 个 entrypoint 脚本
├── ovscs.pod.yaml                   # Pod + ConfigMap (含 knodo-config)
├── settings.json                    # openvscode-server 编辑器设置
└── scripts/
    ├── entrypoint.sh                # 入口: 智能激活 → 拉 agent → exec openvscode-server
    ├── install-knodo-agent.sh       # 包装器: 调 knodo 官方 curl|bash 安装脚本
    └── render-agent-env.sh          # 旁路: 从 BACKEND_WS_URL+API_TOKEN 直接渲染 env
```

## 启动流程

`entrypoint.sh` 按这个优先级决定怎么拿到 knodo 凭证:

```
1. $HOME/.knodo/agent/config/agent.env 存在且 API_TOKEN 非空
   → 复用 (典型: knodo-data-volume 持久化生效)
2. 环境变量 BACKEND_WS_URL + API_TOKEN 都存在
   → render-agent-env.sh 直接写 env (长期凭证, 绕过 24h install URL)
3. 环境变量 KNODO_INSTALL_URL 存在
   → install-knodo-agent.sh 调 knodo 官方 curl|bash 安装脚本 (首次 / 24h 内)
4. 都没有
   → fail
```

不论走哪条, 最后都:
- 后台拉起 `knodo-agent` (supervised 模式, 挂了自动重启)
- 健康检查 15s
- `exec` openvscode-server 占 PID 1

## 部署

### Step 1: 改 ConfigMap, 填 install URL

`ovscs.pod.yaml` 里 `py-knodo-config` 这个 ConfigMap 有占位符, 改完才能 apply:

```yaml
data:
  KNODO_INSTALL_URL: "https://anchnet.knodo.vip/api/v1/public/install/local/<你拿到的token>?origin=..."
```

### Step 2: build 镜像

```bash
cd D:\MyCodes\docker\ocs\python-knodo
docker build -t myg133/openvscode-server:python-knodo .
```

### Step 3: apply

```bash
kubectl apply -f ovscs.pod.yaml
# 或: docker compose / podman kube play, 看你的运行时
```

### Step 4: 等激活完成

```bash
kubectl logs -f openvscode-server | grep -E '(entrypoint|knodo)'
```

第一次会看到:

```
[entrypoint] 首次启动, 使用 KNODO_INSTALL_URL 激活
[INFO] 开始安装本地 Agent: 本地执行机
[INFO] knodo-agent 已启动
[entrypoint] knodo-agent 已就绪
[entrypoint] 启动 openvscode-server
```

### Step 5 (可选): 切到长期凭证

激活成功后, 进容器读 agent.env:

```bash
kubectl exec -it openvscode-server -- cat /home/workspace/.knodo/agent/config/agent.env
```

把 `BACKEND_WS_URL='...'` 和 `API_TOKEN='...'` 两行的值抄出来, 改 ConfigMap:

```yaml
data:
  # 删掉 KNODO_INSTALL_URL
  BACKEND_WS_URL: "wss://..."
  API_TOKEN: "eyJ..."
  KNODO_AGENT_PORT: "9910"
```

重新 apply, 重启 pod 即可。后面就不再依赖 24h 有效的 install URL。

## 日常运维

```bash
# 进容器
kubectl exec -it openvscode-server -- bash

# agent 状态
~/.knodo/agent/bin/knodo-agent status

# 实时日志
~/.knodo/agent/bin/knodo-agent logs
# 或
tail -f ~/.knodo/agent/logs/{stdout,stderr}.log

# 重启 / 升级 / 卸载
~/.knodo/agent/bin/knodo-agent restart
~/.knodo/agent/bin/knodo-agent upgrade
~/.knodo/agent/bin/knodo-agent uninstall --yes

# openvscode-server 这边
# 浏览器: http://<node-ip>:3000
# agent 健康: curl http://127.0.0.1:9910/health
```

## 关键设计取舍

| 决策 | 原因 |
|---|---|
| **不预装 agentd/claude/codex 二进制** | 拉取 URL 需 install token, build 阶段没法弄。`install-knodo-agent.sh` 走标准 curl\|bash, 首次启动会从云端拉, SHA256 增量校验, 后续启动跳过 |
| **强制 `LOCAL_AGENT_RUN_MODE=detached`** | 容器没 systemd, 跳过注册, 用 setsid+supervised 自愈 |
| **HOME=/home/workspace** | 跟 pod.yaml 挂载路径对齐, knodo 装到 `~/.knodo/agent/` 即 `/home/workspace/.knodo/agent/` |
| **knodo-data 用 hostPath 持久化** | dev 场景最简单; 生产换 PVC |
| **agent 后台 + openvscode 前台** | 容器退出两个一起死 (dev container 预期); openvscode 占 PID 1 让信号处理正确 |
| **API_TOKEN 可走 ConfigMap 或 Secret** | 演示用 ConfigMap, 实际生产建议 Secret (ConfigMap 明文落 etcd) |

## 已知限制

1. **多个 pod 共享一个 install URL**: knodo 安装脚本里的 `hostId` 是 install URL 自带的硬编码值, 多容器会共用一个 hostId。云端是否允许要看具体后端实现, 多租户场景建议每个 pod 单独申请 install URL。
2. **systemd 注册会失败**: knodo 脚本会试 `sudo systemctl daemon-reload`, 容器里没 systemd, 失败后自动回退到后台模式, 不影响功能但 stderr.log 会多几行 warn。
3. **render-agent-env.sh 需要预装二进制**: 走"长期凭证"路径时, 二进制必须已经存在 (典型: 从其他容器 copy 出来, 或在 build 阶段用一次性 install token 拉一次)。首次部署还是建议走 `KNODO_INSTALL_URL` 路径。

## 排错速查

| 症状 | 排查 |
|---|---|
| `knodo-agent 启动超时` | `cat /home/workspace/.knodo/agent/logs/stderr.log` 看具体报错 |
| `缺少 knodo 凭证` | ConfigMap 里三个变量 (`KNODO_INSTALL_URL` / `BACKEND_WS_URL`+`API_TOKEN`) 至少有一组 |
| 激活失败 401/403 | install URL 过期 (24h), 重新去 knodo web UI 拿 |
| 激活失败 "fingerprint conflict" | 多 pod 共用 install URL, 见上面"已知限制" |
| `agent.env` 不生成 | knodo curl\|bash 中途断, 看 `~/.knodo/agent/install.log` (如果有) 或重跑 |
| openvscode-server 起不来 | 我们的 entrypoint 是 exec, openvscode 错就直接挂, 看 pod logs |
