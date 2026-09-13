#!/usr/bin/env bash
# ============================================================
# 暖客宝 移动端/桌面端截图工具
#
# 用法:
#   ./tools/screenshot-mobile.sh mobile              # 截 /admin 移动视图 (iPhone 14 Pro 393x852)
#   ./tools/screenshot-mobile.sh desktop             # 截 /admin 桌面视图 (1440x900)
#   ./tools/screenshot-mobile.sh more                # 截"更多"sheet 打开状态
#   ./tools/screenshot-mobile.sh 393 852 /admin/customers /tmp/c.png  # 自定义宽高/路径
#
# 改完 admin UI 后跑这个看效果. 截图存到 /tmp/*.png.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 预设
case "${1:-}" in
  mobile)
    exec node "$ROOT/tools/screenshot-mobile.cjs" \
      "http://192.168.1.200:3010/admin" \
      "/tmp/admin-mobile.png" 393 852
    ;;
  desktop)
    exec node "$ROOT/tools/screenshot-mobile.cjs" \
      "http://192.168.1.200:3010/admin" \
      "/tmp/admin-desktop.png" 1440 900
    ;;
  more)
    exec node "$ROOT/tools/screenshot-more-sheet.cjs" \
      "http://192.168.1.200:3010/admin" \
      "/tmp/more-sheet.png"
    ;;
  "")
    echo "用法: $0 {mobile|desktop|more} 或 $0 <width> <height> [url] [out]"
    exit 1
    ;;
  *)
    # 自定义: width height [url] [out]
    W="$1"; H="$2"; URL="${3:-http://192.168.1.200:3010/admin}"; OUT="${4:-/tmp/admin-custom.png}"
    exec node "$ROOT/tools/screenshot-mobile.cjs" "$URL" "$OUT" "$W" "$H"
    ;;
esac
