#!/usr/bin/env bash
# ============================================
# 护栏: auto-task-snapshot 扩展不能含 `agent_end` 或 `git add -A`
# ============================================
#
# 背景 (AGENTS §8.1.3, 2026-09-23 主人拍板):
#   旧版插件在 agent_end 触发 `git add -A` + commit(`wip(snapshot): <最后一句话>`),
#   会把同一工作目录其他 session 的在制品扫进来 → commit 标题与内容完全无关的
#   「考古灾难」commit. 主人拍板去掉, 只留 turn_start (打 git tag + diff dump).
#
# 后续可能有人改 PR (e.g. 加新 hook) —— 本脚本断言插件源码**不含**:
#   - 注册 `agent_end` 事件
#   - 在任何地方执行 `git add -A` (本仓已明确禁用: 见 scripts/task-snapshot.sh
#     注释 + AGENTS §5 "并发 session 不许 git add -A")
#
# 排除:
#   - 注释 (//, /* */, #) 里的字面提及 —— 这是文档, 不是行为
#   - 字符串字面量 ('...') 里的提及 —— 这是文档引用, 不是行为
#
# 用法:
#   bash tools/check-auto-snapshot-extension.sh
#   exit 0 = 合规; exit 1 = 含禁止模式 (CI / pre-commit)
#
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

EXT=".pi/extensions/auto-task-snapshot.ts"
[[ -f "$EXT" ]] || { echo "✗ 找不到 $EXT"; exit 1; }

FAILED=0

# ---- 1. 不应有 pi.on("agent_end", ...) ----
# 注释里说明「已去掉」是允许的, 但实际注册必须有 guard
N_AGENT_END=$(grep -E '^\s*pi\.on\(\s*["\x27]agent_end' "$EXT" | wc -l | tr -d ' ')
if [[ "$N_AGENT_END" -gt 0 ]]; then
  echo "✗ $EXT 含禁止的 agent_end hook 注册"
  grep -nE '^\s*pi\.on\(\s*["\x27]agent_end' "$EXT" | sed 's/^/    /'
  FAILED=1
fi

# ---- 2. 不应有 `git add -A` 调用 ----
#   ⚠ 必须排除: (a) 注释 (// / /* */ / * 开头)  (b) 字符串字面 (' / " 内部)
#   简单实现:
#     1) 把 /* ... */ 多行块注释整段去掉 (用 awk 跟踪块注释边界)
#     2) 行尾 // 注释去掉
#     3) 行首带 * 的 (/* ... */ 内部) 整行去掉
#     4) 再 grep `git add -A`
TMP=$(mktemp)
awk '
  BEGIN { in_block=0 }
  {
    line = $0
    # 处理 /* ... */ 多行块注释
    if (in_block) {
      if (line ~ /\*\//) { sub(/.*\*\//, "", line); in_block=0 }
      else { next }
    } else {
      while (match(line, /\/\*[^*]*\*+([^/*][^*]*\*+)*\//)) {
        line = substr(line, 1, RSTART-1) substr(line, RSTART+RLENGTH)
      }
      if (line ~ /\/\*/) { sub(/\/\*.*$/, "", line); in_block=1 }
    }
    # 行尾 // 注释
    sub(/[ \t]*\/\/.*$/, "", line)
    # 行首带 * (jsdoc 内部)
    sub(/^[ \t]*\*.*$/, "", line)
    if (line ~ /[^ \t]/) print NR "\t" line
  }
' "$EXT" > "$TMP"
N_GIT_ADD_A=$(grep -cE '\bgit[[:space:]]+add[[:space:]]+-A\b' "$TMP" || true)
rm -f "$TMP"
if [[ "$N_GIT_ADD_A" -gt 0 ]]; then
  echo "✗ $EXT 含禁止的 \`git add -A\` 调用 (本仓已禁用: AGENTS §5)"
  awk '
    BEGIN { in_block=0 }
    {
      line = $0
      if (in_block) {
        if (line ~ /\*\//) { sub(/.*\*\//, "", line); in_block=0 }
        else { next }
      } else {
        while (match(line, /\/\*[^*]*\*+([^/*][^*]*\*+)*\//)) {
          line = substr(line, 1, RSTART-1) substr(line, RSTART+RLENGTH)
        }
        if (line ~ /\/\*/) { sub(/\/\*.*$/, "", line); in_block=1 }
      }
      sub(/[ \t]*\/\/.*$/, "", line)
      sub(/^[ \t]*\*.*$/, "", line)
      if (line ~ /git[ \t]+add[ \t]+-A/) print NR ": " line
    }
  ' "$EXT"
  FAILED=1
fi

# ---- 3. 仅注册了 turn_start 一个 hook ----
N_TURN_START=$(grep -E '^\s*pi\.on\(\s*["\x27]turn_start' "$EXT" | wc -l | tr -d ' ')
N_ALL_HOOKS=$(grep -cE '^\s*pi\.on\(' "$EXT" || true)
echo "✗ $(basename $EXT) 注册 hook = ${N_ALL_HOOKS} 个 (turn_start = ${N_TURN_START})"

if [[ "$N_TURN_START" -ne 1 ]]; then
  echo "✗ 期望恰好 1 个 turn_start hook, 实际 ${N_TURN_START}"
  FAILED=1
fi

if [[ "$FAILED" -ne 0 ]]; then
  echo ""
  echo "✗ 护栏被触发 —— auto-task-snapshot 扩展不能再现 \"wip(snapshot): ...\" 类 commit"
  echo "  详见 AGENTS §8.1.3 (2026-09-23 主人拍板: 去掉 agent_end 自动 commit)"
  exit 1
fi

echo "✓ auto-task-snapshot 扩展合规: 仅 turn_start (git tag + diff dump), 无 agent_end / git add -A"
exit 0