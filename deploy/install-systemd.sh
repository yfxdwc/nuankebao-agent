#!/usr/bin/env bash
# ============================================================
# 暖客宝 备份 systemd user services 安装脚本 (免 sudo)
#
# 装什么 (6 个 unit, 3 对 service+timer):
#   ~/.config/systemd/user/nuankebao-backup.service           + .timer (每日 03:00)
#   ~/.config/systemd/user/nuankebao-code-snapshot.service    + .timer (每日 04:00)
#   ~/.config/systemd/user/nuankebao-restore-verify.service   + .timer (每月第一周日 04:00)
#
# 路径变量化 (AGENTS §6.3 + deploy/paths.conf):
#   - 读 deploy/paths.conf (项目内 source-of-truth, 主人当前机器真值)
#   - cp 到 ~/.config/nuankebao/paths.conf (systemd EnvironmentFile= 实际读的)
#   - sed 渲染 3 个 service 的 __PROJECT_DIR__ / __DATABACKUPS_DIR__ / __OFFSITE_DIR__ / __USER_LOCAL_BIN__ 占位符
#
# 效果:
#   - 当前 shell: systemctl --user enable --now (立刻拉起 + 开机自启)
#   - 开机: 跟 nuankebao-nextjs.service 一起 auto-start (登出 systemd user 持久)
#   - 依赖: nuankebao-stack.service 必须起 (PG container 在跑)
#
# 适用: 重装系统 / 新机器部署 / 主人升级 SOP 后重新装 / 迁移到新机器
#
# 注意: GitHub 镜像 + monitor 不装 (主人 2026-09-08 ask_user 拍板 skip-github-mirror)
#
# ADR: deploy/README.md §10 (备份 SOP) + §11 (路径变量化)
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT/deploy/systemd"
USER_SVC_DIR="$HOME/.config/systemd/user"
RUNTIME_CONF_DIR="$HOME/.config/nuankebao"
RUNTIME_CONF="$RUNTIME_CONF_DIR/paths.conf"

# ============== 1. 加载路径配置 ==============

if [ ! -f "$ROOT/deploy/paths.conf" ]; then
    echo "❌ 缺 deploy/paths.conf"
    echo "   修复: cp deploy/paths.conf.example deploy/paths.conf 然后改值"
    exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ROOT/deploy/paths.conf"
set +a

# 兜底 (paths.conf 没填某项时, 用合理默认)
PROJECT_DIR="${NUANKEBAO_PROJECT_DIR:-$ROOT}"
DATABACKUPS_DIR="${NUANKEBAO_DATABACKUPS_DIR:-$HOME/nuankebao-databackups}"
OFFSITE_DIR="${NUANKEBAO_OFFSITE_DIR:-}"
USER_LOCAL_BIN="${NUANKEBAO_USER_LOCAL_BIN:-$HOME/.local/bin}"

# 校验
[ -d "$PROJECT_DIR" ] || { echo "❌ NUANKEBAO_PROJECT_DIR 不存在: $PROJECT_DIR"; exit 1; }
[ -d "$DATABACKUPS_DIR" ] || { echo "❌ NUANKEBAO_DATABACKUPS_DIR 不存在: $DATABACKUPS_DIR"; exit 1; }
if [ -n "$OFFSITE_DIR" ] && [ ! -d "$OFFSITE_DIR" ]; then
    echo "❌ NUANKEBAO_OFFSITE_DIR 不存在: $OFFSITE_DIR (留空跳过异地)"
    exit 1
fi

# ============== 2. cp paths.conf 到运行时位置 (systemd 读这里) ==============

echo "==> 同步 paths.conf → systemd EnvironmentFile 路径"
mkdir -p "$RUNTIME_CONF_DIR"
if [ ! -f "$RUNTIME_CONF" ]; then
    cp "$ROOT/deploy/paths.conf" "$RUNTIME_CONF"
    echo "  ✓ 首次装: $RUNTIME_CONF 已生成"
    echo "    (systemd EnvironmentFile= 指向这里, 改值后跑 install-systemd.sh 重新同步)"
else
    # 已存在 → 不覆盖 (主人可能手动改过), 只提示
    echo "  → 已存在 (保持主人本地自定义): $RUNTIME_CONF"
fi

# ============== 3. sed 渲染 3 个 service (占位符 → paths.conf 真值) ==============

# 处理 OFFSITE_DIR 空值 (dev 模式): 删 RequiresMountsFor=__OFFSITE_DIR__ 整行,
# 把 __OFFSITE_DIR__/nuankebao-codebackups 重定向到 DATABACKUPS_DIR/nuankebao-codebackups
if [ -z "$OFFSITE_DIR" ]; then
    EFFECTIVE_OFFSITE_DIR="$DATABACKUPS_DIR"
    OFFSITE_RSYNC_DIR="$DATABACKUPS_DIR/nuankebao-codebackups"
    # 占位符哨兵: 用一个独特字符串后面 awk 删整行
    REQUIRES_MOUNT_SENTINEL="__REQUIRES_MOUNT_SKIP__"
else
    EFFECTIVE_OFFSITE_DIR="$OFFSITE_DIR"
    OFFSITE_RSYNC_DIR="$OFFSITE_DIR/nuankebao-codebackups"
    REQUIRES_MOUNT_SENTINEL="$OFFSITE_DIR"
fi

mkdir -p "$USER_SVC_DIR"

for svc in nuankebao-backup.service nuankebao-code-snapshot.service nuankebao-restore-verify.service; do
    # 用 awk 处理 OFFSITE_DIR 空时删整行 + 路径占位符替换
    awk -v project="$PROJECT_DIR" \
        -v databackups="$DATABACKUPS_DIR" \
        -v userlocalbin="$USER_LOCAL_BIN" \
        -v offsite="$EFFECTIVE_OFFSITE_DIR" \
        -v snapshot_dir="$OFFSITE_RSYNC_DIR" \
        -v sentinel="$REQUIRES_MOUNT_SENTINEL" '
    {
        # OFFSITE_DIR 空时: 删掉 RequiresMountsFor=__OFFSITE_DIR__ 整行
        if ($0 ~ "^RequiresMountsFor=__OFFSITE_DIR__$") { next }

        # OFFSITE_DIR 非空时: 替换 RequiresMountsFor=__OFFSITE_DIR__ 为实际路径
        gsub(/__OFFSITE_DIR__/, offsite)
        gsub(/__PROJECT_DIR__/, project)
        gsub(/__DATABACKUPS_DIR__/, databackups)
        gsub(/__USER_LOCAL_BIN__/, userlocalbin)
        print
    }' "$SRC_DIR/$svc" > "$USER_SVC_DIR/$svc"
done

echo "==> 复制 3 个 timer (timer 无路径占位符, 直接 cp)"
for tmr in nuankebao-backup.timer nuankebao-code-snapshot.timer nuankebao-restore-verify.timer; do
    cp "$SRC_DIR/$tmr" "$USER_SVC_DIR/"
done

# ============== 4. reload + enable ==============

echo "==> reload systemd"
systemctl --user daemon-reload

echo "==> enable + start"
systemctl --user enable --now nuankebao-backup.timer
systemctl --user enable --now nuankebao-code-snapshot.timer
# restore-verify timer 也 enable, 但不 --now (月度触发, 立刻跑没意义)
systemctl --user enable nuankebao-restore-verify.timer

# ============== 5. 验证 ==============

echo ""
echo "==> 验证: list-timers"
systemctl --user list-timers nuankebao-* 2>&1 || true

echo ""
echo "==> 验证: linger (登出 systemd user 持久化)"
if ! loginctl show-user "$(whoami)" 2>/dev/null | grep -q "Linger=yes"; then
    echo "  ⚠️  linger 未开, 登出后 timer 不跑"
    echo "  修复: sudo loginctl enable-linger $(whoami)"
    echo "  (本脚本不自动 sudo, 主人拍板)"
else
    echo "  ✓ linger=yes (systemd user 持久化已开)"
fi

echo ""
echo "==> 当前生效路径 (从 $RUNTIME_CONF)"
echo "    PROJECT_DIR       = $PROJECT_DIR"
echo "    DATABACKUPS_DIR   = $DATABACKUPS_DIR"
if [ -n "$OFFSITE_DIR" ]; then
    echo "    OFFSITE_DIR       = $OFFSITE_DIR (异地模式)"
else
    echo "    OFFSITE_DIR       = (空, dev 模式, 本地 staging)"
fi
echo "    USER_LOCAL_BIN    = $USER_LOCAL_BIN"
echo "    systemd conf      = $RUNTIME_CONF"

echo ""
echo "==> 第一次手动 smoke test (备份)"
echo "  建议: systemctl --user start nuankebao-backup.service (立刻跑一次, 看 logs)"
echo "  日志:  tail -f $DATABACKUPS_DIR/logs/backup.log"

echo ""
echo "✅ 装完"
echo "  状态:   systemctl --user status nuankebao-backup.service"
echo "  重跑:   systemctl --user start nuankebao-backup.service"
echo "  日志:   journalctl --user -u nuankebao-backup -f"
echo "  迁移:   改 $RUNTIME_CONF 后重跑本脚本 (无需 systemd daemon-reload 重启 unit)"