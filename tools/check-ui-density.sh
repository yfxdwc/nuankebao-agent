#!/usr/bin/env bash
# ============================================
# UI 密度护栏 (B4, 2026-09-24) — 防「卡片墙回潮 / 行高变胖」再生
# ============================================
#
# 为什么需要 (tools/density-report.sh 只打印指标, 不会 fail):
#   `density-probe.mjs` 用 cardsLike / visibleRows 量化密度, 但**没有断言**。
#   本脚本读 `design/tokens/density-baseline.json`, 跑真浏览器探测, 然后断言:
#     1. **framed (有边框或有阴影的容器)**  ≤ 基线   (上限棘轮, 上涨 = fail)
#     2. **visibleRows @ 1440x900** ≥ 10              (下限棘轮, 列表路由跌破 = fail)
#     3. **rowHeight** 偏离基线 ≥ +20 报警            (行高变胖 → 中老年版回潮)
#
# 棘轮语义 (与 check-ui-tokens.sh 一致):
#   - 当前 framed > 基线 → fail (卡片墙回潮)
#   - 列表路由 visibleRows < 基线 → fail (密度反弹)
#   - framed 减少 / visibleRows 增加 → 提示 `--update-baseline`
#
# 用法:
#   bash tools/check-ui-density.sh                       # 报告 + 断言 (CI / pre-commit)
#   bash tools/check-ui-density.sh --update-baseline      # 把当前值写入 baseline (只在变好时用)
#
# ⚠ 前置:
#   - 跑之前先确认 dev server 活着:
#       curl -s -o /dev/null -w '%{http_code}' localhost:3003/login   # 必须 200
#   - 用真浏览器登录后采集 (NODE_ENV=production 时也要登录; dev = DEV_SKIP_AUTH 旁路)
#   - ⚠ AGENTS §5: 不要并发打 30+ API 请求 (dev mode 内存爆);
#     本脚本内部是顺序探针, 不并发. 但**别同时跑其他探测脚本** (会被 dev mode 拖累).
#   - AGENTS §5: 等构建用 wait-flutter-web-build.sh; 等服务用本脚本里的 HEAD_CHECK.
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT=$(pwd)

STRICT=1  # 始终是 CI 模式; 默认就 fail
UPDATE=0
for arg in "$@"; do
  case "$arg" in
    --update-baseline) UPDATE=1; STRICT=0 ;;
    -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
    *) echo "未知参数: $arg"; exit 2 ;;
  esac
done

BASELINE="$ROOT/design/tokens/density-baseline.json"
[[ -f "$BASELINE" ]] || { echo "✗ 找不到基线 $BASELINE"; exit 1; }

# ---- 1. dev server 必须活着 (AGENTS §5 「dev server 被打挂时验证 UI = 看缓存自欺」) ----
HEAD_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 localhost:3003/login 2>/dev/null || echo 000)
if [[ "$HEAD_CODE" != "200" ]]; then
  echo "✗ dev server 没活着 (HTTP $HEAD_CODE) —— 先确认服务起, 再跑本脚本"
  echo "  重启:  systemctl --user restart nuankebao-nextjs.service   # dev"
  echo "  或:     nohup npx next start -p 3003 > /tmp/nkb-ui-refresh/logs/next-start.log 2>&1 &   # prod"
  exit 1
fi

# ---- 2. 跑探针 (复用 tools/ui-acceptance-probe.mjs — 已含登录 + 真浏览器 + 真数据) ----
OUT_DIR=$(mktemp -d)
VIEWPORTS=${VIEWPORTS:-"1440x900,375x812"}
ROUTES=${ROUTES:-"/admin,/admin/customers,/admin/follow-ups,/admin/interactions,/admin/wellness-records"}
NKB_IDENT=${NKB_IDENT:-13822200001}
NKB_PW=${NKB_PW:-Test12345}

VIEWPORTS="$VIEWPORTS" ROUTES="$ROUTES" OUT_DIR="$OUT_DIR" \
  NKB_IDENT="$NKB_IDENT" NKB_PW="$NKB_PW" \
  JSON=1 timeout 600 node tools/ui-acceptance-probe.mjs > "$OUT_DIR/probe.json" 2>&1 \
  || { echo "✗ 探针失败, 看 $OUT_DIR/probe.json"; exit 2; }

# ---- 3. 解析 + 对照基线 ----
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " UI 密度护栏 (B4)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

REGRESSED=0
IMPROVED=0
NEW_ROUTES_JSON="{}"

# 用 node 解析两份 JSON, 逐路由断言
node -e "
const fs = require('fs');
const baseline = JSON.parse(fs.readFileSync('$BASELINE', 'utf8'));
const probe = JSON.parse(fs.readFileSync('$OUT_DIR/probe.json', 'utf8'));
const routes = baseline._routes || {};
const isList = (r, vp) => {
  const k = r + '|' + vp;
  const e = routes[r] && (routes[r + '||' + vp] ?? null);
  // _routes 是 plain object key=route, 但同一路由多 vp; 用显式 vp 查询
  return routes[r + '||'] === undefined ? false : false;
};

const rows = probe.rows || [];
const out = [];
let regressed = 0, improved = 0;
const newRoutes = {};

// 索引化 baseline._routes (key 已经是 route@viewport 格式, 见 density-baseline.json)
const baseIdx = {};
for (const [k, v] of Object.entries(routes)) {
  // 跳过 _comment / _rules / _source 等元数据键 (它们不是路由)
  if (k.startsWith('_')) continue;
  baseIdx[k] = v;
}

for (const r of rows) {
  const key = r.route + '@' + r.viewport;
  const base = baseIdx[key];
  if (!base) {
    // 无基线时只报告 (本批不写基线的路由), 不 fail
    console.log(
      r.route.padEnd(28) + ' ' + r.viewport.padEnd(10) +
      ' framed=' + String(r.framed).padStart(2) +
      ' visibleRows=' + String(r.visibleRows).padStart(2) +
      ' rowHeight=' + String(r.rowHeight).padStart(3) + ' · 无基线 (跳过)'
    );
    continue;
  }
  const lines = [];
  let localRegress = false;
  let localImprove = false;
  // 断言 1: framed ≤ 基线 (上限棘轮)
  if (r.framed > base.framed) {
    lines.push('framed ' + r.framed + ' > ' + base.framed + ' ✗ 上涨');
    localRegress = true;
  } else if (r.framed < base.framed) {
    lines.push('framed ' + r.framed + ' < ' + base.framed + ' ✓ 下降');
    localImprove = true;
  } else {
    lines.push('framed ' + r.framed + ' = ' + base.framed + ' · 持平');
  }
  // 断言 2: 列表路由 visibleRows ≥ 基线 (下限棘轮); 非列表路由只报警告
  if (base.isListRoute) {
    if (r.visibleRows < base.visibleRows) {
      lines.push('visibleRows ' + r.visibleRows + ' < ' + base.visibleRows + ' ✗ 跌破');
      localRegress = true;
    } else if (r.visibleRows > base.visibleRows) {
      lines.push('visibleRows ' + r.visibleRows + ' > ' + base.visibleRows + ' ✓ 涨');
      localImprove = true;
    } else {
      lines.push('visibleRows ' + r.visibleRows + ' = ' + base.visibleRows + ' · 持平');
    }
    // 行高变胖 (≥ +20px) 也算回潮
    if (r.rowHeight > 0 && base.rowHeight > 0 && r.rowHeight - base.rowHeight >= 20) {
      lines.push('rowHeight ' + r.rowHeight + ' > ' + base.rowHeight + ' ✗ 涨 ≥20 (中老年版回潮?)');
      localRegress = true;
    }
  } else {
    if (r.visibleRows < 10 && r.rowHeight > 0) {
      // 非列表路由的 visibleRows 仅供参考
      lines.push('visibleRows ' + r.visibleRows + ' (非列表路由, 不卡下限)');
    }
  }
  if (localRegress) regressed++;
  if (localImprove) improved++;
  // 拼一行表格
  console.log(
    r.route.padEnd(28) + ' ' + r.viewport.padEnd(10) +
    ' framed=' + String(r.framed).padStart(2) +
    ' visibleRows=' + String(r.visibleRows).padStart(2) +
    ' rowHeight=' + String(r.rowHeight).padStart(3) + ' ' +
    lines.join(' | ')
  );
  newRoutes[key] = {
    route: r.route,
    viewport: r.viewport,
    framed: r.framed,
    visibleRows: r.visibleRows,
    rowHeight: r.rowHeight,
    isListRoute: base.isListRoute,
  };
}

console.log('──────────────────────────────────────────────────────────');
console.log(' 路由: ' + rows.length + ' 退化: ' + regressed + ' 改进: ' + improved);

// 写临时文件供 shell 读
fs.writeFileSync('$OUT_DIR/summary.json', JSON.stringify({regressed, improved, newRoutes}, null, 2));
process.exit(regressed > 0 ? 1 : 0);
" || REGRESSED=1

# ---- 4. 更新基线 (上涨拒绝写入, 同 check-ui-tokens.sh) ----
if [[ "$UPDATE" == "1" ]]; then
  if [[ -f "$OUT_DIR/summary.json" ]]; then
    SUMMARY=$(cat "$OUT_DIR/summary.json")
    REGRESSED=$(node -e "console.log(JSON.parse(process.argv[1]).regressed)" "$SUMMARY")
    if [[ "$REGRESSED" -gt 0 ]]; then
      echo "✗ 拒绝写入: 有路由退化 (regressed=$REGRESSED) —— 棘轮只许往下拧"
      rm -rf "$OUT_DIR"
      exit 1
    fi
    node -e "
      const fs = require('fs');
      const summary = JSON.parse(fs.readFileSync('$OUT_DIR/summary.json', 'utf8'));
      const baseline = JSON.parse(fs.readFileSync('$BASELINE', 'utf8'));
      // 合并: 新测值替换 ref,但保留
      for (const [k, v] of Object.entries(summary.newRoutes)) {
        baseline._routes[k] = v;
      }
      baseline.updatedAt = new Date().toISOString().slice(0, 10);
      fs.writeFileSync('$BASELINE', JSON.stringify(baseline, null, 2) + '\n');
      console.log('✓ 基线已更新: ' + '$BASELINE');
    "
  fi
  rm -rf "$OUT_DIR"
  exit 0
fi

rm -rf "$OUT_DIR"
exit "$REGRESSED"