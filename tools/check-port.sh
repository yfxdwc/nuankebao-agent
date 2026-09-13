#!/usr/bin/env bash
# ============================================================
# 暖客宝 端口检测脚本
# 用法: ./tools/check-port.sh [端口...]
#       ./tools/check-port.sh          # 检测常用端口
# 返回: 占用 → 红色 ✗, 空闲 → 绿色 ✓
# ============================================================
set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 默认检测的常用端口
DEFAULT_PORTS=(3000 3001 3002 3003 3010 3030 4000 5000 5173 5557 7000 8000 8080 8081 8443 8667 9000 9090)

# 检测单个端口是否空闲
is_port_free() {
  local port="$1"
  if ss -tln 2>/dev/null | grep -qE "[:.]${port}[[:space:]]"; then
    return 1  # 占用
  fi
  if lsof -i :${port} -sTCP:LISTEN 2>/dev/null | grep -q LISTEN; then
    return 1  # 占用
  fi
  return 0  # 空闲
}

check_port() {
  local port="$1"
  if is_port_free "$port"; then
    printf "${GREEN}✓${NC} 端口 ${CYAN}%-5s${NC} ${GREEN}空闲${NC}\n" "$port"
    return 0
  else
    # 找出占用进程
    local proc=$(ss -tlnp 2>/dev/null | grep -E "[:.]${port}[[:space:]]" | head -1 | grep -oE 'pid=[0-9]+' | head -1 | cut -d= -f2)
    if [ -n "$proc" ]; then
      local cmd=$(ps -p "$proc" -o comm= 2>/dev/null || echo "?")
      printf "${RED}✗${NC} 端口 ${CYAN}%-5s${NC} ${RED}占用${NC} (pid=$proc, $cmd)\n" "$port"
    else
      printf "${RED}✗${NC} 端口 ${CYAN}%-5s${NC} ${RED}占用${NC}\n" "$port"
    fi
    return 1
  fi
}

# 找第一个空闲端口 (在 start-end 范围)
find_free_port() {
  local start="${1:-3000}"
  local end="${2:-9000}"
  for ((port=start; port<=end; port++)); do
    if is_port_free "$port"; then
      echo "$port"
      return 0
    fi
  done
  return 1
}

main() {
  echo "=========================================="
  echo " 暖客宝 端口检测"
  echo " 时间: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "=========================================="
  echo

  local busy=0  # 累计占用端口数, 用于退出码

  # 特殊命令
  if [ "${1:-}" = "--find" ]; then
    local start="${2:-3000}"
    local end="${3:-9000}"
    echo "在 $start-$end 范围找第一个空闲端口..."
    local free=$(find_free_port "$start" "$end")
    if [ -n "$free" ]; then
      printf "${GREEN}✓ 找到空闲端口: $free${NC}\n"
      return 0
    else
      printf "${RED}✗ 范围内无空闲端口${NC}\n"
      return 1
    fi
  fi

  # 检测指定端口或默认端口
  if [ $# -eq 0 ]; then
    echo "[常用端口检测]"
    for port in "${DEFAULT_PORTS[@]}"; do
      check_port "$port" || busy=$((busy + 1))
    done
    echo
    echo "用法:"
    echo "  ./tools/check-port.sh 3000 3001 5000   # 检测指定端口"
    echo "  ./tools/check-port.sh --find 3000 9000 # 找空闲端口"
    echo
    echo "退出码: 0=全空闲, 1=有占用 (脚本可被 CI / hook 安全依赖)"
    [ $busy -eq 0 ] && return 0 || return 1
  else
    for port in "$@"; do
      check_port "$port" || busy=$((busy + 1))
    done
    [ $busy -eq 0 ] && return 0 || return 1
  fi
}

main "$@"