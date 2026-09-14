#!/usr/bin/env bash
# ============================================================
# 暖客宝 工业级备份脚本 (PG + Media + GPG + 异地 + GFS)
#
# 职责 (按顺序):
#   1. PG 逻辑全备 (pg_dump -Fc 自定义压缩) + GPG 加密 -> 本地
#   2. media 资产档案 (photos + uploads) + GPG 加密 -> 本地
#   3. rsync 三份本地加密备份 -> 外置盘异地 (/media/tooyan/<盘符>/<盘符>/nuankebao-databackups/)
#   4. GFS 清理: 本地 PG/Media 各保留 7 份 (mtime +14 AND count<=7 双保险)
#
# 设计 (dev-domain-backup SOP §3.1):
#   - 全部用密钥文件自动解密, 无人工介入. 失败非 0 退出 (systemd 标记).
#   - 日志: stdout/stderr 由 systemd 追加到 logs/backup.log.
#   - flock 防并发 (.backup.lock, 防止 backup + restore-verify 同时跑破坏副本)
#   - 退出码: 0=成功 2=密钥缺失 3=pg_dump 失败 4=GPG 加密 PG 失败 5=tar 失败 6=GPG 加密 media 失败
#
# 调度: systemd timer nuankebao-backup.timer 每日 03:00 (Persistent=true, RandomizedDelaySec=5min).
#
# 见 deploy/README.md §10.
# ============================================================

set -euo pipefail

# ============== 路径配置 (AGENTS §6.3 + deploy/paths.conf) ==============
#
# 三层来源 (优先级从高到低):
#   1. 环境变量 BBT_DIR / DATABACKUPS / ... (手动 export, 老习惯)
#   2. systemd EnvironmentFile= ~/.config/nuankebao/paths.conf (注入 NUANKEBAO_*)
#   3. 本仓库 deploy/paths.conf (手动跑时 source, dev 默认值)
#
# 没任何配置: 用脚本内 hardcoded 默认值 (兜底, 主人调试用)

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

# ============== 配置 (BBT_* 保留旧名, 见 AGENTS §6.2) ==============
# NUANKEBAO_* → BBT_* 映射 (向后兼容老 env 注入写法)
BBT_DIR="${BBT_DIR:-${NUANKEBAO_PROJECT_DIR:-/home/tooyan/nuankebao-agent}}"
DATABACKUPS="${DATABACKUPS:-${NUANKEBAO_DATABACKUPS_DIR:-/home/tooyan/nuankebao-databackups}}"
BACKUP_DIR="${BACKUP_DIR:-$DATABACKUPS/pg-backups}"
MEDIA_BACKUP_DIR="${MEDIA_BACKUP_DIR:-$DATABACKUPS/media}"
OFFSITE_DIR="${OFFSITE_DIR:-${NUANKEBAO_OFFSITE_DIR:-$DATABACKUPS/offsite}}"
KEY_FILE="${KEY_FILE:-$DATABACKUPS/backup-key.gpg}"

LOG_DIR="${LOG_DIR:-$DATABACKUPS/logs}"
LOG="${LOG_DIR}/backup.log"

HEALTH_DIR="${HEALTH_DIR:-$DATABACKUPS/backup-health}"
HEALTH_FILE="${HEALTH_DIR}/backup.json"
HEALTH_TMP="${HEALTH_DIR}/.backup.json.tmp"

LOCK_FILE="${HEALTH_DIR}/.backup.lock"

PG_CONTAINER="${PG_CONTAINER:-nuankebao-postgres}"
PG_USER="${PG_USER:-nuankebao}"
PG_DB="${PG_DB:-nuankebao}"

# 媒体根目录 (跟 docker-compose + AGENTS §6.1 一致)
MEDIA_ROOT="${MEDIA_ROOT:-$BBT_DIR/public/uploads}"

# GFS 双保险: mtime+14 AND count<=7 (SOP §2.4)
RETENTION_COUNT=7
RETENTION_DAYS=14

LOG_TS() { date '+%Y-%m-%d %H:%M:%S'; }
TS=$(date +%Y%m%d-%H%M%S)
RUN_TS_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
START_TS=$(date +%s)

mkdir -p "$BACKUP_DIR" "$MEDIA_BACKUP_DIR" "$HEALTH_DIR" "$LOG_DIR"
chmod 700 "$BACKUP_DIR" "$MEDIA_BACKUP_DIR" "$HEALTH_DIR" "$LOG_DIR"

# ============== flock 防并发 ==============

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$(LOG_TS) [FATAL] 已有 backup 在跑 (lock: $LOCK_FILE), 退出" | tee -a "$LOG" >&2
    exit 1
fi

# ============== 预检 ==============

if [ ! -s "$KEY_FILE" ]; then
    echo "$(LOG_TS) [FATAL] 密钥文件缺失或为空: $KEY_FILE" | tee -a "$LOG" >&2
    echo "$(LOG_TS) [HINT]  生成: openssl rand -base64 32 > $KEY_FILE && chmod 600 $KEY_FILE" | tee -a "$LOG" >&2
    _write_health "failed" "key_missing" ""
    exit 2
fi

# 检查 PG container 是否在跑 (不健康就 fail-fast, 不要默默备份空数据)
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${PG_CONTAINER}$"; then
    echo "$(LOG_TS) [FATAL] PG container 未运行: $PG_CONTAINER (跳过备份, 防空 dump)" | tee -a "$LOG" >&2
    echo "$(LOG_TS) [HINT]  起: sudo systemctl start nuankebao-stack.service" | tee -a "$LOG" >&2
    _write_health "failed" "pg_container_down" ""
    exit 2
fi

# 清理函数: 失败时写 health state + exit 非 0
cleanup_on_error() {
    local exit_code=$?
    local reason="${1:-unknown}"
    _write_health "failed" "$reason" ""
    echo "$(LOG_TS) [FATAL] 备份失败 exit=$exit_code reason=$reason" | tee -a "$LOG" >&2
    exit "$exit_code"
}

_write_health() {
    local status="$1" reason="$2" extra="$3"
    jq -n \
        --arg status "$status" \
        --arg reason "$reason" \
        --arg ts "$RUN_TS_ISO" \
        --arg extra "$extra" \
        --arg host "$(hostname)" \
        --arg pg_container "$PG_CONTAINER" \
        '{status: $status, reason: $reason, ts: $ts, host: $host, pg_container: $pg_container, extra: $extra}' \
        > "$HEALTH_TMP" 2>/dev/null && mv -f "$HEALTH_TMP" "$HEALTH_FILE"
}

echo "$(LOG_TS) [1/5] START backup (project=$BBT_DIR)"
echo "$(LOG_TS) [1/5] PG container: $PG_CONTAINER (db=$PG_DB user=$PG_USER)"
_write_health "running" "in_progress" ""

# ============== 1) Postgres 备份 ==============

PG_OUT="$BACKUP_DIR/pg-$TS.dump"
PG_ENC="$PG_OUT.gpg"

echo "$(LOG_TS) [2/5] pg_dump -> $PG_OUT"
if ! docker exec "$PG_CONTAINER" pg_dump -U "$PG_USER" -Fc "$PG_DB" > "$PG_OUT"; then
    echo "$(LOG_TS) [FATAL] pg_dump 失败" | tee -a "$LOG" >&2
    rm -f "$PG_OUT"
    _write_health "failed" "pg_dump_failed" ""
    exit 3
fi
chmod 600 "$PG_OUT"

echo "$(LOG_TS) [2/5] GPG encrypt -> $PG_ENC"
if ! gpg --batch --yes --pinentry-mode loopback --passphrase-file "$KEY_FILE" \
        --symmetric --cipher-algo AES256 --output "$PG_ENC" "$PG_OUT"; then
    echo "$(LOG_TS) [FATAL] GPG 加密 PG 失败" | tee -a "$LOG" >&2
    rm -f "$PG_OUT" "$PG_ENC"
    _write_health "failed" "gpg_pg_failed" ""
    exit 4
fi
chmod 600 "$PG_ENC"
shred -u "$PG_OUT" 2>/dev/null || rm -f "$PG_OUT"
PG_SIZE=$(stat -c%s "$PG_ENC" 2>/dev/null || echo 0)
echo "$(LOG_TS) [2/5] OK pg encrypted backup: $PG_ENC ($PG_SIZE bytes)"

# ============== 2) Media 资产档案 ==============

MEDIA_ARCHIVE="$MEDIA_BACKUP_DIR/media-$TS.tar.zst"
MEDIA_ENC="$MEDIA_ARCHIVE.enc"

if [ ! -d "$MEDIA_ROOT" ]; then
    echo "$(LOG_TS) [3/5] media 资产目录不存在, 跳过: $MEDIA_ROOT"
else
    echo "$(LOG_TS) [3/5] media 资产档案 -> $MEDIA_ARCHIVE"
    # 排除 .gitkeep (空目录标记) + thumbs cache (如果有) + purged (逻辑删除)
    # -C 切到 $BBT_DIR/public, 路径 = uploads/...
    if ! tar --zstd -cf "$MEDIA_ARCHIVE" \
            --exclude='.gitkeep' \
            --exclude='cache' \
            --exclude='purged' \
            --exclude='*.tmp' \
            -C "$BBT_DIR/public" uploads 2>&1 | tail -3; then
        echo "$(LOG_TS) [FATAL] media tar 失败" | tee -a "$LOG" >&2
        rm -f "$MEDIA_ARCHIVE"
        _write_health "failed" "media_tar_failed" ""
        exit 5
    fi
    chmod 600 "$MEDIA_ARCHIVE"
    MEDIA_SIZE=$(stat -c%s "$MEDIA_ARCHIVE" 2>/dev/null || echo 0)
    echo "$(LOG_TS) [3/5] media archive: $MEDIA_SIZE bytes"

    echo "$(LOG_TS) [3/5] GPG encrypt -> $MEDIA_ENC"
    if ! gpg --batch --yes --pinentry-mode loopback --passphrase-file "$KEY_FILE" \
            --symmetric --cipher-algo AES256 --output "$MEDIA_ENC" "$MEDIA_ARCHIVE"; then
        echo "$(LOG_TS) [FATAL] GPG 加密 media 失败" | tee -a "$LOG" >&2
        rm -f "$MEDIA_ARCHIVE" "$MEDIA_ENC"
        _write_health "failed" "gpg_media_failed" ""
        exit 6
    fi
    chmod 600 "$MEDIA_ENC"
    shred -u "$MEDIA_ARCHIVE" 2>/dev/null || rm -f "$MEDIA_ARCHIVE"
    MEDIA_ENC_SIZE=$(stat -c%s "$MEDIA_ENC" 2>/dev/null || echo 0)
    echo "$(LOG_TS) [3/5] OK media encrypted backup: $MEDIA_ENC ($MEDIA_ENC_SIZE bytes)"
fi

# ============== 3) 异地 rsync (SOP §2.5 + §3.1) ==============

# tc (2026-09-10 主人拍): OFFSITE_DIR 是本地双副本, 不依赖 /media/tooyan/<盘符>/<盘符>
mkdir -p "$OFFSITE_DIR/pg-backups" "$OFFSITE_DIR/media"
chmod 700 "$OFFSITE_DIR/pg-backups" "$OFFSITE_DIR/media"

echo "$(LOG_TS) [4/5] rsync -> $OFFSITE_DIR"
rsync -a --delete-after "$BACKUP_DIR/" "$OFFSITE_DIR/pg-backups/" || {
    echo "$(LOG_TS) [WARN] PG 异地 rsync 部分失败 (继续, 本地副本完整)" | tee -a "$LOG" >&2
}
rsync -a --delete-after "$MEDIA_BACKUP_DIR/" "$OFFSITE_DIR/media/" || {
    echo "$(LOG_TS) [WARN] media 异地 rsync 部分失败 (继续, 本地副本完整)" | tee -a "$LOG" >&2
}
chmod -R go-rwx "$OFFSITE_DIR/pg-backups/" "$OFFSITE_DIR/media/" 2>/dev/null || true
install -d -m 700 "$OFFSITE_DIR/.backup-key"
install -m 600 "$KEY_FILE" "$OFFSITE_DIR/.backup-key/backup-key.gpg" || true
echo "$(LOG_TS) [4/5] OK 异地副本: PG=$(ls -1 $OFFSITE_DIR/pg-backups/*.gpg 2>/dev/null | wc -l) MEDIA=$(ls -1 $OFFSITE_DIR/media/*.enc 2>/dev/null | wc -l) 密钥已异地副本"

# ============== 4) GFS 清理: mtime+14 AND count<=7 双保险 (SOP §2.4) ==============

gfs_cleanup() {
    set +e  # GFS 内部 find|while 空 stdin rc=1, 跳过 set -e
    local label="$1"
    local dir="$2"
    local pattern="$3"
    echo "$(LOG_TS) [5/5] GFS 清理: $label (mtime+${RETENTION_DAYS} AND count<=${RETENTION_COUNT})"
    # 1) mtime +14 delete
    local deleted_mtime=0
    while read -r f; do
        echo "$(LOG_TS) [5/5]   delete (mtime+${RETENTION_DAYS}d): $f"
        deleted_mtime=$((deleted_mtime + 1))
    done < <(find "$dir" -maxdepth 1 -name "$pattern" -mtime +${RETENTION_DAYS} -print -delete 2>/dev/null || true)
    # 2) count<=7: 若份数仍 >7, 按 mtime 升序删最旧的 excess 个
    local count
    count=$(ls -1 "$dir"/$pattern 2>/dev/null | wc -l)
    local deleted_count=0
    if [ "$count" -gt "$RETENTION_COUNT" ]; then
        local excess=$((count - RETENTION_COUNT))
        while read -r f; do
            rm -f "$f"
            echo "$(LOG_TS) [5/5]   delete (count<=${RETENTION_COUNT}): $f"
            deleted_count=$((deleted_count + 1))
        done < <(ls -1tr "$dir"/$pattern 2>/dev/null | head -n "$excess")
    fi
    local after
    after=$(ls -1 "$dir"/$pattern 2>/dev/null | wc -l)
    echo "$(LOG_TS) [5/5] OK $label 保留 $after 份 (mtime 删 $deleted_mtime / count 删 $deleted_count)"
}

gfs_cleanup "本地 PG 日备"     "$BACKUP_DIR"       "pg-*.dump.gpg"
gfs_cleanup "本地 media 档案"  "$MEDIA_BACKUP_DIR" "media-*.tar.zst.enc"

# ============== 5) 成功 health state ==============

ELAPSED=$(( $(date +%s) - START_TS ))
PG_COUNT=$(ls -1 "$BACKUP_DIR"/pg-*.dump.gpg 2>/dev/null | wc -l)
MEDIA_COUNT=$(ls -1 "$MEDIA_BACKUP_DIR"/media-*.tar.zst.enc 2>/dev/null | wc -l)

jq -n \
    --arg ts "$RUN_TS_ISO" \
    --arg host "$(hostname)" \
    --arg pg_container "$PG_CONTAINER" \
    --argjson pg_size "$PG_SIZE" \
    --argjson media_size "${MEDIA_ENC_SIZE:-0}" \
    --argjson pg_count "$PG_COUNT" \
    --argjson media_count "$MEDIA_COUNT" \
    --argjson elapsed_sec "$ELAPSED" \
    '{status: "success", ts: $ts, host: $host, pg_container: $pg_container, pg_size_bytes: $pg_size, media_size_bytes: $media_size, pg_backup_count: $pg_count, media_backup_count: $media_count, elapsed_sec: $elapsed_sec, reason: ""}' \
    > "$HEALTH_TMP" && mv -f "$HEALTH_TMP" "$HEALTH_FILE"
chmod 600 "$HEALTH_FILE"

echo "$(LOG_TS) DONE 备份完成 (PG=$PG_SIZE bytes / Media=${MEDIA_ENC_SIZE:-0} bytes / elapsed=${ELAPSED}s), 退出 0"
exit 0
