#!/usr/bin/env bash
# 等 Flutter web watch 服务把 public/app 重建完成。
#
# 为什么需要它 (2026-09-23 血泪):
#   watch 服务是「20s 去抖 + ~50s dart2js 构建」≈ 70s 起。
#   用 `sleep 75` 猜时间 → 经常在构建**还没完成**时就跑浏览器验证,
#   看到的是上一版产物 (且 Flutter web 有 Service Worker / HTTP 缓存,
#   连 `curl` 拿到的都可能是旧的) → 得出完全错误的结论:
#   「组件没进树」「修改没生效」其实都是**构建没跟上**。
#   本脚本轮询日志判定, 不猜时间。
#
# 用法:
#   bash tools/wait-flutter-web-build.sh          # 等下一次构建完成
#   timeout 300 bash tools/wait-flutter-web-build.sh || echo "构建没跟上, 别急着验证"
set -uo pipefail
LOG="${NKB_FLUTTER_WATCH_LOG:-/home/tooyan/nuankebao-databackups/logs/flutter-web-watch.log}"
[ -f "$LOG" ] || { echo "✗ 找不到 watch 日志: $LOG" >&2; exit 2; }

LAST=$(grep -c "重建完成" "$LOG" 2>/dev/null || true)
LAST=${LAST:-0}
for i in $(seq 1 60); do
  sleep 3
  NOW=$(grep -c "重建完成" "$LOG" 2>/dev/null || true)
  NOW=${NOW:-0}
  if [ "$NOW" -gt "$LAST" ]; then
    echo "✓ 构建完成 (等待 $((i*3))s)"
    exit 0
  fi
  # 构建失败也要立刻报出来, 不要白等到超时
  if tail -1 "$LOG" | grep -q "重建失败"; then
    echo "✗ 构建失败 — 看 /tmp/nuankebao-flutter-web-watch-build.log" >&2
    exit 1
  fi
done
echo "✗ 等待超时" >&2
exit 1
