#!/usr/bin/env bash
# ============================================================
# 暖客宝 PG 月度恢复演练 (decrypt → temp PG → row count 比对)
#
# 设计 (dev-domain-backup SOP §3.4):
#   1. 找最近一份 PG 加密备份 (按 mtime 排序)
#   2. 解密 → /tmp/pg-verify/
#   3. 起临时 PG 容器 nuankebao-pg-verify:5435 (与生产端口 5432 隔离)
#   4. pg_restore 到临时容器
#   5. 关键表行数比对 (vs 生产 PG 同表行数)
#   6. 自动清理临时容器 + staging
#   7. 失败 → 写 restore-verify.log + alert
#
# 调度: systemd timer nuankebao-restore-verify.timer 每月第一周日 04:00
#       (OnCalendar=Sun *-*-1..7 04:00:00 + RandomizedDelaySec=10min)
#
# 退出码:
#   0  演练成功 (关键表行数 100% 一致)
#   1  参数/路径错误
#   2  无可用备份 / 密钥缺失
#   3  临时 PG 起不来
#   4  pg_restore 失败
#   5  行数比对失败 (任意关键表 0% 一致)
#
# 日志: data/logs/restore-verify.log
#
# 见 deploy/README.md §10.5.
# ============================================================

set -uo pipefail

# ============== 路径配置 (AGENTS §6.3 + deploy/paths.conf) ==============
#
# 三层来源 (优先级从高到低):
#   1. 环境变量 BBT_DIR / DATABACKUPS / ... (手动 export, 老习惯)
#   2. systemd EnvironmentFile= ~/.config/nuankebao/paths.conf (注入 NUANKEBAO_*)
#   3. 本仓库 deploy/paths.conf (手动跑时 source, dev 默认值)

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PROJECT_ROOT="$(cd "$_SCRIPT_DIR/.." && pwd)"
_PATHS_CONF=""
for _cand in \
    "$HOME/.config/nuankebao/paths.conf" \
    "$_PROJECT_ROOT/deploy/paths.conf"; do
    [ -f "$_cand" ] && { _PATHS_CONF="$_cand"; break; }
done
if [ -n "$_PATHS_CONF" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$_PATHS_CONF"
    set +a
fi
unset _SCRIPT_DIR _PROJECT_ROOT _PATHS_CONF _cand

# ============== 配置 ==============
# NUANKEBAO_* → BBT_*/DATABACKUPS 映射
BBT_DIR="${BBT_DIR:-${NUANKEBAO_PROJECT_DIR:-/home/tooyan/nuankebao-agent}}"
# BODR 模式 (2026-09-20): 本地 DATABACKUPS=/tmp staging, rsync 后即被 trap 清
#              验证只能走异地 OFFSITE_DIR (LK /media/mm7/tc_backup/nuankebao[/-prod])
#              systemd service env 显式设 DATABACKUPS=/tmp/<service>-staging + OFFSITE_DIR (从 backup 给出)
DATABACKUPS="${DATABACKUPS:-${NUANKEBAO_DATABACKUPS_DIR:-/tmp/nuankebao-backup-staging}}"
BACKUP_DIR="${BACKUP_DIR:-${OFFSITE_DIR:-/media/mm7/tc_backup/nuankebao}/pg-backups}"
KEY_FILE="${KEY_FILE:-/etc/backup-keys/nuankebao.key.gpg}"
LOG_DIR="${LOG_DIR:-/tmp/nuankebao-backup-staging/logs}"
LOG="${LOG_DIR}/restore-verify.log"
HEALTH_DIR="${HEALTH_DIR:-/home/tooyan/.muse/muse-station/data/backup-health/nuankebao}"
HEALTH_FILE="${HEALTH_DIR}/restore-verify.json"
HEALTH_TMP="${HEALTH_DIR}/.restore-verify.json.tmp"

# 临时容器 (与生产完全隔离, 用同一镜像但不同 container name + 不同端口)
VERIFY_IMAGE="${VERIFY_IMAGE:-pgvector/pgvector:pg16}"
VERIFY_CONTAINER="${VERIFY_CONTAINER:-nuankebao-pg-verify}"
VERIFY_PORT="${VERIFY_PORT:-5435}"   # 端口 5435, 生产用 5432 (隔离)
VERIFY_USER="${VERIFY_USER:-nuankebao}"
VERIFY_PASS="${VERIFY_PASS:-nuankebao_verify_pass}"
VERIFY_DB="${VERIFY_DB:-nuankebao_verify}"

STAGING_DIR="${STAGING_DIR:-/tmp/pg-verify}"

# 生产 PG (用于行数比对)
PROD_CONTAINER="${PROD_CONTAINER:-nuankebao-postgres}"

# 关键表 (按 Drizzle schema 顺序, 含 audit_log dual-write 表)
KEY_TABLES=(
    "customer"
    "wellness_record"
    "wellness_record_body_part"
    "wellness_record_product"
    "follow_up_task"
    "interaction"
    "product"
    "service_item"
    "body_part"
    "store"
    "staff"
    "user"
    "wellness_knowledge"
    "audit_log"
)

LOG_TS() { date '+%Y-%m-%d %H:%M:%S'; }
START_TS=$(date +%s)
RUN_TS_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$LOG_DIR" "$HEALTH_DIR"

log() { echo "$(LOG_TS) $*" | tee -a "$LOG" >&2; }

# ============== 预检 ==============

[ -d "$BACKUP_DIR" ] || { log "[FATAL] 备份目录不存在: $BACKUP_DIR"; exit 1; }
[ -s "$KEY_FILE" ] || { log "[FATAL] 密钥文件缺失: $KEY_FILE"; _write_health "failed" "key_missing"; exit 2; }

# docker 可用?
command -v docker >/dev/null || { log "[FATAL] docker 命令不存在"; exit 3; }

# 生产 PG 在跑? (演练前提是生产 PG 在线, 否则无法比对)
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PROD_CONTAINER}$"; then
    log "[FATAL] 生产 PG container 未运行: $PROD_CONTAINER (无法做行数比对)"
    _write_health "failed" "prod_pg_down"
    exit 3
fi

# 找最近一份 PG 加密备份
LATEST_ENC=$(ls -1t "$BACKUP_DIR"/pg-*.dump.gpg 2>/dev/null | head -1)
if [ -z "$LATEST_ENC" ]; then
    log "[FATAL] 备份目录无 pg-*.dump.gpg: $BACKUP_DIR"
    _write_health "failed" "no_backup_found"
    exit 2
fi

log "[1/5] 找到最近备份: $LATEST_ENC ($(stat -c%s "$LATEST_ENC") bytes)"
log "[1/5] 密钥文件: $KEY_FILE"

# ============== 1) 准备 staging + 清理旧 verify 容器 ==============

mkdir -p "$STAGING_DIR"
chmod 700 "$STAGING_DIR"

# 清理上次可能残留的 verify 容器 (idempotent)
if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${VERIFY_CONTAINER}$"; then
    log "[1/5] 清理残留 verify 容器: $VERIFY_CONTAINER"
    docker rm -f "$VERIFY_CONTAINER" >/dev/null 2>&1 || true
fi

# ============== 2) 解密 ==============

log "[2/5] 解密 -> $STAGING_DIR/verify.dump"
DUMP_FILE="$STAGING_DIR/verify.dump"

if ! gpg --batch --yes --pinentry-mode loopback --passphrase-file "$KEY_FILE" \
        --decrypt --output "$DUMP_FILE" "$LATEST_ENC"; then
    log "[FATAL] GPG 解密失败 (密钥错? 备份损坏?)"
    _write_health "failed" "gpg_decrypt_failed"
    exit 2
fi
chmod 600 "$DUMP_FILE"

# 验证 dump 完整 (pg_restore --list 能跑通 = 格式正确)
if ! docker run --rm -i -v "$STAGING_DIR:/data" "$VERIFY_IMAGE" pg_restore --list /data/verify.dump >/dev/null 2>&1; then
    log "[FATAL] pg_restore --list 失败 (dump 损坏? 非 -Fc 格式?)"
    _write_health "failed" "pg_restore_list_failed"
    exit 4
fi

DUMP_SIZE=$(stat -c%s "$DUMP_FILE")
log "[2/5] OK 解密完成 ($DUMP_SIZE bytes, pg_restore --list 验证通过)"

# ============== 3) 起临时 PG 容器 ==============

log "[3/5] 起临时 PG 容器 $VERIFY_CONTAINER:$VERIFY_PORT"
docker run -d \
    --name "$VERIFY_CONTAINER" \
    -e "POSTGRES_USER=$VERIFY_USER" \
    -e "POSTGRES_PASSWORD=$VERIFY_PASS" \
    -e "POSTGRES_DB=$VERIFY_DB" \
    -p "${VERIFY_PORT}:5432" \
    "$VERIFY_IMAGE" >/dev/null

# 等 PG 就绪 (最多 30s)
for i in $(seq 1 30); do
    if docker exec "$VERIFY_CONTAINER" pg_isready -U "$VERIFY_USER" -d "$VERIFY_DB" >/dev/null 2>&1; then
        log "[3/5] OK PG ready (等 $i 秒)"
        break
    fi
    sleep 1
done

if ! docker exec "$VERIFY_CONTAINER" pg_isready -U "$VERIFY_USER" -d "$VERIFY_DB" >/dev/null 2>&1; then
    log "[FATAL] 临时 PG 30s 内未就绪"
    _write_health "failed" "verify_pg_not_ready"
    docker rm -f "$VERIFY_CONTAINER" >/dev/null 2>&1 || true
    exit 3
fi

# ============== 4) pg_restore ==============

log "[4/5] pg_restore 到临时容器"
# 用 --no-owner + --no-privileges (我们只关心数据完整性, 不管权限)
if ! docker exec -i "$VERIFY_CONTAINER" pg_restore \
        -U "$VERIFY_USER" -d "$VERIFY_DB" \
        --no-owner --no-privileges \
        < "$DUMP_FILE" >/dev/null 2>&1; then
    # pg_restore 在 restore 完成后常常 exit 非 0 (e.g. 扩展不存在等), 但数据可能已经 OK
    # 这里以"关键表能查出行数"为准, 不以 exit code 为准
    log "[4/5] [WARN] pg_restore exit 非 0 (检查关键表行数为准)"
fi
log "[4/5] pg_restore 完成"

# ============== 5) 关键表行数比对 ==============

log "[5/5] 关键表行数比对 (生产 vs 演练)"
MATCH_TOTAL=0
TABLE_TOTAL=${#KEY_TABLES[@]}
ALL_OK=1
COMPARE_LINES=""

for table in "${KEY_TABLES[@]}"; do
    # 演练容器行数 (pg_restore 用 --no-owner, 我们自己 grant 才能 SELECT)
    # 简单做法: 直接 psql (默认 superuser) 即可
    PROD_COUNT=$(docker exec "$PROD_CONTAINER" psql -U "$VERIFY_USER" -d nuankebao -tAc "SELECT COUNT(*) FROM \"$table\"" 2>/dev/null || echo "ERR")
    VERIFY_COUNT=$(docker exec "$VERIFY_CONTAINER" psql -U "$VERIFY_USER" -d "$VERIFY_DB" -tAc "SELECT COUNT(*) FROM \"$table\"" 2>/dev/null || echo "ERR")

    # 一致 = 数值相等 (允许两侧都是 0 即表为空但结构存在)
    if [ "$PROD_COUNT" = "$VERIFY_COUNT" ]; then
        MATCH_TOTAL=$((MATCH_TOTAL + 1))
        COMPARE_LINES="${COMPARE_LINES}  ✓ $table: prod=$PROD_COUNT verify=$VERIFY_COUNT"$'\n'
        log "[5/5]   ✓ $table: prod=$PROD_COUNT verify=$VERIFY_COUNT"
    else
        ALL_OK=0
        COMPARE_LINES="${COMPARE_LINES}  ✗ $table: prod=$PROD_COUNT verify=$VERIFY_COUNT (MISMATCH)"$'\n'
        log "[5/5]   ✗ $table: prod=$PROD_COUNT verify=$VERIFY_COUNT (MISMATCH)"
    fi
done

# ============== 清理 ==============

log "[cleanup] 清理临时容器 + staging"
docker rm -f "$VERIFY_CONTAINER" >/dev/null 2>&1 || true
shred -u "$DUMP_FILE" 2>/dev/null || rm -f "$DUMP_FILE"

ELAPSED=$(( $(date +%s) - START_TS ))

# ============== 签名密钥演练 (同一个月度 timer: keystore 丢了 = 全体用户卸载重装) ==============
#
# 为什么放在这里: 月度演练的职责 = "确认备份真的能用"。keystore 备份同理 ——
# 没验过的备份等于没有 (ADR-0013 相关; 主人 2026-09-21 问「keystore 丢了怎么办」)。
# 失败不覆盖 PG 演练结论, 只记一笔 + 日志大字报 (PG 与密钥是两件事)。
SIGN_VERIFY_LOG="${LOG_DIR:-$(dirname "$LOG")}/signing-key-verify.log"
if [ -x "$_SCRIPT_DIR/verify_signing_key.sh" ]; then
    log "[signing-key] 跑签名密钥演练 (deploy/verify_signing_key.sh)"
    if bash "$_SCRIPT_DIR/verify_signing_key.sh" >>"$SIGN_VERIFY_LOG" 2>&1; then
        log "[signing-key] ✓ 通过 (备份 keystore + 口令可发版)"
    else
        log "[signing-key] ✗ 失败! 详见 $SIGN_VERIFY_LOG (keystore 丢失风险 = 全体用户必须卸载重装)"
        SIGN_KEY_OK=0
    fi
fi

# ============== health state + 退出码 ==============

if [ "$ALL_OK" = "1" ]; then
    jq -n \
        --arg ts "$RUN_TS_ISO" \
        --arg host "$(hostname)" \
        --arg backup "$LATEST_ENC" \
        --argjson matched "$MATCH_TOTAL" \
        --argjson total "$TABLE_TOTAL" \
        --argjson elapsed_sec "$ELAPSED" \
        --argjson sign_key_ok "${SIGN_KEY_OK:-1}" \
        '{status: "success", ts: $ts, host: $host, backup_file: $backup, tables_matched: $matched, tables_total: $total, signing_key_ok: ($sign_key_ok == 1), elapsed_sec: $elapsed_sec, reason: ""}' \
        > "$HEALTH_TMP" && mv -f "$HEALTH_TMP" "$HEALTH_FILE"
    chmod 600 "$HEALTH_FILE" 2>/dev/null || true
    log "DONE 演练成功 ($MATCH_TOTAL/$TABLE_TOTAL 表 100% 一致, elapsed=${ELAPSED}s), 退出 0"
    exit 0
else
    jq -n \
        --arg ts "$RUN_TS_ISO" \
        --arg host "$(hostname)" \
        --arg backup "$LATEST_ENC" \
        --argjson matched "$MATCH_TOTAL" \
        --argjson total "$TABLE_TOTAL" \
        --arg elapsed_sec "$ELAPSED" \
        --arg compare "$COMPARE_LINES" \
        '{status: "failed", ts: $ts, host: $host, backup_file: $backup, tables_matched: $matched, tables_total: $total, reason: "row_count_mismatch", compare_detail: $compare, elapsed_sec: $elapsed_sec}' \
        > "$HEALTH_TMP" && mv -f "$HEALTH_TMP" "$HEALTH_FILE"
    chmod 600 "$HEALTH_FILE" 2>/dev/null || true
    log "DONE 演练失败 (仅 $MATCH_TOTAL/$TABLE_TOTAL 表一致), 退出 5"
    exit 5
fi
