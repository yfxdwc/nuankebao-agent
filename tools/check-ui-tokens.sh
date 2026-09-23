#!/usr/bin/env bash
# ============================================
# UI 令牌护栏 (防"硬编码长回来")
# ============================================
#
# 为什么需要: 令牌系统建好只是第一步 —— 真正的病根是"顺手写个 16 / #D0D0D0"。
#   没有护栏的话, 三个月后又是一地硬编码 (跟 AGENTS §5「贴告示 ≠ 修复」同根:
#   靠人自觉 = 必复发)。
#
# 机制: 棘轮 (ratchet) —— 存量记在 design/tokens/ui-token-baseline.json,
#   **只禁止上涨**, 不要求立刻清零。每修一批就 `--update-baseline` 往下拧一格。
#
# 用法:
#   tools/check-ui-tokens.sh                    报告 (永远 exit 0)
#   tools/check-ui-tokens.sh --strict           超过基线 → exit 1 (CI / pre-commit)
#   tools/check-ui-tokens.sh --update-baseline  把当前值写成新基线 (只在数字**下降**时用)
#   tools/check-ui-tokens.sh --by-file          列出每个文件的明细
#
# 例外 (不算违规):
#   - flutter_app/lib/core/theme/**        令牌系统自身 (tokens.g.dart 必有字面值)
#   - src/lib/design-tokens.g.ts           生成的 web 令牌镜像
#   - src/styles/globals.css 的生成块       生成的 CSS 变量
#   - src/app/admin/dev/architecture/**    mermaid classDef 是**图的 DSL 字符串**, 不是 CSS
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)

STRICT=0
UPDATE=0
BY_FILE=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT=1 ;;
    --update-baseline) UPDATE=1 ;;
    --by-file) BY_FILE=1 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "未知参数: $arg (见 --help)"; exit 2 ;;
  esac
done

BASELINE="$ROOT/design/tokens/ui-token-baseline.json"

# ---- 统计函数: count <标签> <grep 表达式> <路径...> ----
declare -A COUNTS
declare -A FILES
TOTAL=0

count() {
  local label="$1"; shift
  local pattern="$1"; shift
  local n=0
  local per_file=""

  if [ "$#" -eq 0 ]; then
    echo "count: 至少给一个路径 ($label)" >&2
    return 1
  fi

  # grep -r 在无匹配时 exit 1 → 用 || true 兜住 (set -e 没开, 但保持明确)
  n=$(grep -rEo "$pattern" "$@" 2>/dev/null | wc -l | tr -d ' ')
  COUNTS["$label"]=$n
  TOTAL=$((TOTAL + n))

  if [ "$BY_FILE" = "1" ] && [ "$n" -gt 0 ]; then
    per_file=$(grep -rEo "$pattern" "$@" 2>/dev/null \
      | cut -d: -f1 | sort | uniq -c | sort -rn | head -6 | sed 's/^/        /')
    FILES["$label"]="$per_file"
  fi
}

# ============================================
# 1. Flutter: 活跃区 (参与编译)
# ============================================
FLUTTER_ACTIVE=$(find flutter_app/lib -name '*.dart' \
  -not -path '*/_deprecated/*' \
  -not -path '*/core/theme/*' 2>/dev/null)

# shellcheck disable=SC2086
if [ -n "$FLUTTER_ACTIVE" ]; then
  count "flutter.color"        'Color\(0x[0-9A-Fa-f]{6,8}\)'   $FLUTTER_ACTIVE
  count "flutter.fontSize"     'fontSize: *[1-9][0-9]*(\.[0-9]+)?[^0-9]' $FLUTTER_ACTIVE
  count "flutter.radius"       'BorderRadius\.circular\([0-9]'  $FLUTTER_ACTIVE
  count "flutter.spacing"      '(EdgeInsets\.[a-zA-Z]+\([0-9]|SizedBox\((height|width): *[0-9]|(height|width): *(1[2-9]|[2-9][0-9])\b)' $FLUTTER_ACTIVE
fi

# ============================================
# 2. Flutter: _deprecated/ (不参与编译, 但主人要求一并变量化)
# ============================================
FLUTTER_DEPRECATED=$(find flutter_app/lib/_deprecated -name '*.dart' 2>/dev/null)
if [ -n "$FLUTTER_DEPRECATED" ]; then
  # shellcheck disable=SC2086
  count "flutter_deprecated.color"    'Color\(0x[0-9A-Fa-f]{6,8}\)'   $FLUTTER_DEPRECATED
  # shellcheck disable=SC2086
  count "flutter_deprecated.fontSize" 'fontSize: *[1-9][0-9]*(\.[0-9]+)?[^0-9]' $FLUTTER_DEPRECATED
  # shellcheck disable=SC2086
  count "flutter_deprecated.spacing"  '(EdgeInsets\.[a-zA-Z]+\([0-9]|SizedBox\((height|width): *[0-9]|(height|width): *(1[2-9]|[2-9][0-9])\b)' $FLUTTER_DEPRECATED
fi

# ============================================
# 3. Web: Tailwind 调色板类 (绕过语义令牌)
# ============================================
WEB_SRC=$(find src -name '*.tsx' -o -name '*.ts' 2>/dev/null | grep -v 'design-tokens.g.ts')
PALETTE='\b(bg|text|border|ring|from|to|via|fill|stroke|divide|outline|decoration|shadow|accent|caret)-(red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose|slate|gray|zinc|neutral|stone)-[0-9]{2,3}\b'
# shellcheck disable=SC2086
count "web.paletteClass" "$PALETTE" $WEB_SRC

# 任意值: [16px] / [1.25rem] / [#fff]
# shellcheck disable=SC2086
count "web.arbitraryValue" '\[(#[0-9A-Fa-f]{3,8}|[0-9.]+(px|rem|em|vh|vw|%)|var\(--)' $WEB_SRC

# 字面 hex (排除 mermaid 架构图 —— 那是图的 DSL 字符串, 不是 CSS)
WEB_HEX=$(echo "$WEB_SRC" | grep -v 'app/admin/dev/architecture/' | grep -v 'components/dev/mermaid-renderer')
# shellcheck disable=SC2086
count "web.hexLiteral" '#[0-9A-Fa-f]{6}\b' $WEB_HEX

# ============================================
# 4. 令牌生成物一致性
# ============================================
TOKENS_OK=1
if ! npx tsx scripts/generate-tokens.ts --check >/tmp/nkb-tokens-check.log 2>&1; then
  TOKENS_OK=0
fi

# ============================================
# 5. Flutter 有没有人绕过 context.tokens 直接读常量主题
# ============================================
# shellcheck disable=SC2086
count "flutter.constThemeRef" 'AppThemes\.[a-z]+\.' $FLUTTER_ACTIVE

# ============================================
# 报告
# ============================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " UI 令牌护栏 (硬编码棘轮)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

KEYS=(flutter.color flutter.fontSize flutter.radius flutter.spacing \
      flutter_deprecated.color flutter_deprecated.fontSize flutter_deprecated.spacing \
      web.paletteClass web.arbitraryValue web.hexLiteral flutter.constThemeRef)

BASELINE_JSON='{}'
[ -f "$BASELINE" ] && BASELINE_JSON=$(cat "$BASELINE")

printf "%-32s %8s %10s   %s\n" "指标" "当前" "基线" "状态"
printf "%s\n" "──────────────────────────────────────────────────────────"

REGRESSED=0
IMPROVED=0
NEWJSON='{}'

for k in "${KEYS[@]}"; do
  cur=${COUNTS[$k]:-0}
  base=$(node -e "
    try { const b=JSON.parse(process.argv[1]); const v=b.counts && b.counts['$k'];
          process.stdout.write(String(v===undefined?'-':v)); } catch(e){ process.stdout.write('-'); }
  " "$BASELINE_JSON")

  if [ "$base" = "-" ]; then
    status="· 新指标"
    [ "$cur" -gt 0 ] && status="⚠ 未登记 ($cur)"
  elif [ "$cur" -gt "$base" ]; then
    status="✗ 上涨 +$((cur - base))"
    REGRESSED=1
  elif [ "$cur" -lt "$base" ]; then
    status="✓ 下降 -$((base - cur))"
    IMPROVED=1
  else
    status="· 持平"
  fi

  printf "%-32s %8s %10s   %s\n" "$k" "$cur" "$base" "$status"
  NEWJSON=$(printf '%s' "$NEWJSON" | node -e "
    let s=''; process.stdin.on('data',d=>s+=d).on('end',()=>{
      const o=JSON.parse(s||'{}'); o['$k']=$cur;
      process.stdout.write(JSON.stringify(o));
    });
  ")

  if [ "$BY_FILE" = "1" ] && [ -n "${FILES[$k]:-}" ]; then
    printf "%s\n" "${FILES[$k]}"
  fi
done

printf "%s\n" "──────────────────────────────────────────────────────────"
printf " 合计硬编码: %s\n" "$TOTAL"
echo ""

if [ "$TOKENS_OK" = "0" ]; then
  echo "✗ 令牌生成物与 design/tokens/design-tokens.json 不一致"
  tail -4 /tmp/nkb-tokens-check.log | sed 's/^/    /'
  echo "  修法: pnpm tokens:build"
  echo ""
  REGRESSED=1
else
  echo "✓ 令牌生成物与 design-tokens.json 一致"
fi
echo ""

# ---- 更新基线 ----
if [ "$UPDATE" = "1" ]; then
  node -e "
    const fs=require('fs');
    const counts=JSON.parse(process.argv[1]);
    const prev = fs.existsSync('$BASELINE') ? JSON.parse(fs.readFileSync('$BASELINE','utf8')) : {};
    const prevCounts = prev.counts || {};
    const dropped = Object.keys(prevCounts).filter(k => counts[k] !== undefined && counts[k] > prevCounts[k]);
    if (dropped.length) {
      console.error('✗ 拒绝写入: 以下指标比基线**上涨**, 棘轮只许往下拧:');
      for (const k of dropped) console.error('    ' + k + ': ' + prevCounts[k] + ' → ' + counts[k]);
      process.exit(1);
    }
    const out = {
      _comment: 'UI 硬编码棘轮基线。修完一批就 tools/check-ui-tokens.sh --update-baseline 往下拧。只许下降。',
      _generatedBy: 'tools/check-ui-tokens.sh --update-baseline',
      updatedAt: new Date().toISOString().slice(0,10),
      total: Object.values(counts).reduce((a,b)=>a+b,0),
      counts,
    };
    fs.writeFileSync('$BASELINE', JSON.stringify(out,null,2)+'\n');
    console.log('✓ 基线已更新: $BASELINE');
    console.log('  合计 ' + (prev.total ?? '?') + ' → ' + out.total);
  " "$NEWJSON"
  exit 0
fi

if [ "$IMPROVED" = "1" ] && [ "$REGRESSED" = "0" ]; then
  echo "💡 有指标下降 —— 跑 tools/check-ui-tokens.sh --update-baseline 把棘轮拧紧一格"
  echo ""
fi

if [ "$REGRESSED" = "1" ] && [ "$STRICT" = "1" ]; then
  echo "✗ 硬编码出现上涨 (或令牌生成物不同步) —— 本次提交被阻断。"
  echo ""
  echo "  修法 (按推荐顺序):"
  echo "    Flutter 颜色  → context.tokens.xxx     (core/theme/theme_ext.dart)"
  echo "    Flutter 间距  → AppSpace.s16 / AppSpace.cardPadding"
  echo "    Flutter 圆角  → AppRadius.card / AppRadius.r12"
  echo "    Flutter 字号  → AppType.md"
  echo "    Web 调色板类  → bg-success-surface / text-content-secondary / border-divider"
  echo "    Web 字面 hex  → var(--brand) 或 import { palette } from '@/lib/design-tokens.g'"
  echo "    缺令牌        → 加进 design/tokens/design-tokens.json 再 pnpm tokens:build"
  echo ""
  exit 1
fi

exit 0
