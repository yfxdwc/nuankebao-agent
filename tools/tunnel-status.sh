#!/usr/bin/env bash
# ============================================================
# 暖客宝 隧道状态 + 替代访问方式 (含真实健康检查)
#
# 2026-09-05 fix: 加 curl 真验证 3003 / 公网 / tunnel, 不再打印假阳性
# ============================================================
set -uo pipefail

BBT_PORT="${BBT_PORT:-3003}"
BBT_HOSTNAME="${BBT_HOSTNAME:-nuankebao.tooyang.top}"

# 真 curl 3003 健康检查
check_local() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://127.0.0.1:${BBT_PORT}/api/health" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    echo "✅ 健康 (HTTP $code)"
  elif [ "$code" = "000" ]; then
    echo "❌ DOWN (connection refused)"
    echo "   修复: systemctl --user start nuankebao-nextjs.service"
    echo "   或:   ~/nuankebao-agent/tools/start-dev.sh"
  else
    echo "⚠️  HTTP $code (异常, 看 /tmp/nuankebao-nextjs.log)"
  fi
}

# systemd service 状态
check_systemd() {
  local svc="nuankebao-nextjs.service"
  if systemctl --user is-active "$svc" >/dev/null 2>&1; then
    echo "✅ active"
  else
    local state
    state=$(systemctl --user is-active "$svc" 2>/dev/null || echo "unknown")
    echo "❌ $state"
  fi
}

# 公网健康检查
check_public() {
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${BBT_HOSTNAME}/api/health" 2>/dev/null || echo "000")
  if [ "$code" = "200" ]; then
    echo "✅ https://${BBT_HOSTNAME}/ → 健康"
  elif [ "$code" = "307" ] || [ "$code" = "302" ]; then
    echo "✅ https://${BBT_HOSTNAME}/ → 重定向 (HTTP $code, 到登录页正常)"
  elif [ "$code" = "502" ]; then
    echo "❌ 502 Bad Gateway — Cloudflare 连不到 backend"
    echo "   99% 情况: 本机 3003 没跑, 先看 [1. 本机] 状态"
  else
    echo "⚠️  HTTP $code"
  fi
}

# tunnel 状态
check_tunnel() {
  local svc="cloudflared-pi-web.service"
  if systemctl --user is-active "$svc" >/dev/null 2>&1; then
    echo "✅ active"
  else
    local state
    state=$(systemctl --user is-active "$svc" 2>/dev/null || echo "unknown")
    echo "❌ $state"
    echo "   修复: systemctl --user start $svc"
  fi
}

echo "=========================================="
echo " 暖客宝 项目当前可访问方式 (实时检查)"
echo "=========================================="
echo ""

echo "--- 1. 本机 (主人浏览器) ---"
echo "  http://127.0.0.1:${BBT_PORT}"
echo "  状态: $(check_local)"
echo "  systemd: $(check_systemd)"
echo ""

echo "--- 2. 局域网 (主人手机, 同一 WiFi) ---"
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo "  http://${LOCAL_IP:-192.168.1.200}:${BBT_PORT}"
echo "  (前提: 主人手机连同一 WiFi 网段)"
echo ""

echo "--- 3. 公网 (Cloudflare Tunnel) ---"
echo "  https://${BBT_HOSTNAME}/"
echo "  状态: $(check_public)"
echo "  tunnel: $(check_tunnel)"
echo ""

echo "--- 4. 排查命令 ---"
echo "  本机日志:    tail -f /tmp/nuankebao-nextjs.log"
echo "  tunnel 日志: journalctl --user -u cloudflared-pi-web -f"
echo "  重启本机:    systemctl --user restart nuankebao-nextjs"
echo "  重启 tunnel: systemctl --user restart cloudflared-pi-web"
echo "  端到端测试:  ~/nuankebao-agent/tools/nuankebao-tunnel.sh test"
echo ""
