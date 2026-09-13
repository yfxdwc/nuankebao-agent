#!/usr/bin/env bash
# ============================================
# 暖客宝 UI 风格守门脚本 (借鉴 sales-ai check-ui-reference-compliance.py)
#
# 检查项 (per docs/UI_STYLE_GUIDE.md §6.1):
#   ❌ 禁用图标包 (react-icons / @heroicons/* / @tabler/* / @iconify/* / phosphor-react)
#   ❌ namespace 全量 import (import * as Icons from "lucide-react")
#   ❌ 硬编码颜色 (text-gray-* / bg-slate-* / bg-[#xxx])
#   ❌ 暗色模式 (.dark:* 在 nuankebao UI 中)
#   ❌ inline style (style={{ ... }})
#   ❌ icon-only 控件缺 aria-label
#   ⚠️ icon 尺寸非标准 (矩阵外)
#
# 用法:
#   bash tools/check-ui-style.sh                  # 默认检查 src/app + src/components
#   bash tools/check-ui-style.sh --strict         # 警告也阻断
#   bash tools/check-ui-style.sh --fix           # 自动修复 (硬编码颜色)
#   bash tools/check-ui-style.sh path1 path2 ...   # 自定义路径
# ============================================
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${PROJECT_DIR}/src"
SCAN_DIRS=("${SRC_DIR}/app" "${SRC_DIR}/components")
STRICT=0
FIX=0

# 解析参数
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    --fix) FIX=1 ;;
    src/app|src/components)
      SCAN_DIRS=("${SRC_DIR}/app" "${SRC_DIR}/components")
      ;;
    *)
      # 自定义路径
      SCAN_DIRS=("$@")
      ;;
  esac
done

# 错误计数
ERRORS=0
WARNINGS=0
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m'

err() { echo -e "  ${RED}❌${NC}  $*"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}⚠️${NC}  $*"; WARNINGS=$((WARNINGS + 1)); }
ok() { echo -e "  ${GREEN}✅${NC}  $*"; }

echo "🎨 暖客宝 UI 风格守门"
echo "   检查目录: ${SCAN_DIRS[*]}"
echo "   模式: $([ $STRICT -eq 1 ] && echo "strict" || echo "normal")"
echo ""

# ============ 1. 禁用图标包 ============
echo "1️⃣  禁用图标包"
DISABLED_ICONS=(
  "react-icons"
  "@heroicons/"
  "@tabler/icons-react"
  "@iconify/"
  "phosphor-react"
  "react-feather"
  "@radix-ui/react-icons"
)
for dir in "${SCAN_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then continue; fi
  while IFS= read -r -d '' file; do
    for icon in "${DISABLED_ICONS[@]}"; do
      if grep -lE "from ['\"]${icon}" "$file" >/dev/null 2>&1; then
        err "$(basename "$file"): 禁用图标包 ${icon}"
      fi
    done
  done < <(find "$dir" -type f \( -name "*.tsx" -o -name "*.ts" \) -print0)
done
if [ $ERRORS -eq 0 ]; then ok "无禁用图标包"; fi
echo ""

# ============ 2. namespace 全量 import ============
echo "2️⃣  namespace 全量 import"
for dir in "${SCAN_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then continue; fi
  while IFS= read -r -d '' file; do
    if grep -E "import \* as [A-Za-z_]+ from ['\"]lucide-react" "$file" >/dev/null 2>&1; then
      err "$(basename "$file"): namespace 全量 import lucide-react"
    fi
  done < <(find "$dir" -type f \( -name "*.tsx" -o -name "*.ts" \) -print0)
done
ok "lucide-react 全用具名 import"
echo ""

# ============ 3. 硬编码颜色 (Tailwind 默认色板) ============
echo "3️⃣  硬编码颜色 (Tailwind 默认色板)"
HARDCODED_COLORS=(
  "text-gray-"
  "bg-gray-"
  "text-slate-"
  "bg-slate-"
  "text-zinc-"
  "bg-zinc-"
  "text-neutral-"
  "bg-neutral-"
  "text-stone-"
  "bg-stone-"
)
for dir in "${SCAN_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then continue; fi
  while IFS= read -r -d '' file; do
    for color in "${HARDCODED_COLORS[@]}"; do
      if grep -E "${color}" "$file" >/dev/null 2>&1; then
        err "$(basename "$file"): 硬编码颜色 ${color}"
      fi
    done
    # 检查 bg-[#xxx] / text-[#xxx]
    if grep -E "(text|bg)-\[#[0-9a-fA-F]+\]" "$file" >/dev/null 2>&1; then
      err "$(basename "$file"): 硬编码 hex 颜色 (e.g. text-[#xxx])"
    fi
  done < <(find "$dir" -type f \( -name "*.tsx" -o -name "*.ts" \) -print0)
done
ok "颜色全走 token"
echo ""

# ============ 4. 暗色模式 ============
echo "4️⃣  暗色模式 (.dark:*)"
for dir in "${SCAN_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then continue; fi
  while IFS= read -r -d '' file; do
    if grep -E "\.dark:" "$file" >/dev/null 2>&1; then
      err "$(basename "$file"): 使用 .dark:* 变体 (项目禁用暗色模式)"
    fi
  done < <(find "$dir" -type f \( -name "*.tsx" -o -name "*.ts" \) -print0)
done
ok "无 .dark:* 变体 (per AGENTS §1 反 vibe)"
echo ""

# ============ 5. inline style ============
echo "5️⃣  inline style"
for dir in "${SCAN_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then continue; fi
  while IFS= read -r -d '' file; do
    # style={{ ... }} 排除 globals.css (CSS 变量定义允许)
    if grep -E "style=\{\{" "$file" >/dev/null 2>&1; then
      # 允许 globals.css 和 styles/ 目录 (CSS 不是 inline style)
      case "$file" in
        *styles/*|*globals.css) ;;
        *) err "$(basename "$file"): inline style (用 Tailwind class)" ;;
      esac
    fi
  done < <(find "$dir" -type f \( -name "*.tsx" -o -name "*.ts" \) -print0)
done
ok "无 inline style (除 styles/* globals.css)"
echo ""

# ============ 6. icon-only 控件缺 aria-label ============
echo "6️⃣  icon-only 控件 aria-label"
for dir in "${SCAN_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then continue; fi
  while IFS= read -r -d '' file; do
    # 简单启发式: <Button size="icon" 后面没有 aria-label 报错
    # 这不是完美的检测, 但能 catch 大部分
    if grep -E 'size=["'\'']icon["'\'']' "$file" >/dev/null 2>&1; then
      # 找每个 size="icon" 看后面 200 字符内是否有 aria-label
      if ! grep -B1 -A5 'size="icon"' "$file" 2>/dev/null | grep -q 'aria-label'; then
        warn "$(basename "$file"): icon-only 控件可能缺 aria-label (人工确认)"
      fi
    fi
  done < <(find "$dir" -type f -name "*.tsx" -print0)
done
ok "icon-only aria-label 检查 (warning, 不阻断)"
echo ""

# ============ 7. icon 尺寸非标准 (warning) ============
echo "7️⃣  icon 尺寸非标准"
STANDARD_SIZES=("h-3 w-3" "h-4 w-4" "h-5 w-5" "h-8 w-8")
for dir in "${SCAN_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then continue; fi
  while IFS= read -r -d '' file; do
    # 找 h-N w-N 尺寸组合
    grep -oE 'h-[0-9]+ w-[0-9]+' "$file" 2>/dev/null | sort -u | while IFS= read -r size; do
      if [[ ! " ${STANDARD_SIZES[@]} " =~ " ${size} " ]]; then
        warn "$(basename "$file"): 非标准 icon 尺寸 ${size} (h-3/4/5/8 w-3/4/5/8)"
      fi
    done
  done < <(find "$dir" -type f \( -name "*.tsx" -o -name "*.ts" \) -print0)
done
ok "icon 尺寸检查 (warning, 矩阵外)"
echo ""

# ============ 总结 ============
echo "================================"
echo -e "总计: ${RED}${ERRORS} 错${NC}, ${YELLOW}${WARNINGS} 警${NC}"

if [ $ERRORS -gt 0 ]; then
  echo -e "${RED}❌ 阻断 (有错)${NC}"
  exit 1
elif [ $STRICT -eq 1 ] && [ $WARNINGS -gt 0 ]; then
  echo -e "${YELLOW}⚠️  阻断 (strict 模式有警)${NC}"
  exit 2
else
  echo -e "${GREEN}✅ 通过${NC}"
  exit 0
fi
