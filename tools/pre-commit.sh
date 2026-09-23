#!/usr/bin/env bash
# ============================================
# 暖客宝 pre-commit wrapper (链式调用 guards)
# ============================================
# 链式调用所有 pre-commit 检查; 任一失败 → 阻断提交
#
# 当前挂载:
#   1. preview-guard: 锁住 AGENTS §9 9 个预览框架路径
#   2. tokens-guard:   硬编码字面值棘轮 (P2-P5 成果防回退)
#
# 安装 (一次性):
#   ln -sf ../../tools/pre-commit.sh .git/hooks/pre-commit
# ============================================

# 兼容 symlink 调用 (git hook 走 .git/hooks/pre-commit → 真实位置 tools/pre-commit.sh)
SCRIPT=$(realpath "${BASH_SOURCE[0]:-$0}")
cd "$(dirname "$SCRIPT")/.." || exit 1

# 1) 预览框架冻结
echo "▸ preview-guard..."
if ! bash tools/pre-commit-preview-guard.sh; then
  exit 1
fi

# 2) 硬编码护栏 (阻回归)
echo "▸ tokens-guard..."
if ! bash tools/check-ui-tokens.sh --strict; then
  exit 1
fi

echo "✓ pre-commit OK"
