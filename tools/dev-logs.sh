#!/usr/bin/env bash
# ============================================================
# 暖客宝 dev 日志聚合查看 (systemd + docker + /tmp/*.log)
#
# 用法:
#   ./tools/dev-logs.sh                # tail systemd nuankebao-nextjs
#   ./tools/dev-logs.sh -f             # follow 模式
#   ./tools/dev-logs.sh postgres       # docker logs nuankebao-postgres
#   ./tools/dev-logs.sh flutter        # /tmp/nuankebao-flutter-*.log
#   ./tools/dev-logs.sh all            # 并行多源 (用 tmux / multitail 更佳)
#
# 不依赖 tmux/multitail, 用 tail -f 朴素实现
# ============================================================
set -uo pipefail

# 拿 flutter / adb / java 等 dev 工具 (PATH 补全, 见 ~/.nuankebao_env)
[ -f ~/.nuankebao_env ] && . ~/.nuankebao_env

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

TARGET="${1:-nextjs}"
FOLLOW=""
if [ "${2:-}" = "-f" ] || [ "${1:-}" = "-f" ]; then
  FOLLOW="-f"
  [ "${1:-}" = "-f" ] && TARGET="nextjs"
fi

case "$TARGET" in
  nextjs|next)
    journalctl --user -u nuankebao-nextjs $FOLLOW --no-pager 2>&1
    ;;
  postgres|pg)
    docker logs nuankebao-postgres $FOLLOW 2>&1
    ;;
  flutter)
    # dev-flutter.sh 写到 /tmp/nuankebao-flutter/{web,phone}.log
    if ls /tmp/nuankebao-flutter/*.log >/dev/null 2>&1; then
      tail $FOLLOW /tmp/nuankebao-flutter/*.log
    else
      echo "(无 flutter 日志, 跑 ./tools/dev-flutter.sh 后才有)"
    fi
    ;;
  files|local)
    tail $FOLLOW /tmp/nuankebao-*.log 2>/dev/null || echo "(无 /tmp/nuankebao-*.log)"
    ;;
  all)
    echo "=== systemd nuankebao-nextjs (最近 30 行) ==="
    journalctl --user -u nuankebao-nextjs --no-pager -n 30 2>&1
    echo ""
    echo "=== docker nuankebao-postgres (最近 30 行) ==="
    docker logs nuankebao-postgres --tail 30 2>&1
    ;;
  -h|--help)
    sed -n '2,15p' "$0" | sed 's/^# \?//'
    ;;
  *)
    echo "未知目标: $TARGET (nextjs|postgres|flutter|files|all)"
    exit 1
    ;;
esac