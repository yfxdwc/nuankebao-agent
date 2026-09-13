#!/usr/bin/env bash
# ============================================================
# Cloudflare Tunnel 一键开通 (任何 mm7 项目)
#
# 主人提供: hostname + port (各 1 个)
# 我自动: 配 config + 重启 cloudflared + 自动 DNS + 测公网
# ============================================================
set -e

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "用法: $0 <hostname> <port>"
  echo "  e.g. $0 nuankebao.tooyang.top 3003"
  echo "  e.g. $0 myapp.tooyang.top 8080"
  exit 1
fi

HOSTNAME="$1"
PORT="$2"
# Tunnel ID 和 config 路径 env 覆盖 (AGENTS §6.3: 各机器不同)
TUNNEL_ID="${TUNNEL_ID:-a8957e6c-6417-4468-a8d6-c8ed1aa5106f}"   # 默认是 mm7 pi-web, 其他机器重设
CONFIG="${CLOUDFLARED_CONFIG:-$HOME/.cloudflared/config.yml}"
CF_BIN="${CLOUDFLARED_BIN:-/usr/local/bin/cloudflared}"

echo "=========================================="
echo " Cloudflare Tunnel 一键配置"
echo "=========================================="
echo ""
echo "  Hostname: $HOSTNAME"
echo "  Port:     $PORT"
echo "  Tunnel:   $TUNNEL_ID (mm7 pi-web)"
echo ""

# 1. 加 ingress 到 mm7 pi-web config
echo "[1/4] 加 ingress 到 config..."
python3 - "$CONFIG" "$HOSTNAME" "$PORT" << 'PYEOF'
import sys
config_path = sys.argv[1]
hostname = sys.argv[2]
port = sys.argv[3]
with open(config_path) as f:
    content = f.read()
ingress = f"  - hostname: {hostname}\n    service: http://127.0.0.1:{port}\n"
if hostname in content:
    print(f"  ⚠ {hostname} 已存在, 跳过")
else:
    content = content.replace(
        "  # 兜底 404\n  - service: http_status:404",
        ingress + "  # 兜底 404\n  - service: http_status:404"
    )
    with open(config_path, 'w') as f:
        f.write(content)
    print(f"  ✓ {config_path} 加 {hostname} → http://127.0.0.1:{port}")
PYEOF

# 2. 重启 cloudflared
echo ""
echo "[2/4] 重启 mm7 pi-web cloudflared..."
systemctl --user restart cloudflared-pi-web.service
sleep 15
STATUS=$(systemctl --user is-active cloudflared-pi-web.service 2>&1)
echo "  状态: $STATUS"

# 3. 自动配 DNS (cloudflared tunnel route dns)
echo ""
echo "[3/4] 自动配 DNS (cloudflared)..."
cd "$(dirname "$CONFIG")"
if "$CF_BIN" tunnel route dns "$TUNNEL_ID" "$HOSTNAME" 2>&1 | tee /tmp/route-dns.log | grep -q "Added CNAME"; then
  echo "  ✓ DNS CNAME $HOSTNAME → tunnel $TUNNEL_ID"
elif grep -q "already exists" /tmp/route-dns.log; then
  echo "  ⚠ DNS 已存在"
else
  echo "  ✗ DNS 配错:"
  cat /tmp/route-dns.log
  exit 1
fi

# 4. 测公网
echo ""
echo "[4/4] 测公网 (等 30s DNS propagate)..."
sleep 30
HTTP=$(curl -s -o /dev/null -w "%{http_code}" "https://$HOSTNAME/api/health" 2>&1)
echo "  https://$HOSTNAME/api/health → HTTP $HTTP"
if [ "$HTTP" = "200" ]; then
  echo ""
  echo "=========================================="
  echo " ✓ 公网 OK! 主人可访问:"
  echo "   https://$HOSTNAME"
  echo "=========================================="
else
  echo "  ⚠ HTTP $HTTP (再等 30s 或检查 cloudflared log)"
  journalctl --user -u cloudflared-pi-web -n 10 --no-pager | tail -5
fi
