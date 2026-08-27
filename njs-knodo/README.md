# njs-knodo: OCS + knodo-agent 集成镜像 (Node.js / 前端变体)

`myg133/openvscode-server:njs-knodo` —— 在 openvscode-server 基础镜像上预装 **nvm + Node.js 22** 和 7 个前端常用扩展，再叠加 knodo 本地 Agent。

跟 `python-knodo` 共享同一套 knodo 集成逻辑（entrypoint / 安装 / 旁路渲染），只是基础工具和扩展不同。

## 文件结构

```
njs-knodo/
├── Dockerfile                       # Layer 1: nvm + node + git/jq; Layer 2: 7 个扩展; Layer 3: knodo 脚本
├── ovscs.pod.yaml                   # Pod + ConfigMap (settings + knodo-config) + knodo-data volume
├── docker-compose.yml               # 本地测试用
├── .env.example                     # 环境变量模板
├── settings.json                    # openvscode-server 编辑器设置
├── .gitignore                       # 排除 .env / 备份 / 探查脚本
├── .dockerignore                    # 排除 build context 中的垃圾
└── scripts/
    ├── entrypoint.sh                # 入口: 智能激活 → 拉 agent → exec openvscode-server
    ├── install-knodo-agent.sh       # 调 knodo 官方 curl|bash 安装脚本
    ├── render-agent-env.sh          # 旁路: 从 BACKEND_WS_URL+API_TOKEN 渲染 env
    ├── test-knodo-integration.sh    # 进容器验证 8 项 knodo 状态
    ├── extract-knodo-credentials.sh # 从运行中容器提取凭证备份
    └── backup-docker-mirrors.ps1    # 主机端: 临时清空 docker mirror
```

## 预装的东西

### Node.js 工具链
- **nvm 0.40.3** 装在 `/opt/nvm`
- **Node.js 22** 默认版本（`nvm alias default 22`）
- 全局 `/etc/profile.d/nvm.sh` + `/etc/bash.bashrc` 自动 source，任何 shell 进来 `node` / `npm` / `npx` 都能用
- 想换版本？进 openvscode 终端 `nvm install 20 && nvm alias default 20`

### 前端扩展 (7 个)
| 扩展 ID | 作用 |
|---|---|
| `PulkitGangwar.nextjs-snippets` | Next.js 代码片段 |
| `esbenp.prettier-vscode` | Prettier 格式化 |
| `dbaeumer.vscode-eslint` | ESLint |
| `bradlc.vscode-tailwindcss` | Tailwind CSS 智能提示 |
| `christian-kohler.path-intellisense` | 路径补全 |
| `formulahendry.auto-rename-tag` | HTML/JSX 标签自动重命名 |
| `pranaygp.vscode-css-peek` | CSS 类定义跳转 |

加新扩展 → 改 Dockerfile 第 50-58 行的 `for ext in ...` 列表，**只重 build Layer 2**（Layer 1 系统依赖和 Layer 3 脚本缓存命中）。

## 启动流程

跟 `python-knodo` 完全一样：

```
1. $HOME/.knodo/agent/config/agent.env 存在 + API_TOKEN 非空 → 复用
2. BACKEND_WS_URL + API_TOKEN env 都有 → render-agent-env.sh
3. KNODO_INSTALL_URL env 存在 → install-knodo-agent.sh 调 curl|bash
4. 都没有 → fail
```

最后：后台拉 knodo-agent → 健康检查 15s → exec openvscode-server 占 PID 1。

## 部署

### 1. 改 ConfigMap

`ovscs.pod.yaml` 里 `njs-knodo-config` 的 `KNODO_INSTALL_URL` 改成真 token。

### 2. build

```bash
cd D:\MyCodes\docker\ocs\njs-knodo
docker build -t myg133/openvscode-server:njs-knodo .
```

### 3. 本地测试 (docker-compose)

```bash
cp .env.example .env
# 改 .env 填 KNODO_INSTALL_URL
docker compose up -d
docker compose logs -f
```

浏览器: `http://localhost:3000`

### 4. K8s / podman 部署

```bash
kubectl apply -f ovscs.pod.yaml
```

## 日常运维

```bash
# 进容器
docker compose exec openvscode-server bash

# node / npm
node -v
npm -v
nvm ls

# 装前端项目 (示例)
npx create-next-app@latest my-app
cd my-app && npm run dev

# knodo-agent 管理
~/.knodo/agent/bin/knodo-agent status
~/.knodo/agent/bin/knodo-agent logs
~/.knodo/agent/bin/knodo-agent restart
~/.knodo/agent/bin/knodo-agent uninstall --yes

# 提取长期凭证备份
./scripts/extract-knodo-credentials.sh --write-backup
```

## 跟 python-knodo 的差异

| 维度 | python-knodo | njs-knodo |
|---|---|---|
| 基础工具 | uv (Python 包管理) | nvm + Node.js 22 |
| 扩展数 | 5 (Python 系) | 7 (前端 / JS 系) |
| 镜像名 | `myg133/openvscode-server:python-knodo` | `myg133/openvscode-server:njs-knodo` |
| ConfigMap 前缀 | `py-knodo-*` | `njs-knodo-*` |
| knodo 状态 volume | `ocs-py-knodo-data` | `ocs-njs-knodo-data` |
| knodo 集成逻辑 (entrypoint / install / render) | **完全相同** | **完全相同** |

## 排错速查

| 症状 | 排查 |
|---|---|
| `node: command not found` 进容器后 | nvm 没 source, 跑 `source /opt/nvm/nvm.sh && nvm use default`, 或重开 shell |
| `Permission denied` 在 .knodo 目录 | named volume 权限问题, 确认 entrypoint 第 0 阶段 (chown) 跑了 |
| 扩展装失败重试 5 次后报 FATAL | 看 `[retry X/5] <扩展名> 装失败`, 几乎都是网络问题, 重 build 或加 `--no-cache` |
| `knodo-agent 启动超时` | `cat /home/workspace/.knodo/agent/logs/stderr.log` |
| openvscode 起不来 | entrypoint 是 `exec`, openvscode 错直接挂, 看 pod logs |
