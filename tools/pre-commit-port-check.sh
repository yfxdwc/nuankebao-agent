#!/usr/bin/env bash
# ============================================================
# 暖客宝 pre-commit 端口硬约束
# 任何 commit 之前, 如果 diff 里改了端口号, 强制 check-port.sh
#
# 安装方法 (主人手动):
#   ln -s ../../tools/pre-commit-port-check.sh .git/hooks/pre-commit
#   chmod +x .git/hooks/pre-commit
#
# 设计原则: 不阻塞不相关 commit, 只在有端口变更时强制检测
# ============================================================
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 1. 检测 diff 里的端口号
CHANGED_PORTS=$(git diff --cached -U0 2>/dev/null | \
  grep -E '^\+[^+]' | \
  grep -oE '\b(30[0-9]{2}|3[1-9][0-9]{2}|4[0-9]{3}|5[0-9]{3}|6[0-9]{3}|7[0-9]{3}|8[0-9]{3}|9[0-9]{3})\b' | \
  sort -n | uniq)

if [ -z "$CHANGED_PORTS" ]; then
  exit 0  # 没改端口,放行
fi

echo "=========================================="
echo " 暖客宝 pre-commit 端口硬约束"
echo "=========================================="
echo ""
echo -e "${YELLOW}检测到 diff 里改了端口:${NC}"
echo "$CHANGED_PORTS" | sed 's/^/  /'
echo ""

# 2. 对每个端口跑 check-port.sh
HAS_CONFLICT=0
TOOLS_DIR="$(git rev-parse --show-toplevel)/tools"
CHECK_PORT="$TOOLS_DIR/check-port.sh"

if [ ! -x "$CHECK_PORT" ]; then
  echo -e "${RED}✗ 找不到 $CHECK_PORT${NC}"
  exit 1
fi

for PORT in $CHANGED_PORTS; do
  echo "--- 检查 $PORT ---"
  if "$CHECK_PORT" "$PORT" | grep -q "空闲"; then
    echo -e "${GREEN}✓ $PORT 空闲${NC}"
  else
    echo -e "${RED}✗ $PORT 已占用! 请修改端口再 commit${NC}"
    HAS_CONFLICT=1
  fi
  echo ""
done

if [ "$HAS_CONFLICT" -eq 1 ]; then
  echo -e "${RED}=========================================${NC}"
  echo -e "${RED} commit 被阻断: 端口冲突${NC}"
  echo -e "${RED}=========================================${NC}"
  echo ""
  echo "解决方法:"
  echo "  1. 改用上面推荐的空闲端口"
  echo "  2. 编辑相关文件 (docker-compose.yml / .env.example / package.json)"
  echo "  3. 重新 git add + git commit"
  exit 1
fi

echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN} 端口检查通过 ✓${NC}"
echo -e "${GREEN}=========================================${NC}"
exit 0