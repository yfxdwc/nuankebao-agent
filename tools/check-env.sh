#!/usr/bin/env bash
# ============================================================
# 暖客宝 工具链自检脚本
# 用法: ./tools/check-env.sh
# 返回: 0 = 全齐, 1 = 有缺失
# ============================================================
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0
MISSING=()

check() {
  local name="$1"
  local cmd="$2"
  local min_ver="${3:-}"
  local installed
  installed="$(eval "$cmd" 2>&1 | head -1)"
  if [ -n "$installed" ]; then
    printf "${GREEN}✓${NC} %-20s %s\n" "$name" "$installed"
    PASS=$((PASS+1))
  else
    printf "${RED}✗${NC} %-20s ${RED}MISSING${NC}\n" "$name"
    FAIL=$((FAIL+1))
    MISSING+=("$name")
  fi
}

echo "========================================"
echo " 暖客宝 工具链自检"
echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 用户: $(whoami) @ $(hostname)"
echo "========================================"
echo

echo "[核心 — 必须]"
check "pi"          "pi --version 2>&1 | head -1"
check "node"        "node --version"
check "npm"         "npm --version"
check "pnpm"        "pnpm --version 2>&1 | head -1"
check "python3"     "python3 --version"
check "git"         "git --version"

echo
echo "[Python 工具链]"
check "uv"          "uv --version 2>&1 | head -1"
check "pip3"        "pip3 --version 2>&1 | head -1"

echo
echo "[Shell 增强 — 强烈推荐]"
check "rg (ripgrep)"  "rg --version 2>&1 | head -1"
check "fd"            "fd --version"
check "fzf"           "fzf --version 2>&1"
check "bat"           "bat --version 2>&1 | head -1"
check "eza"           "eza --version 2>&1 | head -1"
check "lazygit"       "lazygit --version 2>&1 | head -1"
check "tmux"          "tmux -V"
check "jq"            "jq --version"

echo
echo "[网络 / 系统]"
check "curl"         "curl --version 2>&1 | head -1"
check "wget"         "wget --version 2>&1 | head -1"
check "git"          "git --version"
check "build-essent" "dpkg -l build-essential 2>&1 | tail -1"
check "unzip"        "unzip -v 2>&1 | head -1"

echo
echo "[可选 — 按需安装]"
check "docker"       "docker --version 2>&1"
check "yarn"         "yarn --version 2>&1 | head -1 || echo '跳过'"
check "sqlite3"      "sqlite3 --version 2>&1 | head -1 || echo '跳过'"

echo
echo "========================================"
printf "结果: ${GREEN}%d 通过${NC} / ${RED}%d 缺失${NC}\n" "$PASS" "$FAIL"

if [ $FAIL -gt 0 ]; then
  printf "${YELLOW}缺失:${NC} %s\n" "${MISSING[*]}"
  exit 1
fi
echo -e "${GREEN}✅ 所有工具齐备,可以开始 vibe coding!${NC}"
