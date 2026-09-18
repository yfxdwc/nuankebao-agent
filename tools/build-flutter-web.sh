#!/usr/bin/env bash
# ============================================================
# 暖客宝 Flutter Web Build 脚本
#
# 把 flutter_app/ build 成 web, 同步到 public/app/ (Next.js serve).
# 自动注入 dart-define=NUANKEBAO_API_BASE, 避免像 2026-09-12 那样硬编码 .200
# 导致 dev IP 变了 web 调用错误 IP (DioException connection timeout).
#
# 用法:
#   ./tools/build-flutter-web.sh                            # 默认 (从 .env.local 读 base URL)
#   ./tools/build-flutter-web.sh 192.168.1.99               # 指定 IP, 端口从 .env.local 读
#   ./tools/build-flutter-web.sh 192.168.1.99 3003          # 指定 IP + 端口
#   NUANKEBAO_API_BASE=http://x.x.x.x:3003/api ./tools/build-flutter-web.sh
#   ./tools/build-flutter-web.sh --auto                    # 不传 dart-define, web 自动从 Uri.base 推导
#   ./tools/build-flutter-web.sh --no-sync                  # 只 build, 不同步到 public/app/
#   ./tools/build-flutter-web.sh --help
#
# 环境变量:
#   NUANKEBAO_API_BASE   dart-define API base URL (覆盖 CLI 参数)
#   FLUTTER_DIR          Flutter SDK 位置 (默认 ~/flutter)
#   SKIP_PUB_GET         跳过 flutter pub get (CI / 离线)
#
# 关联:
#   - tools/install-flutter-sdk.sh  装 SDK (~700MB)
#   - tools/dev-flutter.sh          dev 模式 (hot reload, 不 build)
#
# ADR: docs/adr/0003-flutter-dev-workflow.md (TODO, 待补)
# CHANGELOG [0.4.2] 引入: 2026-09-12 主人拍, 解决 web 写死 IP 导致 connection timeout
# ============================================================
set -euo pipefail

# ---------- 自动推导项目根 ----------
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FLUTTER_APP_DIR="$ROOT/flutter_app"
PUBLIC_APP_DIR="$ROOT/public/app"
LOG_DIR="/tmp"
LOG_FILE="$LOG_DIR/nuankebao-build-flutter-web.log"

# ---------- 颜色 + log ----------
RED='\033[0;31m'
GREEN='\033[0:32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +%H:%M:%S)]${NC} $*"; }
err()  { echo -e "${RED}[$(date +%H:%M:%S)]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $*"; }
title(){ echo -e "\n${CYAN}==>${NC} $*"; }

# ---------- 参数解析 ----------
IP_ARG=""
PORT_ARG=""
AUTO_MODE=false
NO_SYNC=false
HELP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      HELP=true
      shift
      ;;
    --auto)
      AUTO_MODE=true
      shift
      ;;
    --no-sync)
      NO_SYNC=true
      shift
      ;;
    -*)
      err "未知参数: $1"
      echo "跑 ./tools/build-flutter-web.sh --help"
      exit 1
      ;;
    *)
      if [ -z "$IP_ARG" ]; then
        IP_ARG="$1"
      elif [ -z "$PORT_ARG" ]; then
        PORT_ARG="$1"
      else
        err "参数过多: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [ "$HELP" = true ]; then
  sed -n '2,28p' "$0" | sed 's/^# \?//'
  exit 0
fi

# ---------- 兜底 IP / Port ----------
# 1) NUANKEBAO_API_BASE env 优先
# 2) CLI IP + .env.local port
# 3) .env.local 全读
# 4) 报错 (无兜底, --auto 除外)
APP_PORT=""
APP_HOST=""

if [ -f "$ROOT/.env.local" ]; then
  APP_PORT="$(grep -E '^APP_PORT=' "$ROOT/.env.local" | cut -d= -f2- | tr -d '"' || true)"
  APP_HOST="$(grep -E '^APP_HOST=' "$ROOT/.env.local" | cut -d= -f2- | tr -d '"' || true)"
fi

if [ -z "$IP_ARG" ] && [ -z "$PORT_ARG" ] && [ -z "${NUANKEBAO_API_BASE:-}" ]; then
  if [ "$AUTO_MODE" = true ]; then
    title "AUTO 模式: 不传 dart-define, web 运行时从 Uri.base.origin 自动推导"
    DART_DEFINE=""
  else
    err "未指定 base URL. 用法:"
    err "  ./tools/build-flutter-web.sh <IP> [PORT]"
    err "  ./tools/build-flutter-web.sh --auto   # 运行时自动推导"
    err "或设 env: NUANKEBAO_API_BASE=http://x.x.x.x:port/api"
    exit 1
  fi
else
  # 拼 IP:port/api (CLI / env 任一)
  if [ -n "${NUANKEBAO_API_BASE:-}" ]; then
    DART_DEFINE="--dart-define=NUANKEBAO_API_BASE=${NUANKEBAO_API_BASE}"
    title "BASE URL (来自 env): ${NUANKEBAO_API_BASE}"
  else
    FINAL_IP="${IP_ARG}"
    FINAL_PORT="${PORT_ARG:-$APP_PORT}"
    if [ -z "$FINAL_PORT" ]; then
      err "未指定端口, 也未在 .env.local 找到 APP_PORT"
      err "用法: ./tools/build-flutter-web.sh $IP_ARG <PORT>"
      exit 1
    fi
    FINAL_URL="http://${FINAL_IP}:${FINAL_PORT}/api"
    DART_DEFINE="--dart-define=NUANKEBAO_API_BASE=${FINAL_URL}"
    title "BASE URL (拼 CLI + .env.local): ${FINAL_URL}"
  fi
fi

# ---------- Flutter SDK 定位 ----------
FLUTTER_DIR="${FLUTTER_DIR:-$HOME/flutter}"
FLUTTER_BIN="$FLUTTER_DIR/bin/flutter"

if ! command -v flutter >/dev/null 2>&1; then
  if [ ! -x "$FLUTTER_BIN" ]; then
    err "flutter 未安装 / 不在 PATH"
    err "  装 SDK: ./tools/install-flutter-sdk.sh  (~700MB)"
    err "  或手动: export PATH=\$HOME/flutter/bin:\$PATH"
    exit 1
  fi
  # 用绝对路径 (即便不在 PATH)
  FLUTTER="$FLUTTER_BIN"
else
  FLUTTER="flutter"
fi

log "Flutter: $($FLUTTER --version 2>&1 | head -1 || echo 'version check failed')"

# ---------- 预检 ----------
if [ ! -d "$FLUTTER_APP_DIR" ]; then
  err "找不到 $FLUTTER_APP_DIR"
  exit 1
fi

if [ ! -f "$FLUTTER_APP_DIR/pubspec.yaml" ]; then
  err "$FLUTTER_APP_DIR/pubspec.yaml 不存在, 不是有效的 Flutter 项目"
  exit 1
fi

# 端口检查 (AGENTS.md §3 红线: 端口用前必须检测, 但这里只 build 不 listen, 跳过)
# 仅当指定了 IP 时提示一下, 不强制

# ---------- 1. flutter clean (可选, 但推荐) ----------
title "flutter clean (清理 stale build artifacts)"
cd "$FLUTTER_APP_DIR"
$FLUTTER clean 2>&1 | tail -3 | sed "s/^/  /"

# ---------- 2. flutter pub get ----------
title "flutter pub get"
if [ "${SKIP_PUB_GET:-}" = "1" ]; then
  warn "SKIP_PUB_GET=1, 跳过 pub get"
else
  $FLUTTER pub get 2>&1 | tail -5 | sed "s/^/  /"
fi

# ---------- 3. flutter build web ----------
# v0.1.4 (2026-09-16): 加 --base-href /app/
# 原因: Flutter bootstrap HTML 用 <base href> + 相对路径加载资源 (flutter_bootstrap.js /
#       main.dart.js / canvaskit/* / assets/* 等). 默认 base href = "/", 浏览器解析所有相对
#       路径到根, 但 Flutter build 输出在 Next.js public/app/, 根路径全 404 → 一片空白.
#       显式 --base-href /app/ 让 Flutter web 知道自己 serve 在 /app/ 子路径, 所有资源从
#       /app/* 解析, 完美对齐 Next.js public static serving.
# 副作用: 浏览器 service worker 缓存了旧 base href → 主人侧 Ctrl+Shift+R 硬刷新.
#         APK 不受影响 (APK 走 native, 跟 web 资源路径无关).
#         dev mode (tools/start-flutter-dev.sh) 不传此 flag: Flutter 3.24.5 dev server
#         不支持 --web-base-href, 但 dev mode 跑在 Flutter 自己 server (:8080) 根路径,
#         默认 base href 就对得上, 不影响.
title "flutter build web --release --base-href /app/ $DART_DEFINE"
START_T=$(date +%s)
$FLUTTER build web --release --base-href /app/ $DART_DEFINE 2>&1 | tee "$LOG_FILE" | tail -15 | sed "s/^/  /"
ELAPSED=$(( $(date +%s) - START_T ))
ok "build 完成 (用时 ${ELAPSED}s)"
ok "日志: $LOG_FILE"

BUILD_OUTPUT="$FLUTTER_APP_DIR/build/web"
if [ ! -d "$BUILD_OUTPUT" ]; then
  err "build 输出目录不存在: $BUILD_OUTPUT"
  exit 1
fi

if [ ! -f "$BUILD_OUTPUT/main.dart.js" ]; then
  err "build 输出缺 main.dart.js (build 可能失败)"
  exit 1
fi

# ---------- 4. 验证 IP 写入正确 (防止 build 缓存问题) ----------
title "验证 main.dart.js 含正确的 API base URL"
# 注 (2026-09-18 修): DART_DEFINE 为空 (--auto 模式) 时 `echo "" | grep -oE ...` 返回 1,
#   在 `set -e` 下整个 `EXPECTED_IP=$(...)` 赋值就失败 → 脚本在「验证」步直接退出,
#   **永不同步到 public/app/** (主人报 --auto 后预览没变化就是这个)。兜 `|| true`。
#   依据: AGENTS §9 (改 preview 冻结文件需主人拍 + --no-verify 提交), 主人 2026-09-18 拍。
EXPECTED_IP=$(echo "$DART_DEFINE" | grep -oE "http://[0-9.]+:[0-9]+" | head -1 | cut -d/ -f3 | cut -d: -f1 || true)
if [ -n "$EXPECTED_IP" ]; then
  if grep -q "$EXPECTED_IP" "$BUILD_OUTPUT/main.dart.js"; then
    ok "✓ 含 IP $EXPECTED_IP"
  else
    err "✗ main.dart.js 不含期望 IP $EXPECTED_IP"
    err "  (build 缓存 / dart-define 未生效 / Flutter 编译时优化掉常量)"
    err "  log: $LOG_FILE"
    exit 1
  fi
elif [ "$AUTO_MODE" = true ]; then
  if grep -q "Uri.base\|location.origin" "$BUILD_OUTPUT/main.dart.js" 2>/dev/null; then
    ok "✓ 含 Uri.base / location.origin (auto-detect 逻辑生效)"
  else
    warn "⚠ 未检测到 auto-detect 关键字 (Uri.base / location.origin)"
    warn "  可能是 dart2js 把字符串优化掉了, 但行为应该 OK"
  fi
fi

# ---------- 5. 同步到 public/app/ ----------
if [ "$NO_SYNC" = true ]; then
  title "NO_SYNC: 跳过同步, build 输出在 $BUILD_OUTPUT"
  ok "完成 (仅 build)"
  exit 0
fi

title "同步 build/web/ → public/app/"
# rsync 比 cp 更精准 (保留时间戳 + 只更新差异)
mkdir -p "$PUBLIC_APP_DIR"
rsync -a --delete \
  --exclude='.last_build_id' \
  "$BUILD_OUTPUT/" "$PUBLIC_APP_DIR/"
ok "✓ 已同步"

# ---------- 6. 更新 version.json (强制浏览器检测新版本) ----------
title "更新 version.json + service worker hash (强制 SW 检测新版本)"

VERSION_FILE="$PUBLIC_APP_DIR/version.json"
if [ -f "$VERSION_FILE" ]; then
  # bump build_number
  CURRENT_BUILD=$(grep -oE '"build_number":"[0-9]+"' "$VERSION_FILE" | grep -oE '[0-9]+' || echo "1")
  NEW_BUILD=$((CURRENT_BUILD + 1))
  CURRENT_VERSION=$(grep -oE '"version":"[^"]*"' "$VERSION_FILE" | cut -d'"' -f4)
  # 生成 timestamp-based version (SemVer patch 增量, e.g. 0.1.0 → 0.1.1)
  BASE_VERSION="${CURRENT_VERSION%.*}"
  PATCH=$(echo "$CURRENT_VERSION" | awk -F. '{print $3}')
  PATCH=${PATCH:-0}
  NEW_PATCH=$((PATCH + 1))
  NEW_VERSION="${BASE_VERSION}.${NEW_PATCH}"
  
  cat > "$VERSION_FILE" <<EOF
{"app_name":"nuankebao","version":"${NEW_VERSION}","build_number":"${NEW_BUILD}","package_name":"nuankebao"}
EOF
  ok "✓ version.json: ${CURRENT_VERSION}#${CURRENT_BUILD} → ${NEW_VERSION}#${NEW_BUILD}"
else
  warn "version.json 不存在, 跳过 bump"
fi

# 更新 service worker manifest 里的 main.dart.js hash
SW_FILE="$PUBLIC_APP_DIR/flutter_service_worker.js"
if [ -f "$SW_FILE" ]; then
  NEW_HASH=$(md5sum "$PUBLIC_APP_DIR/main.dart.js" | awk '{print $1}')
  # 只替换 main.dart.js 那行, 避免误伤
  sed -i "s|\"main.dart.js\": \"[a-f0-9]\{32\}\"|\"main.dart.js\": \"$NEW_HASH\"|" "$SW_FILE"
  ok "✓ flutter_service_worker.js: main.dart.js hash = $NEW_HASH"
else
  warn "flutter_service_worker.js 不存在, 跳过 hash 更新"
fi

# ---------- 7. 总结 ----------
title "✅ build 总结"
echo "  build 输出:  $BUILD_OUTPUT"
echo "  public/app:  $PUBLIC_APP_DIR"
echo "  version:     ${NEW_VERSION:-?}#${NEW_BUILD:-?}"
echo ""
echo "主人浏览器侧 (强制刷新拿新代码, service worker 缓存):"
echo "  Ctrl+Shift+R / Cmd+Shift+R  (硬刷新)"
echo "  OR DevTools → Application → Service Workers → Unregister → 刷新"
echo "  OR 隐私模式打开"
echo ""
echo "下次 IP 变 (192.168.1.x 切换):"
echo "  ./tools/build-flutter-web.sh <新 IP> [PORT]"
echo "  OR 一直用 --auto (web 运行时从 Uri.base 自动推导, IP 变不用 rebuild)"
echo ""
ok "完成 → http://localhost:3003/app-preview 验证"
