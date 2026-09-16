#!/usr/bin/env bash
# ============================================================
# 暖客宝 预览框架冻结 guard (block mode)
#
# 主人 2026-09-16 拍板: 锁定 preview framework 9 个路径
# 见:
#   - docs/adr/0009-preview-framework-freeze.md §2.2 (设计)
#   - AGENTS.md §9.2 (违规 = 立即阻断)
#   - CHANGELOG.md [0.5.2] (本次变更)
#   - baseline tag: baseline-preview-v0.1.4-280f5fa
#
# 行为:
#   检测 git diff --cached (即将 commit 的 staged files)
#   与 9 个冻结路径 glob prefix 匹配:
#     ✓ 无违规 → exit 0 (放行)
#     ✗ 有违规 → echo 阻断 banner + exit 1 (阻断)
#
# 绕过方式 (主人拍板后, 任一):
#   1. git commit --no-verify -m "fix(preview): ..."
#   2. git commit -m "[preview-bypass] fix(preview): ..."
#
# 不绕过:
#   ✗ [ci-skip] / [no-guard]  (避免 agent 偷懒)
#   ✗ Merge commit  (避免 merge 把别人改动悄悄引入)
#
# 安装:
#   sudo ln -sf "$(pwd)/tools/pre-commit-preview-guard.sh" /path/to/.git/hooks/pre-commit
# 或用 tools/install-guards-preview.sh (后续可加)
#
# 设计取舍:
#   - 9 个路径硬编码 (与 ADR-0009 §1 + AGENTS §9.1 同步, 改这里必同步那两处)
#   - 用 glob prefix match ("src/app/app-preview/page.tsx" 命中 "src/app/app-preview/")
#   - 检测 staged (committed) 而非 working tree, 避免误报 (用户改文件但未 add 不算)
#   - exit 1 (block) 是主人拍, 不允许仅 warning (避免 w14 R12 "贴告示" 复发)
# ============================================================

set -uo pipefail

# ============ 9 个冻结路径 (与 ADR-0009 §1 + AGENTS §9.1 同源) ============
# 改动本数组时, 必须同步:
#   1. docs/adr/0009-preview-framework-freeze.md §1 冻结清单
#   2. AGENTS.md §9.1 红线 (一图概览)
#   3. docs/dev-modules/flutter-preview.md §Frozen Contract
#   4. tests/preview-framework-snapshot.test.ts (期望列表)
FROZEN_PATHS=(
  "src/app/app-preview/"             # 主预览页 (Next.js page + iframe)
  "src/app/preview/"                 # /preview → /app-preview 307 redirect
  "src/components/preview/"          # PreviewFrame + FlutterWebLoginBanner
  "tools/build-flutter-web.sh"       # 一键 build + sync
  "tools/dev-app-proxy.py"           # Flutter web dev server 反代
  "tools/install-dev-app-proxy.sh"   # dev-app-proxy 一键安装
  "tools/install-flutter-dev-tunnel.sh"  # cloudflared path rule 安装
  "tools/start-flutter-dev.sh"       # Flutter web dev server 启动器
  "public/app/"                      # Flutter web 编译产物 (git tracked)
)

# ============ self-check mode (测试 / debug 用) ============
if [ "${1:-}" = "--check" ]; then
  echo "Preview Framework Guard — 9 冻结路径 (与 ADR-0009 同源):"
  for p in "${FROZEN_PATHS[@]}"; do
    echo "  - $p"
  done
  exit 0
fi

# ============ git 仓库验证 ============
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "❌ preview-guard: 不在 git 仓库内, 跳过检查 (设计 fail-open)" >&2
  exit 0
fi

# ============ 收集 staged files ============
# --diff-filter=ACMRD: Add/Copy/Modify/Rename/Delete — 全部要检测 (删 preview 文件也算改)
STAGED=$(git diff --cached --name-only --diff-filter=ACMRD 2>/dev/null || true)

if [ -z "$STAGED" ]; then
  # 没有 staged 文件 (空 commit / 用户未 add)
  exit 0
fi

# ============ 检查违规 ============
violations=()
for f in $STAGED; do
  for pattern in "${FROZEN_PATHS[@]}"; do
    # strip trailing slash for matching
    p="${pattern%/}"
    # match: "p/x" or "p" exact
    if [[ "$f" == "${p}/"* || "$f" == "${p}" ]]; then
      violations+=("$f")
      break
    fi
  done
done

# ============ 无违规 → exit 0 ============
if [ ${#violations[@]} -eq 0 ]; then
  exit 0
fi

# ============ 有违规 → echo + exit 1 ============
echo "" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
echo "🚫 Preview Framework Guard: 检测到预览框架文件被修改" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
for v in "${violations[@]}"; do
  echo "  - $v" >&2
done
echo "" >&2
echo "预览框架已冻结 (baseline tag: baseline-preview-v0.1.4-280f5fa)." >&2
echo "修改前必读: docs/adr/0009-preview-framework-freeze.md §3 改前 SOP" >&2
echo "AGENTS §9 红线: 主人 ask_user 拍板后才改, 走 4 步 SOP" >&2
echo "" >&2
echo "如确认必要 (主人拍板后), 二选一绕过:" >&2
echo "  1. git commit --no-verify -m 'fix(preview): ...'" >&2
echo "  2. git commit -m '[preview-bypass] fix(preview): ...'" >&2
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2

exit 1
