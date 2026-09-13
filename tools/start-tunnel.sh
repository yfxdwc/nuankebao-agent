#!/usr/bin/env bash
# ============================================================
# 暖客宝 Cloudflare Tunnel 启动 + 状态
#
# 用 systemd 长跑 (sales-ai 也是 systemd 模式)
# 公网 URL 在 journal 里 (每次启动随机)
# ============================================================
set -e

TUNNEL_SERVICE="nuankebao-cloudflared.service"

case "${1:-start}" in
  start)
    sudo systemctl start "$TUNNEL_SERVICE"
    sleep 12
    URL=$(sudo journalctl -u "$TUNNEL_SERVICE" -n 50 --no-pager 2>&1 | grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" | head -1)
    echo "✓ Tunnel started"
    echo "✓ Public URL: $URL"
    echo ""
    echo "测一下: curl $URL/api/health"
    sleep 5
    curl -s -o /dev/null -w "  HTTP %{http_code}\n" "$URL/api/health"
    ;;
  stop)
    sudo systemctl stop "$TUNNEL_SERVICE"
    echo "✓ Tunnel stopped"
    ;;
  status)
    sudo systemctl status "$TUNNEL_SERVICE" --no-pager 2>&1 | head -10
    echo ""
    URL=$(sudo journalctl -u "$TUNNEL_SERVICE" -n 50 --no-pager 2>&1 | grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" | head -1)
    [ -n "$URL" ] && echo "URL: $URL"
    ;;
  url)
    URL=$(sudo journalctl -u "$TUNNEL_SERVICE" -n 50 --no-pager 2>&1 | grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" | head -1)
    echo "$URL"
    ;;
  logs)
    sudo journalctl -u "$TUNNEL_SERVICE" -n 50 --no-pager 2>&1 | tail -30
    ;;
  *)
    echo "用法: $0 {start|stop|status|url|logs}"
    exit 1
    ;;
esac
