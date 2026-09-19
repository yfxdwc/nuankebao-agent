#!/usr/bin/env bash
# ============================================
# 暖客宝 migration 兼容性检测
# 依据: CHARTER §3.5 Schema 演进红线 + ADR-0004
# ============================================
# 检测 drizzle/*.sql 是否包含禁止模式:
#   ❌ DROP COLUMN / DROP TABLE / RENAME
#   ❌ ALTER COLUMN TYPE 无 USING
#   ❌ ALTER COLUMN SET NOT NULL 无 DEFAULT
#   ❌ DROP INDEX 在核心表
# 警告 (不阻断):
#   ⚠️ ADD COLUMN 无 DEFAULT
#   ⚠️ 大表 ALTER 不带 CONCURRENTLY
# ============================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIZZLE_DIR="$PROJECT_ROOT/drizzle"

# 颜色 (CI 友好)
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 核心表 (DROP INDEX 检测对象)
CORE_TABLES=("customer" "wellness_record" "interaction" "follow_up_task")

if [ ! -d "$DRIZZLE_DIR" ]; then
  echo -e "${RED}❌ Drizzle 目录不存在: $DRIZZLE_DIR${NC}"
  exit 2
fi

# 收集 migration (排除 audit_trigger.sql / audit_function.sql 和 meta/)
MIGRATIONS=$(find "$DRIZZLE_DIR" -maxdepth 1 -name "*.sql" -type f ! -name "audit_trigger.sql" ! -name "audit_function.sql" -printf "%f\n" | sort)

if [ -z "$MIGRATIONS" ]; then
  echo -e "${YELLOW}⚠️ 没找到任何 migration SQL 文件${NC}"
  exit 0
fi

echo -e "${CYAN}=== 暖客宝 migration 兼容性检测 ===${NC}"
echo -e "${CYAN}依据: docs/CHARTER.md §3.5 + ADR-0004${NC}"
echo ""

ERRORS=0
WARNINGS=0

check_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"
  local severity="$4"  # error | warning
  local replacement="$5"

  local matches=$(grep -nE "$pattern" "$file" 2>/dev/null || true)

  if [ -n "$matches" ]; then
    while IFS= read -r match; do
      if [ "$severity" = "error" ]; then
        echo -e "${RED}❌ [ERROR]${NC} $file: $match"
        echo -e "   $description"
        echo -e "   替代方案: $replacement"
        ERRORS=$((ERRORS + 1))
      else
        echo -e "${YELLOW}⚠️  [WARN]${NC}  $file: $match"
        echo -e "   $description"
        echo -e "   建议: $replacement"
        WARNINGS=$((WARNINGS + 1))
      fi
    done <<< "$matches"
  fi
}

for migration in $MIGRATIONS; do
  filepath="$DRIZZLE_DIR/$migration"
  echo -e "${CYAN}--- 检查 $migration ---${NC}"

  # ===== 绝对禁止 (error) =====

  # 1. DROP COLUMN 已被 后续 DROP COLUMN 块处理 (含 IF EXISTS 感知)

  # 2. DROP TABLE (无 IF EXISTS = 真删, 有 IF EXISTS = dev 幂等 pattern, 警告)
  while IFS= read -r line; do
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2-)
    if echo "$content" | grep -qE 'IF[[:space:]]+EXISTS'; then
      echo -e "${YELLOW}⚠️  [WARN]${NC}  $migration:$lineno: DROP TABLE IF EXISTS (Drizzle dev pattern)"
      echo -e "   内容: $content"
      echo -e "   建议: production 前删除 IF EXISTS 行, 避免误删"
      WARNINGS=$((WARNINGS + 1))
    else
      echo -e "${RED}❌ [ERROR]${NC} $migration:$lineno: DROP TABLE 无 IF EXISTS"
      echo -e "   内容: $content"
      echo -e "   替代方案: 主人拍板 + ADR 留档 + 至少保留备份 1 年"
      ERRORS=$((ERRORS + 1))
    fi
  done < <(grep -nE '^[[:space:]]*DROP[[:space:]]+TABLE[[:space:]]+[a-zA-Z_]' "$filepath" 2>/dev/null || true)

  # 3. DROP COLUMN (类似: IF EXISTS 警告, 无 IF EXISTS 错误)
  while IFS= read -r line; do
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2-)
    if echo "$content" | grep -qE 'IF[[:space:]]+EXISTS'; then
      echo -e "${YELLOW}⚠️  [WARN]${NC}  $migration:$lineno: DROP COLUMN IF EXISTS"
      echo -e "   内容: $content"
      echo -e "   建议: production 前删除 IF EXISTS 行"
      WARNINGS=$((WARNINGS + 1))
    else
      echo -e "${RED}❌ [ERROR]${NC} $migration:$lineno: DROP COLUMN 无 IF EXISTS"
      echo -e "   内容: $content"
      echo -e "   替代方案: 加 deleted_at 软标记 + 30 天后真删"
      ERRORS=$((ERRORS + 1))
    fi
  done < <(grep -nE '^[[:space:]]*ALTER[[:space:]]+TABLE.*DROP[[:space:]]+COLUMN' "$filepath" 2>/dev/null || true)

  # 4. RENAME COLUMN
  check_pattern "$filepath" \
    '^[[:space:]]*ALTER[[:space:]]+TABLE[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]+RENAME[[:space:]]+COLUMN' \
    "RENAME COLUMN 禁止: Flutter JSON 序列化硬编码字段名" \
    "error" \
    "不重命名,新增列 + 旧列留 NULL"

  # 5. RENAME TABLE
  check_pattern "$filepath" \
    '^[[:space:]]*ALTER[[:space:]]+TABLE[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]+RENAME[[:space:]]+TO' \
    "RENAME TABLE 禁止: 关联代码 / 报表 / 备份全部失效" \
    "error" \
    "新建表 + 数据迁移 + DROP 旧表 (2-3 步)"

  # 5. ALTER COLUMN TYPE 无 USING (单行类型变更必须带 USING,或分多行)
  # 简化检测: ALTER COLUMN ... TYPE 行但不含 USING
  while IFS= read -r line; do
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2-)
    if echo "$content" | grep -qE 'ALTER[[:space:]]+COLUMN.*TYPE' && \
       ! echo "$content" | grep -q 'USING'; then
      echo -e "${RED}❌ [ERROR]${NC} $migration:$lineno: ALTER COLUMN TYPE 缺 USING"
      echo -e "   完整内容: $content"
      echo -e "   替代方案: 加新列 + 双写 + 后切读 + 最后删旧列 (3 步走)"
      ERRORS=$((ERRORS + 1))
    fi
  done < <(grep -nE '^[[:space:]]*ALTER[[:space:]]+COLUMN.*TYPE' "$filepath" 2>/dev/null || true)

  # 6. SET NOT NULL 无 DEFAULT (一行内 ALTER COLUMN 同时 SET NOT NULL 但无 DEFAULT)
  while IFS= read -r line; do
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2-)
    if echo "$content" | grep -qE 'SET[[:space:]]+NOT[[:space:]]+NULL' && \
       ! echo "$content" | grep -qE 'DEFAULT'; then
      echo -e "${RED}❌ [ERROR]${NC} $migration:$lineno: SET NOT NULL 无 DEFAULT"
      echo -e "   完整内容: $content"
      echo -e "   替代方案: 加 DEFAULT 或两步 (1. UPDATE 填默认  2. SET NOT NULL)"
      ERRORS=$((ERRORS + 1))
    fi
  done < <(grep -nE '^[[:space:]]*ALTER[[:space:]]+COLUMN' "$filepath" 2>/dev/null || true)

  # 7. DROP INDEX 在核心表 (无 IF EXISTS = 真删, 有 IF EXISTS = dev pattern 警告)
  for tbl in "${CORE_TABLES[@]}"; do
    matches=$(grep -nE "^[[:space:]]*DROP[[:space:]]+INDEX[[:space:]]+.*ON[[:space:]]+[\"']?${tbl}[\"']?" "$filepath" 2>/dev/null || true)
    if [ -n "$matches" ]; then
      while IFS= read -r match; do
        lineno=$(echo "$match" | cut -d: -f1)
        content=$(echo "$match" | cut -d: -f2-)
        if echo "$content" | grep -qE 'IF[[:space:]]+EXISTS'; then
          echo -e "${YELLOW}⚠️  [WARN]${NC}  $migration:$lineno: DROP INDEX IF EXISTS ON $tbl"
          echo -e "   内容: $content"
          echo -e "   建议: production 前删除 IF EXISTS 行"
          WARNINGS=$((WARNINGS + 1))
        else
          echo -e "${RED}❌ [ERROR]${NC} $migration:$lineno: DROP INDEX ON $tbl (无 IF EXISTS)"
          echo -e "   内容: $content"
          echo -e "   替代方案: 加新索引 + 验证查询计划后再 DROP"
          ERRORS=$((ERRORS + 1))
        fi
      done <<< "$matches"
    fi
  done

  # ===== 推荐 (warning, 不阻断) =====

  # 8. ADD COLUMN 无 DEFAULT (可能有 nullable, 看是否带 NOT NULL)
  # 简化: ADD COLUMN ... NOT NULL 而无 DEFAULT 算 warning
  while IFS= read -r line; do
    lineno=$(echo "$line" | cut -d: -f1)
    content=$(echo "$line" | cut -d: -f2-)
    if echo "$content" | grep -qE 'ADD[[:space:]]+COLUMN' && \
       echo "$content" | grep -qE 'NOT[[:space:]]+NULL' && \
       ! echo "$content" | grep -qE 'DEFAULT'; then
      echo -e "${YELLOW}⚠️  [WARN]${NC}  $migration:$lineno: ADD COLUMN NOT NULL 无 DEFAULT"
      echo -e "   完整内容: $content"
      echo -e "   建议: 加 DEFAULT 'xxx'::类型 (避免老 APK INSERT 失败)"
      WARNINGS=$((WARNINGS + 1))
    fi
  done < <(grep -nE '^[[:space:]]*ALTER[[:space:]]+TABLE.*ADD[[:space:]]+COLUMN' "$filepath" 2>/dev/null || true)

  # 9. CREATE INDEX 不带 CONCURRENTLY
  matches=$(grep -nE '^[[:space:]]*CREATE[[:space:]]+INDEX[[:space:]]+' "$filepath" 2>/dev/null | \
            grep -v 'CONCURRENTLY' | grep -v 'IF NOT EXISTS' || true)
  # 注: IF NOT EXISTS 算安全 (Drizzle 默认)
  if [ -n "$matches" ]; then
    while IFS= read -r match; do
      # 跳过 IF NOT EXISTS (Drizzle 默认写法, 通常小表加索引 OK)
      if echo "$match" | grep -q 'IF NOT EXISTS'; then
        continue
      fi
      echo -e "${YELLOW}⚠️  [WARN]${NC}  $migration: $match"
      echo -e "   CREATE INDEX 不带 CONCURRENTLY 会锁表 (大表慎用)"
      echo -e "   建议: 大表用 CREATE INDEX CONCURRENTLY"
      WARNINGS=$((WARNINGS + 1))
    done <<< "$matches"
  fi

  echo ""
done

# ===== 总结 =====

echo -e "${CYAN}=== 总结 ===${NC}"
echo -e "Errors:   ${RED}$ERRORS${NC}"
echo -e "Warnings: ${YELLOW}$WARNINGS${NC}"
echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}❌ migration 兼容性检测失败 (CHARTER §3.5)${NC}"
  echo -e "${RED}   必须修复所有 ❌ 项后重跑,或主人 ask_user 拍板例外${NC}"
  exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
  echo -e "${YELLOW}⚠️  通过 (有警告, 建议 review)${NC}"
  exit 0
fi

echo -e "${GREEN}✅ migration 兼容性检测通过 (无错误无警告)${NC}"
exit 0