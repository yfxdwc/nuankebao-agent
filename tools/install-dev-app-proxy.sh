#!/usr/bin/env bash
# ============================================================
# 暖客宝 dev-app-proxy 注册为 systemd user service
#
# 用途: 让 dev-app-proxy (aiohttp path strip) 跟 cloudflared + Flutter dev server
#   一起开机自启, 不需要手工 nohup
#
# 实施: user systemd (类似 cloudflared-tc-prod.service), 不需要 sudo
# 配合:
#   - tools/start-flutter-dev.sh (起 Flutter web dev server → 8080)
#   - tools/install-flutter-dev-tunnel.sh (加 cloudflared /dev-app* rule → 8181)
#
# 用法:
#   ./tools/install-dev-app-proxy.sh                  # 注册并 enable
#   ./tools/install-dev-app-proxy.sh --uninstall     # 移除 service
#
# 拍板: 2026-09-16, 配合 feature-customer-graph-uses-franchisee
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_NAME="nuankebao-dev-app-proxy"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"

UNINSTALL=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall|-u)
      UNINSTALL=true
      shift
      ;;
    --help|-h)
      sed -n '2,20p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      exit 1
      ;;
  esac
done

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0:32m'
YELLOW='\033[1;33m'
BLUE='\033[0:34m'
NC='\033[0m'
log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $*"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }

# ---------- 卸载 ----------
if [ "$UNINSTALL" = true ]; then
  log "卸载 $SERVICE_NAME..."
  systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "$SERVICE_FILE"
  systemctl --user daemon-reload
  ok "✓ 已卸载"
  exit 0
fi

# ---------- 安装 ----------
mkdir -p "$(dirname "$SERVICE_FILE")"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Nuankebao dev-app-proxy (aiohttp path strip /dev-app/* → Flutter dev server)
After=network.target

[Service]
Type=simple
WorkingDirectory=$ROOT
ExecStart=/usr/bin/env python3 $ROOT/tools/dev-app-proxy.py
Restart=always
RestartSec=5
StandardOutput=append:/tmp/nuankebao-dev-app-proxy.log
StandardError=append:/tmp/nuankebao-dev-app-proxy.log

[Install]
WantedBy=default.target
EOF

log "service file: $SERVICE_FILE"
log "reload systemd + enable + start..."
systemctl --user daemon-reload
systemctl --user enable "$SERVICE_NAME"
systemctl --user restart "$SERVICE_NAME"

sleep 3
if systemctl --user is-active "$SERVICE_NAME" >/dev/null 2>&1; then
  ok "✓ $SERVICE_NAME 在跑"
else
  err "✗ $SERVICE_NAME 启动失败, 看 log:"
  err "  journalctl --user -u $SERVICE_NAME -n 20"
  exit 1
fi

echo ""
ok "✅ 完成"
echo ""
echo "验证:"
echo "  curl http://127.0.0.1:8181/healthz"
echo "  curl 'https://nuankebao.tooyang.top/dev-app/?v=test'"
echo ""
echo "卸载: $0 --uninstall"