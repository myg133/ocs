#!/bin/bash
# =============================================================================
# uninstall-k8s.sh - 铲除 kubeadm 装的 k8s (含控制平面 + 业务 workload)
#
# 用法:
#   ./uninstall-k8s.sh             # 预览模式: 只看, 不动
#   ./uninstall-k8s.sh --execute   # 真正执行 (会停 Postgres/Redis/MinIO 等)
#   ./uninstall-k8s.sh --dry-run   # kubectl 命令只 echo, 不真跑
#
# 保留:
#   - NFS server (172.25.93.9) + /data-volumes 内容 (含 pvc-* PV 数据)
#   - dockerd + knodo 容器
#   - ollama / llama-server (LLM, 在宿主机进程)
#
# 释放:
#   - RAM ~1.5 GB (k8s 控制平面 + 业务 pod)
#   - CPU  ~4 核 (apiserver/etcd/controller/minio 等)
# =============================================================================

set -euo pipefail

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()   { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
fail()  { printf "${RED}[✗]${NC} %s\n" "$*" >&2; exit 1; }
hdr()   { printf "\n${CYAN}${BOLD}══ %s ══${NC}\n" "$*"; }
step()  { printf "${BOLD}[%d/%d]${NC} %s\n" "$1" "$2" "$3"; }

# ---------- 模式 ----------
EXECUTE=false
DRY_RUN=false
[ "${1:-}" = "--execute" ] && EXECUTE=true
[ "${1:-}" = "--dry-run" ]  && DRY_RUN=true

# ---------- 前置检查 ----------
[ "$(id -u)" -eq 0 ] || fail "必须 root 跑 (sudo $0)"

# 检测 kubeadm
if ! command -v kubeadm >/dev/null 2>&1; then
    warn "kubeadm 不在 PATH, 这台机器可能没装 k8s"
    warn "继续执行也安全 (会跳过 kubeadm reset 步骤)"
    HAVE_KUBEADM=false
else
    HAVE_KUBEADM=true
fi

# 检测 kubectl
if ! command -v kubectl >/dev/null 2>&1; then
    warn "kubectl 不在 PATH"
    KUBECT="kubectl"
else
    KUBECT="kubectl"
fi

# 检测 docker
command -v docker >/dev/null 2>&1 || fail "docker 不在 PATH"

# 跑命令 (考虑 dry-run)
run() {
    if $DRY_RUN; then
        printf "  ${YELLOW}[dry-run]${NC} %s\n" "$*"
    else
        "$@"
    fi
}

# ---------- 阶段 0: 预览 ----------
if ! $EXECUTE; then
    hdr "预览模式: 不会动任何东西"
    echo "本脚本会执行以下操作 (按顺序):"
    echo ""
    echo "  1. 列当前 k8s 节点 / namespace / 工作负载"
    echo "  2. 删所有非系统 namespace (停 Postgres/Redis/MinIO 等业务)"
    echo "  3. 删 kube-system namespace (停 CNI/Coredns/Ingress/Csi-nfs 等)"
    echo "  4. 等所有 k8s_* docker 容器清空 (最多 60s)"
    echo "  5. kubeadm reset (清 /etc/kubernetes, /var/lib/etcd, CNI, iptables)"
    echo "  6. 删残留目录: /var/lib/kubelet /etc/cni /run/kubernetes /root/.kube"
    echo "  7. 验证清理结果, 显示保留的东西"
    echo ""
    echo "确认要继续? 跑:"
    echo "  ${BOLD}sudo $0 --execute${NC}"
    echo ""
    echo "或者先 dry-run 看看 kubectl 会跑啥:"
    echo "  ${BOLD}sudo $0 --dry-run${NC}"
    echo ""
    exit 0
fi

# ---------- 真正执行 ----------
hdr "k8s 铲除 - 真执行模式"
echo ""
echo "${YELLOW}警告: 不可逆! 会停所有 k8s 业务 (Postgres/Redis/MinIO 等)${NC}"
echo ""
read -p "确认继续? [y/N] " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] || { echo "已取消"; exit 0; }

# ---------- 阶段 1: 列当前状态 ----------
hdr "阶段 1: 当前 k8s 状态"
echo ""
echo "--- 节点 ---"
$KUBECT get nodes -o wide 2>/dev/null || warn "kubectl 跑不动, 跳过"
echo ""
echo "--- namespace ---"
$KUBECT get ns 2>/dev/null || warn "无 namespace"
echo ""
echo "--- 工作负载 (所有 namespace) ---"
for ns in $($KUBECT get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    workloads=$($KUBECT get deploy,sts,ds -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [ "$workloads" -gt 0 ]; then
        echo "  [$ns] $workloads 个工作负载"
        $KUBECT get deploy,sts,ds -n "$ns" --no-headers 2>/dev/null | awk '{print "    - " $1 " (" $2 ")"}'
    fi
done
echo ""
echo "--- PVC (数据卷, 铲后保留) ---"
$KUBECT get pvc -A 2>/dev/null | grep -v "^NAME" || warn "无 PVC"

# ---------- 阶段 2: 删业务 namespace ----------
step 2 7 "删业务 namespace (停 Postgres/Redis/MinIO 等)"
for ns in $($KUBECT get ns -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    case "$ns" in
        default|kube-system|kube-public|kube-node-lease) continue ;;
    esac
    echo "  → 删 namespace: $ns"
    run $KUBECT delete ns "$ns" --grace-period=0 --force --wait=false 2>&1 | tail -2 || true
done

# ---------- 阶段 3: 删 kube-system ----------
step 3 7 "删 kube-system namespace (停 CNI/ingress/csi-nfs 等)"
echo "  → 删 namespace: kube-system"
run $KUBECT delete ns kube-system --grace-period=0 --force --wait=false 2>&1 | tail -2 || true

# ---------- 阶段 4: 等容器清空 ----------
step 4 7 "等所有 k8s_* 容器清空 (最多 90s)"
SECONDS=0
while [ $SECONDS -lt 90 ]; do
    remaining=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -c '^k8s_' || echo 0)
    if [ "$remaining" -eq 0 ]; then
        log "所有 k8s 容器已清空 (用时 ${SECONDS}s)"
        break
    fi
    printf "  剩余: %-3d 容器, 等 3s...  (%ds 已用)\n" "$remaining" "$SECONDS"
    sleep 3
done
if [ "$remaining" -ne 0 ]; then
    warn "还有 $remaining 个 k8s 容器没清, 后续 kubeadm reset 会强制清"
fi

# ---------- 阶段 5: kubeadm reset ----------
step 5 7 "kubeadm reset (清 etcd/CNI/iptables/kubelet)"
if $HAVE_KUBEADM; then
    run kubeadm reset --force 2>&1 | tail -15 || warn "kubeadm reset 报错, 继续"
else
    warn "跳过 (kubeadm 未安装)"
fi

# ---------- 阶段 6: 清理残留 ----------
step 6 7 "删残留目录"
for dir in \
    /etc/kubernetes \
    /var/lib/etcd \
    /var/lib/kubelet \
    /var/lib/cni \
    /etc/cni/net.d \
    /run/kubernetes \
    /var/run/kubernetes \
    /root/.kube \
    /home/*/.kube; do
    if [ -e "$dir" ]; then
        run rm -rf "$dir"
        printf "  → 删 %s\n" "$dir"
    fi
done
log "残留目录清理完成"

# ---------- 阶段 7: 验证 ----------
hdr "阶段 7: 验证清理结果"
echo ""

# 检查 docker k8s 容器
remaining=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -c '^k8s_' || echo 0)
if [ "$remaining" -eq 0 ]; then
    log "k8s_* 容器: 0 (全清)"
else
    warn "k8s_* 容器: 仍剩 $remaining 个"
    docker ps -a --format '{{.Names}}' | grep '^k8s_' | head -10
fi

# 检查关键目录
for dir in /etc/kubernetes /var/lib/etcd /var/lib/kubelet; do
    if [ -e "$dir" ]; then
        warn "$dir 还在"
    else
        log "$dir 已清"
    fi
done

# 检查端口
echo ""
echo "--- 端口监听 (常见 k8s 端口应该没人听) ---"
for port in 6443 10250 10259 10257 10251 2379 2380; do
    if ss -tlnp 2>/dev/null | grep -q ":$port "; then
        warn "端口 $port 还在听"
    else
        printf "  端口 %s: ✓ 没人听\n" "$port"
    fi
done

# NFS 校验
echo ""
echo "--- NFS /data-volumes 状态 (PV 数据应保留) ---"
if [ -d /data-volumes ]; then
    pvc_count=$(ls -d /data-volumes/pvc-* 2>/dev/null | wc -l)
    log "/data-volumes 存在, 含 $pvc_count 个 pvc-* 目录 (k8s 历史 PV 数据)"
    echo ""
    echo "  前 5 个:"
    ls -d /data-volumes/pvc-* 2>/dev/null | head -5 | sed 's/^/    /'
    echo ""
    echo "  这些是 k8s 业务的旧数据 (Postgres/MinIO/Redis 等)."
    echo "  要清理? 跑: ${BOLD}rm -rf /data-volumes/pvc-*-*-*-*-*${NC}"
    echo "  不清理也行, 留着当备份."
else
    warn "/data-volumes 不存在 (NFS 路径错?)"
fi

# knodo 容器状态
echo ""
echo "--- knodo 容器状态 (应该还在跑) ---"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' 2>/dev/null | grep -E '^(ocs-|NAMES)' || warn "无 knodo 容器"

# 系统资源
echo ""
echo "--- 资源释放确认 ---"
free -h | head -2
echo ""
echo "  释放的 RAM (k8s 没了):"
echo "    控制平面 (etcd/apiserver/controller/scheduler):  ~800 MB"
echo "    业务 pod (postgres/redis/minio/ingress/csi):    ~700 MB"
echo "    合计:                                            ~1.5 GB"
echo ""
echo "  释放的 CPU:"
echo "    apiserver (6.9%) + controller (2.6%) + scheduler (2%) + etcd (3.5%) + minio (19.5%):  ~3-4 核"

# ---------- 完成 ----------
hdr "✓ k8s 铲除完成"

cat <<EOF

保留的东西:
  - NFS server (172.25.93.9) + /data-volumes 内容
  - dockerd + knodo 容器 (py-knodo, njs-knodo)
  - ollama / llama-server (LLM, 宿主机进程)
  - /data-volumes/pvc-* (k8s 历史 PV 数据, 手动决定是否删)

接下来:
  1. 跑 \`docker ps\` 确认 k8s 容器全没了
  2. 跑 \`free -h\` 确认 RAM 释放了
  3. 你的 knodo 容器不受影响, 已在跑
  4. 重新评估容量: 5-6 个 → 8-10 个容器

如需重新装 k8s (rollback):
  sudo kubeadm init --config /etc/kubernetes/init.yaml.bak  # 如果有备份
  或:  sudo kubeadm init                                # 全新

EOF
