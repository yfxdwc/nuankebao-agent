#!/usr/bin/env bash
# ============================================================
# BBT Cloudflare Tunnel 完整一键配置
#
# 主人只需提供: Cloudflare Tunnel token (从 Dashboard 拷)
# 其他全自动化
# ============================================================
set -e

# 自动推导 + env 覆盖 (AGENTS §6.3)
BBT_DIR="${BBT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
# cloudflared 安装目录: 优先 paths.conf, 兜底到 $HOME/.cloudflared-nuankebao
TUNNEL_DIR="${NUANKEBAO_TUNNEL_DIR:-$HOME/.cloudflared-nuankebao}"
TUNNEL_FILE="$TUNNEL_DIR/credentials.json"
CONFIG_FILE="$TUNNEL_DIR/config.yml"
SERVICE_FILE="${TUNNEL_SERVICE_FILE:-/etc/systemd/system/nuankebao-cloudflared.service}"
# 用户名 (systemd unit 里的 User=) - 默认当前用户 (sudo 调用者)
TUNNEL_USER="${TUNNEL_USER:-$(logname 2>/dev/null || echo $SUDO_USER)}"
HOSTNAME="${TUNNEL_HOSTNAME:-nuankebao.tooyang.top}"   # 主人可改 (AGENTS §6.3 强绑定)
DEV_PORT="${TUNNEL_DEV_PORT:-3003}"

if [ "$EUID" -ne 0 ]; then
  echo "❌ 必须 sudo"
  exit 1
fi

if [ ! -f "$TUNNEL_FILE" ]; then
  echo "❌ 没找到 $TUNNEL_FILE"
  echo ""
  echo "主人操作: 创建 Cloudflare Tunnel 并保存 token"
  echo "  1. 打开 https://one.dash.cloudflare.com/"
  echo "  2. Zero Trust → Networks → Tunnels → Create"
  echo "  3. 名字: nuankebao"
  echo "  4. 选 'Cloudflared' → Save"
  echo "  5. 复制 Token JSON"
  echo "  6. 主人机器: scp <token>.json mm7@<server>:$TUNNEL_FILE"
  exit 1
fi

echo "✓ Token: $TUNNEL_FILE"

# 1. 写 config.yml
mkdir -p "$TUNNEL_DIR"
cat > "$CONFIG_FILE" << 'YAML'
tunnel: $(jq -r .TunnelID "$TUNNEL_FILE")
credentials-file: "$TUNNEL_FILE"
YAML

cat >> "$CONFIG_FILE" << YAML

ingress:
  - hostname: $HOSTNAME
    service: http://127.0.0.1:$DEV_PORT
  - service: http_status:404
YAML

echo "✓ Config: $CONFIG_FILE"
cat "$CONFIG_FILE"

# 2. 写 systemd unit
cat > "$SERVICE_FILE" << UNIT
[Unit]
Description=BBT Cloudflare Tunnel (\$HOSTNAME)
After=network.target

[Service]
Type=simple
User=$TUNNEL_USER
ExecStart=/usr/local/bin/cloudflared --config $CONFIG_FILE tunnel run
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

echo "✓ Systemd: $SERVICE_FILE"

# 3. 启动
systemctl daemon-reload
systemctl enable nuankebao-cloudflared.service
systemctl stop nuankebao-cloudflared.service 2>/dev/null || true
sleep 2
systemctl start nuankebao-cloudflared.service

sleep 15

# 4. 等 URL 出现
URL=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  URL=$(journalctl -u nuankebao-cloudflared.service -n 50 --no-pager 2>&1 | grep -oE "https://[a-z0-9-]+\.cfargotunnel\.com" | head -1)
  [ -n "$URL" ] && break
  sleep 3
done

if [ -z "$URL" ]; then
  echo "❌ tunnel URL 还没出来, 看 journal:"
  journalctl -u nuankebao-cloudflared.service -n 30 --no-pager
  exit 1
fi

echo ""
echo "=========================================="
echo " ✓ Tunnel 跑起来了!"
echo "=========================================="
echo ""
echo "  Internal: http://127.0.0.1:$DEV_PORT"
echo "  Public:   $URL"
echo ""
echo " 主人还需 1 步 (Cloudflare DNS):"
echo "  1. 打开 https://one.dash.cloudflare.com/"
echo "  2. DNS → Records → Add"
echo "     Type: CNAME, Name: nuankebao, Target: $URL (去掉 https://), Proxy: ON"
echo ""
echo "  之后 nuankebao.tooyang.top 走这个 tunnel"
echo ""
