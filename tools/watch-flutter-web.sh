#!/usr/bin/env bash
# ============================================================
# 暖客宝 Flutter Web 预览自动重建守护 (2026-09-20)
#
# 主人需求: 「给我一个真正的实时最新预览地址」。静态预览包 public/app 不会自动
# 跟随源码变化; `?dev=1` 的 DDC 调试模式又慢又要求 dev server 手工 hot reload。
# 本守护补上这块:
#   每 POLL_SECONDS 检查 flutter_app/lib/** + pubspec.yaml 指纹, 变了就
#   等 DEBOUNCE_SECONDS 去抖 → tools/build-flutter-web.sh --auto
#   (release build + 同步 public/app + version.json bump)
#   → LAN `:3003/app-preview` 与 dev 公网 `/app-preview` 在 ~2-4 分钟内自动最新。
#
# 依赖: 纯轮询, 无 inotify-tools。systemd user 单元:
#   nuankebao-flutter-web-watch.service (deploy/systemd/)
# 手动跑: bash tools/watch-flutter-web.sh
# ============================================================
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# shellcheck disable=SC1090
source "$HOME/.nuankebao_env" 2>/dev/null || true

POLL_SECONDS="${WATCH_POLL_SECONDS:-15}"
DEBOUNCE_SECONDS="${WATCH_DEBOUNCE_SECONDS:-20}"

fingerprint() {
  find flutter_app/lib flutter_app/pubspec.yaml -type f -printf '%T@ %s %p\n' 2>/dev/null \
    | sort | sha256sum | cut -d' ' -f1
}

last="$(fingerprint)"
echo "[$(date '+%F %T')] watcher 启动 (poll=${POLL_SECONDS}s debounce=${DEBOUNCE_SECONDS}s) fp=${last:0:12}"

while true; do
  sleep "$POLL_SECONDS"
  now="$(fingerprint)"
  [ "$now" = "$last" ] && continue

  echo "[$(date '+%F %T')] 检测到源码变化 → ${DEBOUNCE_SECONDS}s 去抖后重建"
  sleep "$DEBOUNCE_SECONDS"
  last="$(fingerprint)"

  echo "[$(date '+%F %T')] 开始重建 Flutter web (public/app)..."
  if bash tools/build-flutter-web.sh --auto >/tmp/nuankebao-flutter-web-watch-build.log 2>&1; then
    echo "[$(date '+%F %T')] ✅ 重建完成 version=$(cat public/app/version.json 2>/dev/null)"
  else
    echo "[$(date '+%F %T')] ✗ 重建失败 (日志 /tmp/nuankebao-flutter-web-watch-build.log), 下轮变化再试"
  fi
  last="$(fingerprint)"
done
