#!/usr/bin/env bash
# ============================================
# 暖客宝部署修复脚本 (主人手工跑, agent 不执行)
#
# 背景: v0.1.2 改名后 (BBT → 暖客宝), 独立 cloudflared tunnel 从未创建,
#       systemd nuankebao-nextjs.service 启动失败 12162 次 (EADDRINUSE),
#       next dev 进程 (pid 398590) 僵死占着 3003 端口.
#
# 完整 SOP: docs/deploy/nuankebao-tunnel-fix.md
#
# 用法 (主人手工):
#   bash tools/fix-nuankebao-deploy.sh kill-old-dev
#   bash tools/fix-nuankebao-deploy.sh start-systemd
#   bash tools/fix-nuankebao-deploy.sh verify
#   bash tools/fix-nuankebao-deploy.sh help
#
# ⚠️ AGENTS §3: "不要 sudo 改系统配置"
#    agent 不直接执行本脚本 (涉及主人机器全局状态).
# ============================================
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEV_PORT="${DEV_PORT:-3003}"
HOSTNAME="${HOSTNAME:-nuankebao.tooyang.top}"
HOSTNAME="${HOSTNAME#https://}"
HOSTNAME="${HOSTNAME#http://}"
SERVICE="nuankebao-nextjs.service"
TUNNEL_DIR="$HOME/.cloudflared-nuankebao"

step() {
  echo ""
  echo "▶ $*"
}

ok()   { echo "  ✅ $*"; }
warn() { echo "  ⚠️  $*"; }
fail() { echo "  ❌ $*"; }

# ============ 1. 杀老 next dev 进程 ============
kill_old_dev() {
  step "1/4 杀老 next dev 进程 (释放 ${DEV_PORT})"
  PIDS=$(pgrep -f "next dev -p ${DEV_PORT}" || true)
  if [ -z "$PIDS" ]; then
    warn "无 next dev 进程占用 ${DEV_PORT} (可能已被 systemd 接管或已杀)"
    return 0
  fi
  echo "  发现 next dev PID: $PIDS"
  echo "  杀进程..."
  for pid in $PIDS; do
    if kill "$pid" 2>/dev/null; then
      ok "killed pid $pid"
    else
      fail "kill pid $pid 失败"
      echo "    试试: kill -9 $pid"
    fi
  done
  sleep 2
  # 验证端口释放
  if pgrep -f "next dev -p ${DEV_PORT}" >/dev/null 2>&1; then
    warn "next dev 仍存活, 强杀 (kill -9)..."
    pkill -9 -f "next dev -p ${DEV_PORT}" 2>/dev/null || true
    sleep 1
  fi
  if pgrep -f "next dev -p ${DEV_PORT}" >/dev/null 2>&1; then
    fail "next dev 仍占 ${DEV_PORT}, 主人手工检查"
    return 1
  else
    ok "${DEV_PORT} 端口已释放"
  fi
}

# ============ 2. 让 systemd 接管 ============
start_systemd() {
  step "2/4 让 systemd 接管 (${SERVICE})"
  if ! systemctl --user is-enabled "$SERVICE" >/dev/null 2>&1; then
    fail "systemd unit ${SERVICE} 未启用"
    echo "    安装: bash deploy/install-systemd.sh"
    return 1
  fi
  systemctl --user start "$SERVICE"
  ok "systemctl start ${SERVICE} 已触发"
  echo "  等 8s 编译..."
  sleep 8
  # 健康检查
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${DEV_PORT}/api/health" 2>/dev/null || echo "000")
  if [ "$CODE" = "200" ]; then
    ok "localhost:${DEV_PORT}/api/health → HTTP 200 (systemd 接管成功)"
  else
    fail "localhost:${DEV_PORT}/api/health → HTTP $CODE"
    echo "    查日志: journalctl --user -u ${SERVICE} -n 30 --no-pager"
    return 1
  fi
}

# ============ 3. 状态总览 ============
verify() {
  step "3/4 状态总览"
  # next.js 状态
  echo "  📦 next.js (port ${DEV_PORT}):"
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:${DEV_PORT}/api/health" 2>/dev/null || echo "000")
  if [ "$CODE" = "200" ]; then
    ok "✅ HTTP $CODE (next.js 跑中)"
  else
    fail "❌ HTTP $CODE (next.js 未启动或端口错)"
  fi
  # systemd
  echo "  ⚙️  systemd:"
  if systemctl --user is-active "$SERVICE" >/dev/null 2>&1; then
    ok "✅ ${SERVICE} active"
  else
    fail "❌ ${SERVICE} not active"
  fi
  # tunnel
  echo "  🌐 tunnel (${HOSTNAME}):"
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${HOSTNAME}/api/health" 2>/dev/null || echo "000")
  if [ "$CODE" = "200" ]; then
    ok "✅ HTTP $CODE (公网 ${HOSTNAME} 通)"
  else
    warn "❌ HTTP $CODE (公网 404 — 需主人手工配 tunnel, 见 SOP Step 3-4)"
  fi
  # tunnel 配置检查
  if [ -d "$TUNNEL_DIR" ]; then
    ok "✅ ${TUNNEL_DIR} 存在"
  else
    warn "❌ ${TUNNEL_DIR} 不存在 (SOP Step 3)"
  fi
}

# ============ 4. 完整修复 (一键跑 Step 1+2) ============
auto_fix() {
  step "完整修复 (Step 1+2 自动化, Step 3-4 需主人手工)"
  kill_old_dev || return 1
  start_systemd || return 1
  verify
}

# ============ 5. 一键切换到 production mode ============
switch_to_production() {
  step "一键切换到 production mode (杀 dev + build + start)"
  echo "  ⚠️  pnpm build 会需 5-10 分钟, 不要 Ctrl+C"
  echo ""
  # 杀 next dev
  kill_old_dev || return 1
  # build
  echo ""
  step "pnpm build (5-10 分钟)"
  cd "$PROJECT_DIR"
  if ! pnpm build 2>&1 | tail -20; then
    fail "pnpm build 失败"
    return 1
  fi
  ok "build 完成"
  # start (后台 nohup)
  echo ""
  step "pnpm start (后台 nohup)"
  nohup pnpm start > /tmp/nuankebao-prod.log 2>&1 &
  PID=$!
  echo "  PID: $PID"
  sleep 10
  # 健康检查
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${DEV_PORT}/api/health" 2>/dev/null || echo "000")
  if [ "$CODE" = "200" ]; then
    ok "production mode 启动成功! localhost:${DEV_PORT}/api/health → HTTP 200"
    echo ""
    echo "=========================================="
    echo " ✓ 主人可访问 (秒开, 无 dev 模式编译延迟):"
    echo "   http://${HOSTNAME#https://}/dev"
    echo "   http://${HOSTNAME#https://}/admin"
    echo "=========================================="
  else
    fail "production mode 启动失败 (HTTP $CODE)"
    echo "  看日志: tail -50 /tmp/nuankebao-prod.log"
    return 1
  fi
}

# ============ help ============
help_msg() {
  cat <<EOF
暖客宝部署修复脚本

用法:
  bash tools/fix-nuankebao-deploy.sh kill-old-dev           # Step 1: 杀老 next dev
  bash tools/fix-nuankebao-deploy.sh start-systemd           # Step 2: 让 systemd 接管
  bash tools/fix-nuankebao-deploy.sh verify                  # Step 3: 状态总览
  bash tools/fix-nuankebao-deploy.sh auto-fix                # Step 1+2 一键
  bash tools/fix-nuankebao-deploy.sh switch-to-production    # 切换 production mode (一键)
  bash tools/fix-nuankebao-deploy.sh help

环境变量:
  DEV_PORT   (default: 3003)
  HOSTNAME   (default: nuankebao.tooyang.top)

完整 SOP:
  cat docs/deploy/nuankebao-tunnel-fix.md

⚠️ AGENTS §3: "不要 sudo 改系统配置"
   agent 不直接执行本脚本.
   主人手工跑, 或确认后让 agent 协助.

何时用 switch-to-production:
  dev mode (/admin / /dev 打开极慢) → production mode
  原因: dev mode 按需编译 + 单线程 (首次访问 5-180 秒)
  修复: pnpm build (5-10 分钟一次性编译) + pnpm start
EOF
}

case "${1:-help}" in
  kill-old-dev) kill_old_dev ;;
  start-systemd) start_systemd ;;
  verify) verify ;;
  auto-fix) auto_fix ;;
  switch-to-production) switch_to_production ;;
  help|--help|-h|"") help_msg ;;
  *) echo "❌ 未知 action: $1"; help_msg; exit 1 ;;
esac
