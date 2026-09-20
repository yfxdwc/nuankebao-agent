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
#      生产: nuankebao-prod-backup.timer 每日 03:30 + NUANKEBAO_PROFILE=prod (独立目录/日志/health)。
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

# ============== 生产 profile (P3, 2026-09-19) ==============
# NUANKEBAO_PROFILE=prod → PG 容器 / 目录 / 日志 / health 全部独立于 dev, 互不覆盖;
# 媒体源是 Docker named volume (无法按 host 路径 tar, 走 docker run 流式打包, 见下)。
# 显式 env 优先 (跟 dev 同一原则: 环境变量 > 默认值)。
PROD_MODE=0
if [ "${NUANKEBAO_PROFILE:-}" = "prod" ]; then
    PROD_MODE=1
    BACKUP_DIR="${BACKUP_DIR:-$DATABACKUPS/prod/pg-backups}"
    MEDIA_BACKUP_DIR="${MEDIA_BACKUP_DIR:-$DATABACKUPS/prod/media}"
    OFFSITE_DIR="${OFFSITE_DIR:-/media/mm7/tc_backup/nuankebao-prod}"
    LOG_DIR="${LOG_DIR:-$DATABACKUPS/prod/logs}"
    HEALTH_DIR="${HEALTH_DIR:-$DATABACKUPS/prod/backup-health}"
    PG_CONTAINER="${PG_CONTAINER:-nuankebao-prod-postgres}"
    MEDIA_VOLUME="${MEDIA_VOLUME:-nuankebao-prod-uploads}"
fi

BACKUP_DIR="${BACKUP_DIR:-$DATABACKUPS/pg-backups}"
MEDIA_BACKUP_DIR="${MEDIA_BACKUP_DIR:-$DATABACKUPS/media}"
OFFSITE_DIR="${OFFSITE_DIR:-/media/mm7/tc_backup/nuankebao}"
KEY_FILE="${KEY_FILE:-/etc/backup-keys/nuankebao.key.gpg}"

# APK 签名密钥备份目录 (主人 2026-09-21: keystore 丢了 = 全体用户必须卸载重装;
#   而且 Android 密钥轮换需要旧私钥 → 丢了无法轮换 → 唯一治本 = 保证它一直在)
KEYS_BACKUP_DIR="${KEYS_BACKUP_DIR:-$DATABACKUPS/keys}"
SIGNING_JKS="${SIGNING_JKS:-/home/tooyan/nuankebao-keys/nuankebao-release.jks}"
SIGNING_KEY_PROPS="${SIGNING_KEY_PROPS:-$BBT_DIR/flutter_app/android/key.properties}"

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

MEDIA_ARCHIVED=0
if [ "$PROD_MODE" = "1" ]; then
    # 生产: 媒体在 Docker named volume (nuankebao-prod-uploads)
    if docker volume inspect "$MEDIA_VOLUME" >/dev/null 2>&1; then
        echo "$(LOG_TS) [3/5] media 资产档案 (volume: $MEDIA_VOLUME) -> $MEDIA_ARCHIVE"
        # 用已在本地的 pgvector 镜像 (不额外拉取); tar -> stdout -> zstd
        if ! docker run --rm -v "$MEDIA_VOLUME":/data:ro --entrypoint tar \
                pgvector/pgvector:pg16 \
                --exclude=.gitkeep --exclude=cache --exclude=purged --exclude='*.tmp' \
                -C /data -cf - . | zstd -q -f -o "$MEDIA_ARCHIVE"; then
            echo "$(LOG_TS) [FATAL] media tar 失败 (volume: $MEDIA_VOLUME)" | tee -a "$LOG" >&2
            rm -f "$MEDIA_ARCHIVE"
            _write_health "failed" "media_tar_failed" ""
            exit 5
        fi
        MEDIA_ARCHIVED=1
    else
        echo "$(LOG_TS) [3/5] media volume 不存在, 跳过: $MEDIA_VOLUME"
    fi
else
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
        MEDIA_ARCHIVED=1
    fi
fi

if [ "$MEDIA_ARCHIVED" = "1" ]; then
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

# === APK 签名密钥 (keystore + key.properties) 加密备份 ===
# 为什么单独一段 (主人 2026-09-21 问「keystore 丢了怎么办」):
#   keystore = 发行身份, 丢了以后所有 APK 签名都变 → **全体用户必须卸载重装**;
#   Android v3 密钥轮换要用旧私钥签 lineage → 丢了没法轮换。唯一治本 = 一直在多个地方有副本。
#   key.properties 里有口令, 必须跟 keystore **一起**备份 (只有 jks 没口令等于没有)。
# 失败不影响 PG/media 备份 (非致命, 但日志会大声报)
if [ -f "$SIGNING_JKS" ]; then
    echo "$(LOG_TS) [keys] 备份 APK 签名密钥 -> $KEYS_BACKUP_DIR" | tee -a "$LOG"
    mkdir -p "$KEYS_BACKUP_DIR" && chmod 700 "$KEYS_BACKUP_DIR"
    KEYS_STAGE="$(mktemp -d /tmp/nuankebao-keys-XXXXXX)"
    install -m 600 "$SIGNING_JKS" "$KEYS_STAGE/nuankebao-release.jks"
    if [ -f "$SIGNING_KEY_PROPS" ]; then
        install -m 600 "$SIGNING_KEY_PROPS" "$KEYS_STAGE/key.properties"
    else
        echo "$(LOG_TS) [keys][WARN] 没找到 $SIGNING_KEY_PROPS (口令没进备份 → 恢复时打不开 jks)" | tee -a "$LOG" >&2
    fi
    cat > "$KEYS_STAGE/README.txt" <<'KEYS_README'
暖客宝 APK 签名密钥 (自动备份)

内容:
  nuankebao-release.jks  —— release 签名 keystore (包名 cn.nuankebao.app)
  key.properties         —— storePassword / keyPassword / keyAlias / storeFile

怎么恢复 (换机器 / 灾难恢复):
  1. 解包: gpg --decrypt signing-keys.tar.zst.enc | tar --zstd -xf - -C /tmp/keys
  2. 放回位置: mkdir -p /home/tooyan/nuankebao-keys && cp /tmp/keys/nuankebao-release.jks /home/tooyan/nuankebao-keys/ && chmod 600 ...
  3. 放回配置: cp /tmp/keys/key.properties flutter_app/android/   (并把 storeFile 改成新路径)
  4. 演练验证: bash deploy/verify_signing_key.sh   ← 必须通过, 否则别发版

指纹 (必须与历史版本一致, 否则用户要先卸载):
  SHA-256: 0DB0A1BCFF6DA703B9FE3A3C05033CCF2D67E4F0B04D69164319C16B621900B6
  SHA-1  : 1E369EE9956CCF5E393F55D4B63C882B91AC043E
  证书   : CN=NuankeBao, OU=Mobile, O=NuankeBao, L=Beijing, ST=Beijing, C=CN

⚠️ 本包含私钥 + 口令: 只放加密归档里, 别解开留在磁盘/聊天工具里。
KEYS_README
    KEYS_TAR="$KEYS_STAGE/../signing-keys.tar.zst"
    ( cd "$KEYS_STAGE" && tar --zstd -cf "$KEYS_TAR" . )
    KEYS_ENC="$KEYS_BACKUP_DIR/signing-keys.tar.zst.enc"
    if gpg --batch --yes --pinentry-mode loopback --passphrase-file "$KEY_FILE" \
            --symmetric --cipher-algo AES256 --output "$KEYS_ENC" "$KEYS_TAR"; then
        chmod 600 "$KEYS_ENC"
        # 月度留档: 每月一份 (keystore 极少变; 保留 12 份防"改坏了又想回退")
        cp -f "$KEYS_ENC" "$KEYS_BACKUP_DIR/signing-keys-$(date +%Y%m).tar.zst.enc"
        ls -1t "$KEYS_BACKUP_DIR"/signing-keys-*.tar.zst.enc 2>/dev/null | tail -n +13 | xargs -r rm -f
        echo "$(LOG_TS) [keys] OK $(stat -c%s "$KEYS_ENC") bytes -> $KEYS_ENC" | tee -a "$LOG"
    else
        echo "$(LOG_TS) [keys][ERROR] GPG 加密签名密钥失败" | tee -a "$LOG" >&2
    fi
    shred -u "$KEYS_STAGE"/* 2>/dev/null || rm -f "$KEYS_STAGE"/*
    rmdir "$KEYS_STAGE" 2>/dev/null || true
    rm -f "$KEYS_TAR"
else
    echo "$(LOG_TS) [keys][WARN] 没找到 $SIGNING_JKS → 跳过签名密钥备份" | tee -a "$LOG" >&2
fi

# === ssh push (主理人 2026-09-14 拍: 异地到 lk:/media/mm7/tc_backup/nuankebao) ===
if ! ssh -o BatchMode=yes -o ConnectTimeout=10 lk true 2>/dev/null; then
    echo "$(LOG_TS) [FATAL] ssh lk unreachable" | tee -a "$LOG" >&2
    exit 10
fi
ssh -o BatchMode=yes lk "mkdir -p ${OFFSITE_DIR}/pg-backups ${OFFSITE_DIR}/media ${OFFSITE_DIR}/keys && chmod 700 ${OFFSITE_DIR} ${OFFSITE_DIR}/pg-backups ${OFFSITE_DIR}/media ${OFFSITE_DIR}/keys"
AVAIL_KB=$(ssh -o BatchMode=yes lk "df -k ${OFFSITE_DIR}" | tail -1 | awk '{print $4}')
AVAIL_GB=$((AVAIL_KB / 1024 / 1024))
echo "$(LOG_TS) [pre-check] ssh ok, ${OFFSITE_DIR} free=${AVAIL_GB}G" | tee -a "$LOG"
if [[ "${AVAIL_GB}" -lt 2 ]]; then
    echo "$(LOG_TS) [FATAL] offsite space < 2G, abort" | tee -a "$LOG" >&2
    exit 11
fi
echo "$(LOG_TS) [3/5] rsync PG -> lk:${OFFSITE_DIR}/pg-backups/" | tee -a "$LOG"
shopt -s nullglob
for f in "$BACKUP_DIR"/pg-*.dump.gpg; do
    if ! rsync -a "$f" "lk:${OFFSITE_DIR}/pg-backups/"; then
        shopt -u nullglob
        echo "$(LOG_TS) [FATAL] rsync PG failed: $f" | tee -a "$LOG" >&2
        exit 12
    fi
done
shopt -u nullglob
echo "$(LOG_TS) [3/5] rsync media -> lk:${OFFSITE_DIR}/media/" | tee -a "$LOG"
shopt -s nullglob
for f in "$MEDIA_BACKUP_DIR"/*.tar.zst.enc "$MEDIA_BACKUP_DIR"/*.sha256 "$MEDIA_BACKUP_DIR"/*.manifest.json; do
    if ! rsync -a "$f" "lk:${OFFSITE_DIR}/media/"; then
        shopt -u nullglob
        echo "$(LOG_TS) [FATAL] rsync media failed: $f" | tee -a "$LOG" >&2
        exit 13
    fi
done
shopt -u nullglob
ssh -o BatchMode=yes lk "mkdir -p ${OFFSITE_DIR}/.backup-key && chmod 700 ${OFFSITE_DIR}/.backup-key"
ssh -o BatchMode=yes lk "install -m 600 /dev/stdin ${OFFSITE_DIR}/.backup-key/backup-key.gpg" < "$KEY_FILE"
PG_COUNT=$(ssh -o BatchMode=yes lk "ls -1 ${OFFSITE_DIR}/pg-backups/*.gpg 2>/dev/null | wc -l")
MEDIA_COUNT=$(ssh -o BatchMode=yes lk "ls -1 ${OFFSITE_DIR}/media/*.enc 2>/dev/null | wc -l")
# 签名密钥异地 (丢了 = 全体用户卸载重装, 所以它比 PG 备份还"经不起丢")
shopt -s nullglob
for f in "$KEYS_BACKUP_DIR"/signing-keys*.enc; do
    rsync -a "$f" "lk:${OFFSITE_DIR}/keys/" || echo "$(LOG_TS) [keys][ERROR] rsync 签名密钥失败: $f" | tee -a "$LOG" >&2
done
shopt -u nullglob
KEYS_COUNT=$(ssh -o BatchMode=yes lk "ls -1 ${OFFSITE_DIR}/keys/*.enc 2>/dev/null | wc -l")
echo "$(LOG_TS) [3/5] OK offsite PG=$PG_COUNT MEDIA=$MEDIA_COUNT KEYS=$KEYS_COUNT key-copied" | tee -a "$LOG"

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
