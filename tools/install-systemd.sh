#!/usr/bin/env bash
# ============================================================
# 暖客宝 systemd user service 安装脚本 (免 sudo)
#
# 装什么:
#   ~/.config/systemd/user/nuankebao-nextjs.service
#   ~/.config/systemd/user/nuankebao-nextjs.service.d/override.conf
#
# 效果:
#   - 当前 shell: systemctl --user start nuankebao-nextjs (立即起)
#   - 开机:       systemctl --user enable nuankebao-nextjs (自动起)
#   - crash:      RestartSec=30 自动拉, 10 分钟内最多 5 次
#
# 适用: 重装系统 / 新机器部署 暖客宝
#
# ADR: docs/adr/0003-flutter-dev-workflow.md (Next.js dev 守护)
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVC_DIR="$HOME/.config/systemd/user"
SRC_DIR="$ROOT/tools/systemd"

echo "==> 复制 service 文件 (sed 渲染占位符 → ROOT)"
mkdir -p "$SVC_DIR/nuankebao-nextjs.service.d"
# nuankebao-nextjs.service 用 __PROJECT_DIR__ 占位符, sed 渲染到 ROOT
sed "s|__PROJECT_DIR__|$ROOT|g" "$SRC_DIR/nuankebao-nextjs.service" \
    > "$SVC_DIR/nuankebao-nextjs.service"
cp "$SRC_DIR/override.conf" "$SVC_DIR/nuankebao-nextjs.service.d/override.conf"

echo "==> reload systemd"
systemctl --user daemon-reload

echo "==> enable + start"
systemctl --user enable nuankebao-nextjs.service
systemctl --user restart nuankebao-nextjs.service

echo "==> 验证"
sleep 5
for i in 5 10 15 20; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 http://127.0.0.1:3003/api/health 2>/dev/null || echo "000")
  echo "[${i}s] HTTP $code"
  [ "$code" = "200" ] && break
  sleep 5
done

echo ""
echo "✅ 装完"
echo "  状态:   systemctl --user status nuankebao-nextjs"
echo "  重启:   systemctl --user restart nuankebao-nextjs"
echo "  日志:   journalctl --user -u nuankebao-nextjs -f"
echo "  完整态: $ROOT/tools/tunnel-status.sh"
