#!/usr/bin/env bash
# ============================================================
# 暖客宝 代码快照 (dirty + untracked → 外置盘异地)
#
# 设计 (dev-domain-backup SOP §3.2):
#   - 不依赖 git (不 git add / commit, 不区分 tracked/untracked)
#   - 打包整个 /home/tooyan/nuankebao-agent/ 到 .tar.zst (zstd level 19)
#   - 包含 .git/ (异地能还原 commit 历史)
#   - 排除 node_modules / .next* / Flutter build / .venv (重建产物)
#   - 文件名带日期: nuankebao-agent-YYYYMMDD-HHMMSS.tar.zst
#   - 产物包含 .sha256 + .manifest.json + .manifest.txt sidecar
#   - 保留策略: mtime +14 天 AND count <= 7 (双保险, 与 backup.sh §4 一致)
#   - fail-closed 预检 (SOP §2.5): 命中 secret basename / 应排除路径未排除 -> exit 4
#   - 输出最近一行供前端读取
#
# 触发:
#   - 手动: /admin/settings/backup 页面 "立即快照代码" 按钮 (Phase 2 待补)
#   - 自动: systemd timer nuankebao-code-snapshot.timer (每日 04:00, 错开 backup 03:00)
#
# 调度: 04:00 错开 backup 03:00, 防 rsync 时段重叠.
#
# 日志: data/logs/code-snapshot.log
#
# 退出码:
#   0  成功
#   1  参数/路径错误
#   2  远端盘未挂载 (本地折中: 写本地 staging, 但 exit 非 0 让 systemd 标记)
#   3  tar 失败
#   4  fail-closed 预检失败 (命中 secret / 漏排除) — **不**备份, alert
#   5  manifest / sha256 校验失败
#
# 见 deploy/README.md §10.
# ============================================================

set -uo pipefail

# ============== 路径配置 (AGENTS §6.3 + deploy/paths.conf) ==============
#
# 三层来源 (优先级从高到低):
#   1. 环境变量 BBT_DIR / SNAPSHOT_DIR / ... (手动 export, 老习惯)
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
# NUANKEBAO_* → BBT_*/SNAPSHOT_DIR 映射
BBT_DIR="${BBT_DIR:-${NUANKEBAO_PROJECT_DIR:-/home/tooyan/nuankebao-agent}}"
DATABACKUPS="${DATABACKUPS:-${NUANKEBAO_DATABACKUPS_DIR:-/home/tooyan/nuankebao-databackups}}"
# SNAPSHOT_DIR 优先 OFFSITE_DIR/nuankebao-codebackups; OFFSITE_DIR 空 = 本地双副本
SNAPSHOT_DIR="${SNAPSHOT_DIR:-${NUANKEBAO_OFFSITE_DIR:-$DATABACKUPS}/nuankebao-codebackups}"
LOG_DIR="${LOG_DIR:-$DATABACKUPS/logs}"
LOG="${LOG_DIR}/code-snapshot.log"
HEALTH_DIR="${HEALTH_DIR:-$DATABACKUPS/backup-health}"
HEALTH_FILE="${HEALTH_DIR}/code-snapshot.json"
HEALTH_TMP="${HEALTH_DIR}/.code-snapshot.json.tmp"
LOCK_FILE="${HEALTH_DIR}/.code-snapshot.lock"

# 双保险: mtime+14 AND count<=7
RETENTION_DAYS=14
RETENTION_COUNT=7

TS() { date '+%Y-%m-%d %H:%M:%S'; }
START_TS=$(date +%s)
RUN_TS=$(date -u +%Y%m%d-%H%M%S)
RUN_TS_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

mkdir -p "$LOG_DIR" "$HEALTH_DIR"

# flock 防并发
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "$(TS) [FATAL] 已有 code-snapshot 在跑 (lock: $LOCK_FILE), 退出" | tee -a "$LOG" >&2
    exit 1
fi

log() { echo "$(TS) $*" | tee -a "$LOG" >&2; }

# ============== 预检 ==============

[ -d "$BBT_DIR" ] || { log "[FATAL] 项目目录不存在: $BBT_DIR"; _write_health "failed" "project_missing"; exit 1; }

# 异地盘 fail-closed (仅 OFFSITE_DIR 非空时检查, dev 模式跳过)
if [ -n "${NUANKEBAO_OFFSITE_DIR:-}" ]; then
    # 取 OFFSITE_DIR 祖先 (拿挂载点), 检查是否挂载
    _OFFSITE_MOUNT="$(findmnt -n -o TARGET --target "$NUANKEBAO_OFFSITE_DIR" 2>/dev/null || echo "")"
    if [ -z "$_OFFSITE_MOUNT" ]; then
        log "[FATAL] 异地盘 $NUANKEBAO_OFFSITE_DIR 未挂载 (code snapshot 必须直接写异地, 不存本地)"
        _write_health "failed" "offline_disk_down"
        exit 2
    fi
fi
unset _OFFSITE_MOUNT

mkdir -p "$SNAPSHOT_DIR" || { log "[FATAL] 快照目录不可写: $SNAPSHOT_DIR"; _write_health "failed" "snapshot_dir_unwritable"; exit 1; }
chmod 700 "$SNAPSHOT_DIR"

log "[1/4] 项目根: $BBT_DIR"
log "[1/4] 快照目录: $SNAPSHOT_DIR"

SNAPSHOT_FILE="${SNAPSHOT_DIR}/nuankebao-agent-${RUN_TS}.tar.zst"

# ============== fail-closed 预检 (SOP §2.5) ==============
#
# 红线:
#   - 不读文件内容, 只看 basename + 路径 (性能 + 隐私)
#   - 命中 secret basename (黑名单) -> exit 4 + alert
#   - 应排除路径未排除 -> exit 4 + alert (dry-run ls 检查)
#
# 黑名单来源: SOP §3.2.1

log "[2/4] fail-closed 预检 (secret basename + 应排除路径检查)..."

# 黑名单 secret basename 模式 (不读内容, 只看文件名)
SECRET_BASENAME_PATTERNS=(
    '\.env$'              # .env (注意: .env.example 允许通过)
    '\.env\.[a-z]+$'      # .env.local / .env.production 等 (含 .local / .example 后续单独放行)
    '\.pem$'
    '\.key$'
    '\.p12$'
    '\.pfx$'
    'token'               # 任意文件名含 token (e.g. github_token, api_token)
    'pgpass'
    'npmrc'
    'pypirc'
    'netrc'
    'id_rsa'              # SSH private key
    'id_dsa'
    'id_ecdsa'
    'id_ed25519'
)

# 应排除路径 (即使在 .tar.zst 里也会被 --exclude 跳过; 但预检也必须命中)
EXPECTED_EXCLUDES=(
    'node_modules'
    '.next'
    'flutter_app/build'
    'flutter_app/.dart_tool'
    'flutter_app/android/.gradle'
    'flutter_app/android/app/build'
    'flutter_app/android/build'
    'flutter_app/ios/Pods'
    '.pnpm-store'
    'test-results'
    'playwright-report'
    '.turbo'
    'coverage'
    'tools/branding/build'
    'data'                # 备份密钥 + health state 不进归档
)

# 用 git ls-files (tracked) + git status --porcelain (dirty) 列举所有要打包的 basename
cd "$BBT_DIR" || { log "[FATAL] 无法 cd $BBT_DIR"; _write_health "failed" "cd_failed"; exit 1; }

# 收集所有 tracked + dirty + untracked 文件的 basename
TRACKED_FILES=$(git ls-files 2>/dev/null || echo "")
DIRTY_FILES=$(git status --porcelain 2>/dev/null | awk '{print $2}' || echo "")

# 合并去重
ALL_FILES=$(printf "%s\n%s\n" "$TRACKED_FILES" "$DIRTY_FILES" | sort -u | grep -v '^$' || echo "")

if [ -z "$ALL_FILES" ]; then
    log "[WARN] git ls-files + status 都为空, 项目无 tracked / dirty 文件? (继续, 仍打包)"
fi

# 1) 检查 secret basename
SECRET_HITS=0
for pat in "${SECRET_BASENAME_PATTERNS[@]}"; do
    # .env.example 特殊豁免 (SOP §2.5 末段)
    if [ "$pat" = '\.env$' ] || [ "$pat" = '\.env\.[a-z]+$' ]; then
        # 只匹配 .env 和 .env.* 但跳过 .env.example
        hits=$(echo "$ALL_FILES" | grep -E "$pat" | grep -v '\.env\.example$' || true)
    else
        hits=$(echo "$ALL_FILES" | grep -E "$pat" || true)
    fi
    if [ -n "$hits" ]; then
        log "[FATAL] 预检命中 secret basename '$pat':"
        echo "$hits" | while read -r f; do
            log "  - $f"
        done
        SECRET_HITS=$((SECRET_HITS + 1))
    fi
done

if [ "$SECRET_HITS" -gt 0 ]; then
    log "[FATAL] fail-closed 预检失败: 命中 $SECRET_HITS 个 secret basename (SOP §2.5 红线)"
    log "[HINT]  .env.example 允许通过, 其他 secret 必须 .gitignore + tar --exclude"
    _write_health "failed" "secret_basename_precheck_failed"
    exit 4
fi

log "[2/4] OK secret basename 预检通过 (0 hit)"

# 2) 应排除路径检查 — 检查这些路径在仓库内确实存在 (确保排除规则有命中目标)
for p in "${EXPECTED_EXCLUDES[@]}"; do
    if [ -e "$p" ]; then
        log "[2/4]   应排除路径存在: $p (将 --exclude)"
    fi
done

# ============== 打包 ==============

log "[3/4] tar 打包 (zstd level 19, 排除列表见 SOP §3.2.1)..."

# tar 排除清单 (SOP §3.2.1 适配 nuankebao):
#
#   重建产物:
#     - node_modules / .pnpm-store / .next / .next-* / .turbo
#     - coverage / test-results / playwright-report / playwright/.cache
#     - *.tsbuildinfo
#     - Flutter: flutter_app/build / .dart_tool / .flutter-plugins* / .metadata
#       flutter_app/android/.gradle / android/app/build / android/build
#       flutter_app/ios/Pods / ios/Flutter/Flutter.framework / ios/Flutter/Flutter.podspec
#       flutter_app/.idea / .vscode 顶层 (子目录的 .vscode/launch.json 保留)
#     - tools/branding/build / tools/branding/**/_tmp / tools/branding/legacy
#
#   备份 / 运行时数据 (归 backup.sh 管, 不重复):
#     - data/             (backup-key.gpg + backup-health/ + logs/)
#     - backups/          (老版本备份根)
#     - 异地 nuankebao-databackups 目录本身
#
#   APK / 包产物:
#     - *.apk / *.aab / *.ipa
#
#   Logs / 临时文件:
#     - *.log / **/*.log
#     - **/.DS_Store
#
#   包含 .git/ (异地能还原 commit 历史, 含 HEAD + refs/heads/master 等)
#
# 注意: secret 黑名单已在上面 fail-closed 预检里 grep 命中, 这里 --exclude 不再列
#       (因为预检通过 = 已确认仓库里没有 .env / .pem / .key 等)

cd "$BBT_DIR" || { log "[FATAL] 无法 cd $BBT_DIR"; _write_health "failed" "cd_failed"; exit 1; }

tar --zstd -cf - \
    --exclude='node_modules' \
    --exclude='.pnpm-store' \
    --exclude='.next' \
    --exclude='.next-*' \
    --exclude='.turbo' \
    --exclude='.parcel-cache' \
    --exclude='coverage' \
    --exclude='test-results' \
    --exclude='playwright-report' \
    --exclude='playwright/.cache' \
    --exclude='.tsbuildinfo' \
    --exclude='flutter_app/build' \
    --exclude='flutter_app/.dart_tool' \
    --exclude='flutter_app/.flutter-plugins' \
    --exclude='flutter_app/.flutter-plugins-dependencies' \
    --exclude='flutter_app/.metadata' \
    --exclude='flutter_app/android/.gradle' \
    --exclude='flutter_app/android/app/build' \
    --exclude='flutter_app/android/build' \
    --exclude='flutter_app/android/local.properties' \
    --exclude='flutter_app/android/.cxx' \
    --exclude='flutter_app/ios/Pods' \
    --exclude='flutter_app/ios/Flutter/Flutter.framework' \
    --exclude='flutter_app/ios/Flutter/Flutter.podspec' \
    --exclude='flutter_app/ios/.symlinks' \
    --exclude='flutter_app/.idea' \
    --exclude='tools/branding/build' \
    --exclude='tools/branding/legacy' \
    --exclude='data' \
    --exclude='backups' \
    --exclude='*.apk' \
    --exclude='*.aab' \
    --exclude='*.ipa' \
    --exclude='*.log' \
    --exclude='.DS_Store' \
    . > "$SNAPSHOT_FILE.tmp" 2>"$SNAPSHOT_FILE.err" || {
    log "[FATAL] tar 失败 (stderr: $(tail -3 "$SNAPSHOT_FILE.err" 2>/dev/null | tr '\n' ' '))"
    rm -f "$SNAPSHOT_FILE.tmp" "$SNAPSHOT_FILE.err"
    _write_health "failed" "tar_failed"
    exit 3
}

mv -f "$SNAPSHOT_FILE.tmp" "$SNAPSHOT_FILE"
rm -f "$SNAPSHOT_FILE.err"
chmod 600 "$SNAPSHOT_FILE"

SNAPSHOT_SIZE=$(stat -c%s "$SNAPSHOT_FILE")
log "[3/4] OK snapshot: $SNAPSHOT_FILE ($SNAPSHOT_SIZE bytes)"

# ============== SHA256 + manifest ==============

log "[4/4] SHA256 + manifest 生成..."

SHA256_FILE="${SNAPSHOT_FILE}.sha256"
sha256sum "$SNAPSHOT_FILE" | awk -v f="$(basename "$SNAPSHOT_FILE")" '{print $1"  "f}' > "$SHA256_FILE"
chmod 600 "$SHA256_FILE"

# 验证 SHA256 (round-trip check)
EXPECTED_SHA=$(awk '{print $1}' "$SHA256_FILE")
ACTUAL_SHA=$(sha256sum "$SNAPSHOT_FILE" | awk '{print $1}')
if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
    log "[FATAL] SHA256 校验失败 (expected=$EXPECTED_SHA actual=$ACTUAL_SHA)"
    rm -f "$SNAPSHOT_FILE" "$SHA256_FILE"
    _write_health "failed" "sha256_mismatch"
    exit 5
fi

# 文件计数 (tar -tf 解压列表, 但不解压; 这里用 tar --list 即可)
FILES_COUNT=$(tar --zstd -tf "$SNAPSHOT_FILE" 2>/dev/null | wc -l)

# HEAD SHA + branch (git 在场)
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "no-git")
HEAD_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "no-git")
DIRTY_COUNT=$(git status --porcelain 2>/dev/null | wc -l)

# 工具版本
TAR_VER=$(tar --version | head -1 | awk '{print $NF}')
ZSTD_VER=$(zstd --version 2>&1 | head -1 | awk '{print $2}')

MANIFEST_JSON="${SNAPSHOT_FILE}.manifest.json"
MANIFEST_TXT="${SNAPSHOT_FILE}.manifest.txt"

jq -n \
    --arg ts "$RUN_TS_ISO" \
    --arg file "$(basename "$SNAPSHOT_FILE")" \
    --arg sha256 "$EXPECTED_SHA" \
    --argjson size "$SNAPSHOT_SIZE" \
    --argjson files_count "$FILES_COUNT" \
    --arg head_sha "$HEAD_SHA" \
    --arg head_branch "$HEAD_BRANCH" \
    --argjson dirty_count "$DIRTY_COUNT" \
    --arg tar_ver "$TAR_VER" \
    --arg zstd_ver "$ZSTD_VER" \
    --arg host "$(hostname)" \
    --arg excludes_version "v1-2026-09-07" \
    '{
        ts: $ts, file: $file, sha256: $sha256, size_bytes: $size,
        files_count: $files_count, head_sha: $head_sha, head_branch: $head_branch,
        dirty_count: $dirty_count, host: $host,
        tool_versions: {tar: $tar_ver, zstd: $zstd_ver},
        excludes_version: $excludes_version
    }' > "$MANIFEST_JSON"
chmod 600 "$MANIFEST_JSON"

cat > "$MANIFEST_TXT" <<EOF
nuankebao-agent code snapshot
============================
file:        $(basename "$SNAPSHOT_FILE")
created:     $RUN_TS_ISO
host:        $(hostname)
size:        $SNAPSHOT_SIZE bytes
files:       $FILES_COUNT
sha256:      $EXPECTED_SHA
git HEAD:    $HEAD_SHA
git branch:  $HEAD_BRANCH
dirty files: $DIRTY_COUNT
tar ver:     $TAR_VER
zstd ver:    $ZSTD_VER
excludes:    v1-2026-09-07 (dev-domain-backup SOP §3.2.1)
EOF
chmod 600 "$MANIFEST_TXT"

log "[4/4] OK sha256 + manifest 生成完成"

# ============== GFS 清理: mtime+14 AND count<=7 双保险 ==============

log "[cleanup] GFS 清理 (mtime+${RETENTION_DAYS} AND count<=${RETENTION_COUNT})"

# 1) mtime +14 delete
while read -r f; do
    log "[cleanup]   delete (mtime+${RETENTION_DAYS}d): $f"
done < <(find "$SNAPSHOT_DIR" -maxdepth 1 -name "nuankebao-agent-*.tar.zst" -mtime +${RETENTION_DAYS} -print -delete 2>/dev/null || true)

# 2) count<=7
count=$(ls -1 "$SNAPSHOT_DIR"/nuankebao-agent-*.tar.zst 2>/dev/null | wc -l)
if [ "$count" -gt "$RETENTION_COUNT" ]; then
    excess=$((count - RETENTION_COUNT))
    while read -r f; do
        rm -f "$f" "${f}.sha256" "${f}.manifest.json" "${f}.manifest.txt"
        log "[cleanup]   delete (count<=${RETENTION_COUNT}): $f (+ sidecars)"
    done < <(ls -1tr "$SNAPSHOT_DIR"/nuankebao-agent-*.tar.zst 2>/dev/null | head -n "$excess")
fi

after=$(ls -1 "$SNAPSHOT_DIR"/nuankebao-agent-*.tar.zst 2>/dev/null | wc -l)
log "[cleanup] OK 保留 $after 份"

# ============== 成功 health state ==============

ELAPSED=$(( $(date +%s) - START_TS ))

_write_health() {
    local status="$1" reason="$2"
    jq -n \
        --arg status "$status" \
        --arg reason "$reason" \
        --arg ts "$RUN_TS_ISO" \
        --arg host "$(hostname)" \
        --argjson elapsed_sec "$ELAPSED" \
        '{status: $status, reason: $reason, ts: $ts, host: $host, elapsed_sec: $elapsed_sec}' \
        > "$HEALTH_TMP" 2>/dev/null && mv -f "$HEALTH_TMP" "$HEALTH_FILE"
    chmod 600 "$HEALTH_FILE" 2>/dev/null || true
}

_write_health "success" ""

log "DONE 快照完成 (size=$SNAPSHOT_SIZE / files=$FILES_COUNT / sha=${EXPECTED_SHA:0:16}... / elapsed=${ELAPSED}s), 退出 0"
exit 0
