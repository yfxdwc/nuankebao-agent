#!/usr/bin/env bash
# ============================================================
# 暖客宝 Cloudflared Tunnel 加 /dev-app path rule
#
# 用途: 让 /app-preview?dev=1 能跨公网走 Flutter web dev server (秒级 hot reload)
#   - 现在: nuankebao.tooyang.top /dev-app* 走 127.0.0.1:3003 (Next.js), 404
#   - 改后: nuankebao.tooyang.top /dev-app* 走 127.0.0.1:8080 (Flutter web dev server)
#
# 原理: cloudflared ingress 按 first-match 路由, 把 /dev-app* rule 放在 root rule 前面
#   - 浏览器访问 https://nuankebao.tooyang.top/dev-app → cloudflared → 127.0.0.1:8080
#   - iframe 内 window.location.origin = https://nuankebao.tooyang.top (同源!)
#   - cookie 在 .tooyang.top → iframe fetch /api 自动带 cookie (R12 不复现)
#   - WebSocket hot reload 同源不被 CORS 拦 (秒级 hot reload)
#
# 用法:
#   ./tools/install-flutter-dev-tunnel.sh           # 默认改 ~/.cloudflared-tc-prod/config.yml
#   ./tools/install-flutter-dev-tunnel.sh --dry-run # 只打印 diff, 不写
#   ./tools/install-flutter-dev-tunnel.sh --revert  # 移除 /dev-app* rule (回滚)
#
# ⚠ AGENTS §3 红线: "不要 sudo 改系统配置". 本脚本只改 $HOME/.cloudflared-tc-prod/config.yml
#   (主人家目录, 不算系统级). 但 reload cloudflared 需要 SIGUSR1 给 cloudflared 进程,
#   用 pidof 自动定位, 不需要 sudo.
#
# 拍板: 主人 2026-09-16 拍, 配合 feature-customer-graph-uses-franchisee 任务
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# ---------- 默认 ----------
TUNNEL_CONFIG="$HOME/.cloudflared-tc-prod/config.yml"
DEV_PORT="${DEV_PORT:-8080}"

# ---------- 参数 ----------
DRY_RUN=false
REVERT=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)
      DRY_RUN=true
      shift
      ;;
    --revert|-r)
      REVERT=true
      shift
      ;;
    --help|-h)
      sed -n '2,28p' "$0" | sed 's/^# \?//'
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

# ---------- 预检 ----------
if [ ! -f "$TUNNEL_CONFIG" ]; then
  err "找不到 tunnel config: $TUNNEL_CONFIG"
  err "  当前 dev 机 nuankebao.tooyang.top tunnel 配置不在此路径"
  err "  查: ls $HOME/.cloudflared*/config.yml"
  exit 1
fi

# 找 nuankebao.tooyang.top 那段 root rule
if ! grep -q "hostname: nuankebao.tooyang.top" "$TUNNEL_CONFIG"; then
  err "$TUNNEL_CONFIG 里没有 nuankebao.tooyang.top hostname"
  err "  脚本假设 nuankebao tunnel 在这. 检查实际配置路径"
  exit 1
fi

# ---------- 备份 ----------
BACKUP_FILE="$TUNNEL_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
if [ "$DRY_RUN" = false ]; then
  cp "$TUNNEL_CONFIG" "$BACKUP_FILE"
  log "备份: $BACKUP_FILE"
fi

# ---------- 主体 ----------
if [ "$REVERT" = true ]; then
  log "回滚: 移除 /dev-app* rule"
  # 删掉我加的那段 (含 start_marker + end_marker)
  if [ "$DRY_RUN" = true ]; then
    sed -n '/# >>> nuankebao flutter dev start >>>/,/# <<< nuankebao flutter dev end <<</p' "$TUNNEL_CONFIG" || true
    ok "dry-run 模式, 只打印不改"
  else
    sed -i '/# >>> nuankebao flutter dev start >>>/,/# <<< nuankebao flutter dev end <<</d' "$TUNNEL_CONFIG"
    ok "已移除 /dev-app* rule"
  fi
else
  log "加 /dev-app* rule (path 路由到 127.0.0.1:$DEV_PORT Flutter web dev server)"
  # 拼要插入的内容
  INSERT_BLOCK=$(cat <<EOF
# >>> nuankebao flutter dev start >>>
# v0.1.4 加 (2026-09-16, 主人拍): 让 /app-preview?dev=1 走 Flutter web dev server
# 秒级 hot reload. 同源保证 cookie 共享 + WebSocket OK.
# 配合: tools/start-flutter-dev.sh (后台起 flutter run -d web-server)
# 回滚: ./tools/install-flutter-dev-tunnel.sh --revert
  - hostname: nuankebao.tooyang.top
    path: /dev-app
    service: http://127.0.0.1:$DEV_PORT
  - hostname: nuankebao.tooyang.top
    path: /dev-app/*
    service: http://127.0.0.1:$DEV_PORT
# <<< nuankebao flutter dev end <<<
EOF
)
  if [ "$DRY_RUN" = true ]; then
    echo "----- 准备插入到 'nuankebao.tooyang.top' 段前的 block -----"
    echo "$INSERT_BLOCK"
    echo "----- end -----"
    ok "dry-run 模式, 不改文件"
  else
    # 在 "hostname: nuankebao.tooyang.top" 第一次出现前插入 block
    # 用 awk 替代 sed (多行插入更稳)
    awk -v block="$INSERT_BLOCK" '
      /^  - hostname: nuankebao\.tooyang\.top$/ && !inserted {
        print block
        inserted = 1
      }
      { print }
    ' "$TUNNEL_CONFIG" > "$TUNNEL_CONFIG.tmp" && mv "$TUNNEL_CONFIG.tmp" "$TUNNEL_CONFIG"
    ok "已加 /dev-app + /dev-app/* path rule"
  fi
fi

# ---------- 显示 diff ----------
echo ""
log "=== diff ==="
diff -u "$BACKUP_FILE" "$TUNNEL_CONFIG" 2>/dev/null | head -40 || diff "$BACKUP_FILE" "$TUNNEL_CONFIG" | head -40 || true

# ---------- 验证配置语法 ----------
if command -v cloudflared >/dev/null 2>&1; then
  log "验证 config 语法..."
  if cloudflared tunnel --config "$TUNNEL_CONFIG" ingress validate 2>/dev/null; then
    ok "✓ config 语法 OK"
  else
    warn "✗ config 语法有问题 (上面 diff 自己确认)"
    if [ "$DRY_RUN" = false ]; then
      warn "自动回滚到备份 $BACKUP_FILE"
      cp "$BACKUP_FILE" "$TUNNEL_CONFIG"
      exit 1
    fi
  fi
fi

# ---------- reload cloudflared (SIGUSR1) ----------
if [ "$DRY_RUN" = true ]; then
  ok "dry-run 完成, 上面是预览"
  exit 0
fi

# 找 cloudflared 进程 (用 nuankebao tunnel 的 config)
CLOUDFLARED_PID=$(pgrep -f "cloudflared.*$(basename "$TUNNEL_CONFIG")" | head -1 || true)
if [ -z "$CLOUDFLARED_PID" ]; then
  warn "找不到 cloudflared 进程 (用 $(basename "$TUNNEL_CONFIG"))"
  warn "  可能需要: systemctl restart nuankebao-cloudflared (主人手工)"
  exit 0
fi

log "reload cloudflared (PID=$CLOUDFLARED_PID, SIGUSR1)..."
if kill -USR1 "$CLOUDFLARED_PID" 2>/dev/null; then
  ok "✓ SIGUSR1 已发, cloudflared 5s 内 reload config"
else
  err "✗ SIGUSR1 失败"
  exit 1
fi

echo ""
ok "✅ 完成"
echo ""
echo "验证 (主人侧):"
echo "  curl -I https://nuankebao.tooyang.top/dev-app/"
echo "  期望: HTTP/1.1 200 OK (Cloudflare tunnel + Flutter web dev server)"
echo ""
echo "用法 (主人侧):"
echo "  1. 启动 Flutter dev: ./tools/start-flutter-dev.sh"
echo "  2. 浏览器开:        https://nuankebao.tooyang.top/app-preview?dev=1"
echo "  3. 改代码:         flutter_app/lib/**/*.dart → 保存 → 1-2s iframe 自动更新"
echo ""
echo "回滚: ./tools/install-flutter-dev-tunnel.sh --revert"