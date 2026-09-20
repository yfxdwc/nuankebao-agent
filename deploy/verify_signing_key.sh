#!/usr/bin/env bash
# ============================================================
# 暖客宝 APK 签名密钥 月度演练 (主人 2026-09-21 问「keystore 丢了怎么办」)
#
# 为什么需要:
#   keystore 丢了 = 以后所有 APK 签名都变 = **全体用户必须卸载重装** (掉登录态;
#   业务数据在服务器, 不会丢, 但体验很难看)。而且 Android 的密钥轮换 (v3 proof-of-rotation)
#   需要**用旧私钥签轮换 lineage** → 对"已经丢了"无能为力。所以唯一治本 = 保证它不丢,
#   且**定期验证备份真的能用**(备份没验过 = 等于没有)。
#
# 演练内容 (只读 + 临时目录, 不动生产材料):
#   1. 工作副本 keystore + key.properties 口令 → keytool 能打开
#   2. 最近一份**加密备份** → 解密 → 与工作副本 sha256 一致
#   3. **真签一次**: 用解密出来的 keystore 给现有 APK 重签 → apksigner verify →
#      指纹与预期一致 (证明"这份备份真能用来发版", 而不只是"文件还在")
#
# 用法:
#   bash deploy/verify_signing_key.sh              # 全演练
#   bash deploy/verify_signing_key.sh --quick      # 跳过第 3 步 (不真签, 快)
#
# 退出码:
#   0 演练通过   1 参数/环境错   2 工作副本打不开   3 找不到加密备份
#   4 解密/校验失败   5 真签失败/指纹不一致
#
# 调度建议: 跟着 PG 月度演练 (nuankebao-restore-verify.timer) 一起跑, 见 deploy/README.md §10
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DATABACKUPS="${DATABACKUPS:-/home/tooyan/nuankebao-databackups}"
KEYS_ARCHIVE="${KEYS_ARCHIVE:-$DATABACKUPS/keys/signing-keys.tar.zst.enc}"
KEY_FILE="${KEY_FILE:-/etc/backup-keys/nuankebao.key.gpg}"
WORK_JKS="${WORK_JKS:-/home/tooyan/nuankebao-keys/nuankebao-release.jks}"
KEY_PROPS="${KEY_PROPS:-$PROJECT_ROOT/flutter_app/android/key.properties}"
APK="${APK:-$PROJECT_ROOT/flutter_app/build/app/outputs/flutter-apk/app-release.apk}"
EXPECTED_SHA256="${EXPECTED_SHA256:-0DB0A1BCFF6DA703B9FE3A3C05033CCF2D67E4F0B04D69164319C16B621900B6}"

export JAVA_HOME="${JAVA_HOME:-/home/tooyan/jdk}"
export PATH="$JAVA_HOME/bin:$PATH"
APKSIGNER="${APKSIGNER:-$(ls /home/tooyan/android-sdk/build-tools/*/apksigner 2>/dev/null | tail -1)}"

QUICK=0
[ "${1:-}" = "--quick" ] && QUICK=1

say() { echo "[signing-key] $*"; }
fail() { echo "[signing-key] ✗ $*" >&2; exit "${2:-1}"; }

# ---------- 0. 预检 ----------
[ -f "$WORK_JKS" ] || fail "工作副本 keystore 不存在: $WORK_JKS" 1
[ -f "$KEY_PROPS" ] || fail "key.properties 不存在: $KEY_PROPS" 1
command -v keytool >/dev/null || fail "keytool 不在 PATH (设 JAVA_HOME)" 1

STORE_PASS="$(grep -oP '(?<=storePassword=).*' "$KEY_PROPS")"
KEY_PASS="$(grep -oP '(?<=keyPassword=).*' "$KEY_PROPS")"
[ -n "$STORE_PASS" ] || fail "key.properties 里没有 storePassword" 1

# ---------- 1. 工作副本能用吗 ----------
say "1/3 工作副本: $WORK_JKS"
if ! keytool -list -keystore "$WORK_JKS" -storepass "$STORE_PASS" >/dev/null 2>&1; then
    fail "工作副本打不开 (口令不对? 文件损坏?)" 2
fi
WORK_SHA=$(sha256sum "$WORK_JKS" | awk '{print $1}')
say "    ✓ 可打开, sha256=${WORK_SHA:0:16}…"

# ---------- 2. 加密备份能解出来并且一致吗 ----------
say "2/3 加密备份: $KEYS_ARCHIVE"
[ -f "$KEYS_ARCHIVE" ] || fail "找不到签名密钥加密备份 (先跑备份: deploy/backup.sh)" 3
STAGE="$(mktemp -d /tmp/nuankebao-signkey-XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

if ! gpg --batch --yes --pinentry-mode loopback --passphrase-file "$KEY_FILE" \
        --decrypt --output "$STAGE/signing-keys.tar.zst" "$KEYS_ARCHIVE" 2>/dev/null; then
    fail "GPG 解密失败 (KEY_FILE=$KEY_FILE)" 4
fi
tar --zstd -xf "$STAGE/signing-keys.tar.zst" -C "$STAGE" || fail "解包失败" 4

BACKUP_JKS="$(find "$STAGE" -name '*.jks' | head -1)"
[ -n "$BACKUP_JKS" ] || fail "备份包里没有 .jks" 4
BACKUP_SHA=$(sha256sum "$BACKUP_JKS" | awk '{print $1}')
[ "$BACKUP_SHA" = "$WORK_SHA" ] || fail "备份副本与工作副本不一致 ($BACKUP_SHA != $WORK_SHA)" 4
say "    ✓ 解密成功且与工作副本一致 (sha256=${BACKUP_SHA:0:16}…)"

BACKUP_PASS="$(grep -oP '(?<=storePassword=).*' "$(find "$STAGE" -name 'key.properties' | head -1)" 2>/dev/null || echo "")"
if [ -n "$BACKUP_PASS" ] && [ "$BACKUP_PASS" != "$STORE_PASS" ]; then
    fail "备份里的口令与当前 key.properties 不一致" 4
fi
say "    ✓ 口令一致"

# ---------- 3. 真签一次 (证明备份能用来发版) ----------
if [ "$QUICK" = "1" ]; then
    say "3/3 跳过真签 (--quick)"
    say "✅ 演练通过 (quick)"
    exit 0
fi
[ -n "$APKSIGNER" ] || fail "找不到 apksigner (设 APKSIGNER 或装 Android SDK build-tools)" 1
[ -f "$APK" ] || fail "找不到用于重签的 APK: $APK" 1

say "3/3 用**备份 keystore** 重签一次并验指纹"
OUT="$STAGE/resigned.apk"
cp "$APK" "$OUT"
if ! "$APKSIGNER" sign --ks "$BACKUP_JKS" --ks-pass "pass:$BACKUP_PASS" \
        --key-pass "pass:$KEY_PASS" "$OUT" >/dev/null 2>&1; then
    fail "用备份 keystore 签名失败" 5
fi
GOT_SHA=$("$APKSIGNER" verify --print-certs "$OUT" 2>/dev/null \
    | grep -iE "SHA-256 digest" | head -1 | awk '{print $NF}' | tr -d ':' | tr 'a-f' 'A-F')
[ -n "$GOT_SHA" ] || fail "apksigner verify 没打印 SHA-256" 5
if [ "$GOT_SHA" != "$EXPECTED_SHA256" ]; then
    fail "重签后的指纹与预期不符 (got ${GOT_SHA:0:16}…, want ${EXPECTED_SHA256:0:16}…)" 5
fi
say "    ✓ 重签成功, 指纹 = ${GOT_SHA:0:16}… (与线上一致)"
say "✅ 演练通过: 备份里的 keystore + 口令**真能用来发版**"
