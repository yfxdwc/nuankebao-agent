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
  # 默认 POSIX ERE。个别需 PCRE (负向先行 (?!)) 的指标调用前 export GREP_PC=1 切换。
  if [ "${GREP_PC:-}" = "1" ]; then
    n=$(grep -rPo "$pattern" "$@" 2>/dev/null | wc -l | tr -d ' ')
  else
    n=$(grep -rEo "$pattern" "$@" 2>/dev/null | wc -l | tr -d ' ')
  fi
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
  -not -path '*/core/theme/*' 2>/dev/null)

# ---- 文件级白名单 (B4, 2026-09-24 加) ----
#   flutter.cardWidget 若确有正当用途 (例: Dialog 内嵌、Sheet 顶部、单实体卡) →
#   把路径加进下面数组, **注明理由 + 拍板日期**。 禁止行号级豁免 (行号会漂移)。
#   改本数组时, 同步在 AGENTS §5「卡片墙回潮」反模式里加一条备注。
FLUTTER_CARD_WHITELIST=(
  # (空 = 无豁免; 真有需要再加, 拍板日期格式 YYYY-MM-DD)
)

# shellcheck disable=SC2086
if [ -n "$FLUTTER_ACTIVE" ]; then
  count "flutter.color"        'Color\(0x[0-9A-Fa-f]{6,8}\)'   $FLUTTER_ACTIVE
  count "flutter.fontSize"     'fontSize: *[1-9][0-9]*(\.[0-9]+)?[^0-9]' $FLUTTER_ACTIVE
  count "flutter.radius"       'BorderRadius\.circular\([0-9]'  $FLUTTER_ACTIVE
  count "flutter.spacing"      '(EdgeInsets\.[a-zA-Z]+\([0-9]|SizedBox\((height|width): *[0-9]|(height|width): *(1[2-9]|[2-9][0-9])\b)' $FLUTTER_ACTIVE

  # B4 新增: 卡片墙回潮信号
  #   flutter.cardWidget: Card( 调用 —— 原则 4 说列表项 / 同质块不应用 Card
  #   flutter.legacyBigWidget: BigButton / BigFab 旧大号组件 (B 档拍板不用的)
  #   两个都进棘轮: 只许下降, 不许上涨
  if [ "${#FLUTTER_CARD_WHITELIST[@]}" -gt 0 ] && [ "$FLUTTER_ACTIVE" ]; then
    WL_FILTER=$(printf -- '-not -path %s ' "${FLUTTER_CARD_WHITELIST[@]}")
    # shellcheck disable=SC2086
    FLUTTER_CARD_SCAN=$(eval "find flutter_app/lib -name '*.dart' $WL_FILTER")
  else
    FLUTTER_CARD_SCAN="$FLUTTER_ACTIVE"
  fi
  # shellcheck disable=SC2086
  count "flutter.cardWidget"     'Card\('                       $FLUTTER_CARD_SCAN

  # flutter.legacyBigWidget: BigButton / BigFab 旧大号组件。
  #   ⚠ 这些组件名常出现在注释里 (「已退役」「不再使用」之类说明) —— 注释不算违规。
  #   先 sed 掉 // 后内容再 grep, 把注释里的提及当作文档而不是代码。
  TMP=$(mktemp)
  sed -E 's|/\*[^*]*\*+([^/*][^*]*\*+)*/||g; s|//.*$||g' $FLUTTER_ACTIVE 2>/dev/null \
    | grep -E '(BigButton|BigFab)' > "$TMP" || true
  N_BIG=$(wc -l < "$TMP" | tr -d ' ')
  rm -f "$TMP"
  COUNTS["flutter.legacyBigWidget"]=$N_BIG
  TOTAL=$((TOTAL + N_BIG))
fi

# ============================================
# 3. Web: Tailwind 调色板类 (绕过语义令牌)
# ============================================
WEB_SRC=$(find src -name '*.tsx' -o -name '*.ts' 2>/dev/null \
  | grep -v 'design-tokens.g.ts' \
  | grep -v '^src/components/preview/' \
  | grep -v '^src/app/app-preview/' \
  | grep -v '^src/app/preview/')
# ↑ 后三条是 AGENTS §9.1 冻结的预览框架路径 —— 改了会被 pre-commit guard 阻断, 故不计入
PALETTE='\b(bg|text|border|ring|from|to|via|fill|stroke|divide|outline|decoration|shadow|accent|caret)-(red|orange|amber|yellow|lime|green|emerald|teal|cyan|sky|blue|indigo|violet|purple|fuchsia|pink|rose|slate|gray|zinc|neutral|stone)-[0-9]{2,3}\b'
# shellcheck disable=SC2086
count "web.paletteClass" "$PALETTE" $WEB_SRC

# 任意值: [16px] / [1.25rem] / [#fff]
# vh/vw/% 是视口相对单位 (没有"绝对值令牌"可替) → 不计入
# shellcheck disable=SC2086
count "web.arbitraryValue" '\[(#[0-9A-Fa-f]{3,8}|[0-9.]+(px|rem|em)|var\(--)' $WEB_SRC

# 字面 hex (排除 mermaid 架构图 —— 那是图的 DSL 字符串, 不是 CSS;
#           排除冻结的预览框架路径)
# 注释里提到 hex 不算硬编码 → 先把 // 和 /* */ 剥掉再扫
WEB_HEX=$(echo "$WEB_SRC" | grep -v 'app/admin/dev/architecture/' | grep -v 'components/dev/mermaid-renderer')
if [ -n "$WEB_HEX" ]; then
  # shellcheck disable=SC2086
  n_hex=$(grep -rhE '#[0-9A-Fa-f]{6}\b' $WEB_HEX 2>/dev/null \
    | sed -E 's|/\*[^*]*\*/||g; s|//.*$||g' \
    | grep -cE '#[0-9A-Fa-f]{6}\b' || true)
  COUNTS["web.hexLiteral"]=${n_hex:-0}
  TOTAL=$((TOTAL + ${n_hex:-0}))
fi

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

# ---- Flutter 新增指标 (P2-P5 漏网补漏, 2026-09-24 加) ----
#
# flutter.toolbarHeight: AppBar 高度必须用 token
#   P2 漏网的元凶 (之前批次 1-3 都漏扫了) —— 当时 15 处全 Flutter 写死 64
#   现在应该恒为 0; 不涨 = 没人"顺手写 64"
count "flutter.toolbarHeight" 'toolbarHeight: *[0-9]+' $FLUTTER_ACTIVE

# flutter.iconSize: Icon(...) 内的 size 硬数字
#   简化版: 只匹配 Icon( 后的 size: 数字 —— 不加负向先行 (IconBuilder 在用 Icon 的代码库
#   里极少, 不强求零误伤; 比起 PCRE 的复杂度收益更大)
#   例外白名单: LoadingState.size: / QrImage.size: / SizedBox 都是非 Icon 上下文
count "flutter.iconSize" 'Icon\([^I)]*?size: *[0-9]+(\.[0-9]+)?[,)]' $FLUTTER_ACTIVE
#   匹配 SnackBar.showSnackBar(duration: Duration(seconds: N))
#   业务 timing (telemetry flush / auth init / api timeout / 搜索 debounce)
#   在白名单路径, 不计入 —— 它们是业务时长, 不是 UI 动效
MOTION_FILES=$(echo "$FLUTTER_ACTIVE" | grep -v -E '(/telemetry/|/http/api_client\.dart|/auth/screens/login_screen\.dart|/auth/providers/auth_provider\.dart)')
# shellcheck disable=SC2086
count "flutter.motionDuration" 'duration: Duration\(+seconds: *[2-6]\)' $MOTION_FILES

# flutter.radiusRadius: 独立 Radius.circular(N) (不经 BorderRadius)
#   BorderRadius.circular(N) 已由 flutter.radius 覆盖; 这个是独立使用场景
count "flutter.radiusRadius" 'Radius\.circular\([0-9]+' $FLUTTER_ACTIVE

# ============================================
# 报告
# ============================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " UI 令牌护栏 (硬编码棘轮)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

KEYS=(flutter.color flutter.fontSize flutter.radius flutter.spacing \
      flutter.toolbarHeight flutter.iconSize flutter.motionDuration flutter.radiusRadius \
      flutter.constThemeRef \
      flutter.cardWidget flutter.legacyBigWidget \
      web.paletteClass web.arbitraryValue web.hexLiteral)

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
