#!/usr/bin/env bash
# ============================================
# 暖客宝 drizzle-kit generate 护栏 (2026-09-23 立, 主人拍板)
# ============================================
# 背景: docs/backlog.md 「技术债 · drizzle snapshot 只到 0016」条目
#   + drizzle/0024_app_config.sql 顶部注释
#   drizzle/meta/ snapshot 只到 0016; 之后 0017-0024 都是手写迁移。
#   直接跑 `npx drizzle-kit generate` 会把 0017-0024 的变更**整段重放**到一份
#   「0025_xxx.sql」里 → apply 到已有库 = 重复 ALTER / 重复建表, 灾难。
#
# 用途: 包住 `npx drizzle-kit generate`, 在**临时目录**里跑 dry-run, 仓库
#       drizzle/ 永不被污染; 然后检测输出里有没有「对已存在表/列/索引的
#       危险重放」。命中 → exit 1; 没命中 → exit 0 + 提醒人工 review。
#
# 设计 (AGENTS §3 该做项「改了 migration 必跑 db:compat」同根):
#   - 临时目录跑 generate (复制 meta 进 tmp + 软链 schema.ts + tmp 专属 config)
#   - trap EXIT 兜底清理, 任何失败路径都不会留垃圾
#   - 纯函数 detectReplay 在 tools/check-drizzle-generate.ts (可单测)
#   - 「仓库已有表/索引」自动 grep drizzle/*.sql, 跟 schema 自动同步
#   - 命中模式: CREATE 已存在表 / ALTER 已存在表 / DROP 已存在索引
#
# 用法:
#   pnpm db:generate                       # 走此护栏 (package.json 已替换)
#   bash tools/check-drizzle-generate.sh --verbose   # 看 generate 原始输出
#   bash tools/check-drizzle-generate.sh --check     # 自检, 不真跑 drizzle-kit
# ============================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DETECT_TS="$SCRIPT_DIR/check-drizzle-generate.ts"

# 颜色 (CI / log 友好)
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============ 参数 ============
VERBOSE=0
CHECK_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
    --check) CHECK_ONLY=1 ;;
    --help|-h)
      echo "用法: bash tools/check-drizzle-generate.sh [--verbose] [--check]"
      echo "  默认: dry-run drizzle-kit generate + 检测「重放历史变更」危险"
      echo "  --verbose: 额外打印 drizzle-kit 原始输出 + 生成的 .sql 全文"
      echo "  --check:   只自检 (不真跑 drizzle-kit, 用于 CI/调试护栏本身)"
      exit 0
      ;;
  esac
done

# ============ CHECK ONLY 模式 (调试 / CI 验收护栏本身) ============
if [ "$CHECK_ONLY" = "1" ]; then
  echo -e "${CYAN}=== drizzle-generate-guard 自检 ===${NC}"
  echo -e "仓库路径:   $PROJECT_ROOT"
  echo -e "drizzle/:   $PROJECT_ROOT/drizzle"
  sql_count=$(ls "$PROJECT_ROOT/drizzle"/*.sql 2>/dev/null | grep -vc '^audit_' || true)
  echo -e "迁移文件数: $sql_count (排除 audit_*.sql)"
  echo -e "检测纯函数: $DETECT_TS"
  echo -e "退出: 0 (自检通过)"
  exit 0
fi

# ============ 环境检查 ============
if [ ! -f "$PROJECT_ROOT/.env.local" ]; then
  echo -e "${RED}❌ 找不到 .env.local (drizzle.config.ts 加载需要, 即便 generate 不真连库)${NC}" >&2
  exit 2
fi
if [ ! -f "$DETECT_TS" ]; then
  echo -e "${RED}❌ 找不到 $DETECT_TS (护栏检测逻辑文件丢失)${NC}" >&2
  exit 2
fi

# ============ 准备临时目录 ============
# trap EXIT 是关键: 任何退出路径 (正常 / 报错 / Ctrl-C) 都保证清理临时目录,
# 避免 .git/ 缓存或外部工具误把它当成仓库产物 (AGENTS §5「APK 分发走 volume
# mount, 不靠 commit」同根思想: 临时产物不进 git)。
TMPDIR=$(mktemp -d -p /tmp drizzle-generate-guard.XXXXXX)
if [ ! -d "$TMPDIR" ]; then
  echo -e "${RED}❌ 无法创建临时目录${NC}" >&2
  exit 2
fi

cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

mkdir -p "$TMPDIR/drizzle" "$TMPDIR/src/lib/db"

# 关键步骤:
#   1. 复制 meta/ 进 TMPDIR — drizzle-kit 读这里判断「上次到哪」。
#      没这一步它会认为从没跑过 migration, 把 schema.ts 整体输出 → 假阳性爆炸。
#   2. 软链 schema.ts — 走 schema 解析但不复制 (避免污染)。
#   3. 临时 config — out 指向 TMPDIR (仓库 drizzle/ 不被写)。
cp -r "$PROJECT_ROOT/drizzle/meta" "$TMPDIR/drizzle/meta"
ln -sf "$PROJECT_ROOT/src/lib/db/schema.ts" "$TMPDIR/src/lib/db/schema.ts"

cat > "$TMPDIR/drizzle.config.ts" <<'EOF'
import type { Config } from "drizzle-kit";
export default {
  schema: "./src/lib/db/schema.ts",
  out: "./drizzle",
  dialect: "postgresql",
  dbCredentials: { url: process.env.DATABASE_URL ?? "postgres://x@localhost/x" },
  strict: true,
  verbose: false,
} satisfies Config;
EOF

# ============ 在临时目录跑 drizzle-kit generate ============
cd "$TMPDIR"

echo -e "${CYAN}=== drizzle-kit generate dry-run (隔离临时目录) ===${NC}"
echo -e "${CYAN}仓库 drizzle/ 永不被碰 — trap EXIT 兜底清理 TMPDIR${NC}"
echo ""

# 占位 DATABASE_URL — drizzle-kit generate 不真连库, 但 config 加载时校验非空。
# 用仓库的 node_modules (--prefix) 避免 npx 现拉版本。
export DATABASE_URL="postgres://guard@localhost/guard"

GENERATE_LOG="$TMPDIR/.generate-output.txt"
GENERATE_EXIT=0
npx --prefix "$PROJECT_ROOT" --no-install drizzle-kit generate > "$GENERATE_LOG" 2>&1 || GENERATE_EXIT=$?

# ============ 找生成的 .sql (用 nullglob 防空匹配时返回原串) ============
shopt -s nullglob
GENERATED_SQLS=("$TMPDIR/drizzle/00"*.sql)
shopt -u nullglob

if [ "$VERBOSE" = "1" ]; then
  echo "--- drizzle-kit generate 原始输出 ---"
  cat "$GENERATE_LOG"
  echo "--- (drizzle-kit exit: $GENERATE_EXIT) ---"
  echo ""
fi

# drizzle-kit 完全没生成文件 = schema 与最新 snapshot 一致 (最理想情况)
if [ "${#GENERATED_SQLS[@]}" -eq 0 ]; then
  # 若 drizzle-kit 报错且没生成文件 → 透传错误, 不是「重放」问题
  if [ "$GENERATE_EXIT" -ne 0 ]; then
    echo -e "${RED}❌ drizzle-kit generate 失败 (exit $GENERATE_EXIT)${NC}" >&2
    cat "$GENERATE_LOG" >&2
    exit $GENERATE_EXIT
  fi
  echo -e "${GREEN}✅ drizzle-kit generate: 无新变更 (schema 与最新 snapshot 完全一致)${NC}"
  echo -e "${CYAN}   这是最理想情况 — 不需要新 migration。${NC}"
  exit 0
fi

# 选了第一个文件 — drizzle-kit generate 一次只产一条 (我们传入的 meta 是连续的,
# 不会一次蹦两条; 万一蹦了, 头一条就是最新的)
GENERATED_SQL="${GENERATED_SQLS[0]}"

# ============ 检测危险 (调纯函数) ============
# 显式传仓库 drizzle/ 路径, 避免「检测函数与生成输出在同一目录」造成自我污染
# (drizzle-kit generate 把 0025_xxx.sql 写到 TMPDIR/drizzle/, 与检测函数要扫的目录同名)
DETECT_EXIT=0
DATABASE_URL="postgres://guard@localhost/guard" \
  npx --prefix "$PROJECT_ROOT" --no-install tsx "$DETECT_TS" "$GENERATED_SQL" "$PROJECT_ROOT/drizzle" \
  || DETECT_EXIT=$?

if [ "$DETECT_EXIT" -ne 0 ]; then
  echo -e "${RED}❌ 检测到「重放历史变更」危险 — drizzle-kit generate 输出是 snapshot 落后的假 diff${NC}" >&2
  echo -e "${RED}   不要 apply 这条 generate, 见上方说明 + docs/backlog.md 技术债条目${NC}" >&2
  if [ "$VERBOSE" = "1" ]; then
    echo ""
    echo "--- drizzle-kit 生成的 .sql 全文 (仅供调试) ---"
    cat "$GENERATED_SQL"
  else
    echo ""
    echo -e "${CYAN}   (re-run with --verbose 看 drizzle-kit 原始输出 + 生成的 .sql 全文)${NC}"
  fi
  exit 1
fi

# ============ 通过 ============
echo -e "${GREEN}✅ drizzle-kit generate dry-run 通过危险检测${NC}"
echo -e "${CYAN}   生成的 SQL 没命中「重放已存在表/列/索引」模式${NC}"
echo -e "${CYAN}   但仍要人工 review — 加列/约束的语义是否合规, 走 ADR-0004 + pnpm db:compat${NC}"
echo ""
echo -e "${CYAN}   生成的 .sql (隔离目录, trap EXIT 自动清理):${NC}"
echo -e "${CYAN}   $GENERATED_SQL${NC}"
if [ "$VERBOSE" = "1" ]; then
  echo ""
  echo "--- 生成的 SQL 全文 ---"
  cat "$GENERATED_SQL"
fi
exit 0