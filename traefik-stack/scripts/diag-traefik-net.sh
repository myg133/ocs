#!/bin/bash
# 容器网络诊断 - 在 Traefik 容器里跑
# 用法: docker exec traefik bash /scripts/diag-traefik-net.sh
#      (或手动一行行跑下面命令)

echo "==== 1. 容器内 DNS 配置 ===="
echo "--- /etc/resolv.conf ---"
cat /etc/resolv.conf
echo
echo "--- /etc/hosts ---"
cat /etc/hosts
echo

echo "==== 2. 容器能不能上外网 ===="
echo "--- 8.8.8.8:53 连通性 (Google DNS) ---"
nc -zvw3 8.8.8.8 53 2>&1 || echo "FAIL: 8.8.8.8:53 不通"
echo "--- 1.1.1.1:53 连通性 (Cloudflare DNS) ---"
nc -zvw3 1.1.1.1 53 2>&1 || echo "FAIL: 1.1.1.1:53 不通"
echo "--- 119.29.29.29:53 连通性 (DNSPod DNS) ---"
nc -zvw3 119.29.29.29 53 2>&1 || echo "FAIL: 119.29.29.29:53 不通"
echo

echo "==== 3. tencentcloud API 能不能调 ===="
echo "--- HTTPS 连通性 ---"
curl -sI -m 5 https://dnspod.tencentcloudapi.com 2>&1 | head -3
echo
echo "--- 实际调一次 (无需认证, 看返回结构) ---"
curl -s -m 5 -X POST https://dnspod.tencentcloudapi.com/ \
  -H "X-TC-Action: DescribeRecords" \
  -H "Content-Type: application/json" 2>&1 | head -c 500
echo

echo "==== 4. 容器能不能解析域名 ===="
echo "--- 内部默认 resolver 查 google.com ---"
nslookup google.com 2>&1 | head -10
echo
echo "--- 内部默认 resolver 查 anspire.cn ---"
nslookup anspire.cn 2>&1 | head -10
echo
echo "--- 强制走 8.8.8.8 查 _acme-challenge ---"
nslookup _acme-challenge.traefik.localdev.anspire.cn 8.8.8.8 2>&1 | head -10
echo
echo "--- 强制走 catfish.dnspod.net 查 _acme-challenge ---"
nslookup _acme-challenge.traefik.localdev.anspire.cn catfish.dnspod.net 2>&1 | head -10
echo

echo "==== 5. 容器内能看到什么网络 ===="
echo "--- ip route ---"
ip route 2>&1 || route -n 2>&1
echo
echo "--- 监听的端口 ---"
ss -tlnp 2>&1 | head -10
echo
echo "--- 出去的连接 (看下都连到哪) ---"
ss -tnp 2>&1 | head -20
echo

echo "==== 6. Traefik 进程是否在 ===="
ps -ef | grep -E '(traefik|entrypoint)' | grep -v grep
echo

echo "==== 诊断完成 ===="
echo "把上面所有输出贴回来, 跟 host 对比: ss/netstat 在 host 跑"
