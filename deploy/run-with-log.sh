#!/usr/bin/env bash
# ============================================
# systemd 日志包装器 (2026-09-19 P3)
#
# 用法:
#   run-with-log.sh <logfile> <command> [args...]
#
# 为什么需要:
#   systemd 的 StandardOutput=append:<path> 要求父目录 **在 unit 启动前** 已存在,
#   否则 unit 直接 209/STDOUT 起不来 —— 且 ExecStartPre 也救不了 (systemd 先配 stdout,
#   再跑 ExecStartPre)。dev 备份因此 2026-09-17 ~ 09-19 连挂 3 天, 根因就是
#   /home/tooyan/nuankebao-databackups 被删。
#   本包装器先 mkdir, 再把命令输出同时送 journal (stdout) + 文件; systemd unit 不再写
#   StandardOutput=append, 从根本上消除这个启动依赖。
#
# 退出码 = 命令的退出码 (tee 的退出码忽略)。
# ============================================
set -uo pipefail

if [ $# -lt 2 ]; then
    echo "用法: $0 <logfile> <command> [args...]" >&2
    exit 64
fi

LOG="$1"
shift

mkdir -p "$(dirname "$LOG")"
"$@" 2>&1 | tee -a "$LOG"
exit "${PIPESTATUS[0]}"
