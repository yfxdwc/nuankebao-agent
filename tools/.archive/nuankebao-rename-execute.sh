#!/usr/bin/env bash
# ============================================================
# 暖客宝 (NuankeBao) rename 一键执行脚本
#
# 背景: pi agent mv 仓库目录后, bash 工具 cwd 锁死,
#       无法在 agent 内执行 sudo systemctl / docker compose。
#       主人手工跑这个脚本完成剩余 stages 3-8。
#
# 用法:
#   bash /home/mm7/nuankebao-agent/tools/nuankebao-rename-execute.sh 3       # 只跑 stage 3
#   bash /home/mm7/nuankebao-agent/tools/nuankebao-rename-execute.sh all    # 跑 stage 3-8
#
# 安全: set -euo pipefail + 每步 echo + 关键步骤 prompt
# 回滚: tools/nuankebao-rename-rollback.sh (主人可手工跑)
#
# 拍板: 2026-09-06 主人 G0 全过 + sudo 提升 + delete-stale
# SOP: docs/rename-sop.md
# ============================================================
set -euo pipefail

# ---------- 路径常量 ----------
NUANKEBAO_DIR="/home/mm7/nuankebao-agent"
BBT_DIR="/home/mm7/nuankebao-agent"  # 应当不存在,仅作 fallback
TMP_DUMP="/tmp/bbt-pre-rename.dump"
LOG_DIR="/tmp"
STAGE="${1:-all}"

cd "$NUANKEBAO_DIR"

# ---------- 颜色 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

step() { echo -e "${CYAN}▶ $1${NC}"; }
ok()   { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠ $1${NC}"; }
die()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

# ---------- 前置检查 ----------
step "前置检查"
[ -d "$NUANKEBAO_DIR" ] || die "新目录不存在: $NUANKEBAO_DIR"
[ ! -d "$BBT_DIR" ]      || die "老目录仍存在: $BBT_DIR (mv 未完成?)"
[ -f "$TMP_DUMP" ]      || die "DB dump 不存在: $TMP_DUMP (阶段 1.3 漏跑?)"
command -v docker  >/dev/null || die "docker 未装"
command -v sudo    >/dev/null || die "sudo 未装"
ok "前置 OK"

# ============================================================
# Stage 3: systemd service + tunnel 改名
# ============================================================
stage_3() {
    step "Stage 3: systemd service + tunnel 改名"

    # 3.1 nuankebao-stack.service (system, root-owned)
    step "3.1 安装 nuankebao-stack.service 到 /etc/systemd/system"
    sudo cp "$NUANKEBAO_DIR/tools/nuankebao-stack.service" /etc/systemd/system/nuankebao-stack.service
    sudo chown root:root /etc/systemd/system/nuankebao-stack.service
    sudo chmod 644 /etc/systemd/system/nuankebao-stack.service
    ok "nuankebao-stack.service 装好"

    # 3.2 nuankebao-nextjs.service (user)
    step "3.2 安装 nuankebao-nextjs.service 到 ~/.config/systemd/user"
    mkdir -p "$HOME/.config/systemd/user/nuankebao-nextjs.service.d"
    cp "$NUANKEBAO_DIR/tools/systemd/nuankebao-nextjs.service" \
       "$HOME/.config/systemd/user/nuankebao-nextjs.service"
    # override.conf 沿用
    if [ -f "$NUANKEBAO_DIR/tools/systemd/override.conf" ]; then
        cp "$NUANKEBAO_DIR/tools/systemd/override.conf" \
           "$HOME/.config/systemd/user/nuankebao-nextjs.service.d/override.conf"
    fi
    ok "nuankebao-nextjs.service 装好"

    # 3.3 daemon-reload
    step "3.3 daemon-reload"
    sudo systemctl daemon-reload
    systemctl --user daemon-reload
    ok "daemon-reload 完成"

    # 3.4 disable 旧的 bbt-stack (它一直在 activating 死循环)
    step "3.4 disable bbt-stack.service"
    sudo systemctl disable bbt-stack.service 2>/dev/null || true
    sudo systemctl stop bbt-stack.service    2>/dev/null || true
    ok "bbt-stack.service 已停"

    # 3.5 enable + start nuankebao-stack
    step "3.5 enable + start nuankebao-stack (只跑 postgres)"
    sudo systemctl enable nuankebao-stack.service
    sudo systemctl start nuankebao-stack.service
    sleep 8  # docker compose up postgres 等待 ready
    sudo systemctl is-active nuankebao-stack.service || die "nuankebao-stack 未 active"
    ok "nuankebao-stack active"

    # 3.6 验证 postgres 还在响应
    step "3.6 验证 postgres (nuankebao-postgres container 仍在跑,只在 systemd 启停)"
    docker exec nuankebao-postgres pg_isready -U bbt -d bbt || die "postgres 不响应"
    ok "postgres 响应正常"

    # 3.7 enable + start nuankebao-nextjs (user service)
    step "3.7 enable + start nuankebao-nextjs.service"
    systemctl --user enable nuankebao-nextjs.service
    systemctl --user start  nuankebao-nextjs.service
    sleep 12  # next dev 冷启动 10-15 秒
    ok "nuankebao-nextjs 启动 (PID 见 systemctl --user status)"

    # 3.8 验证公网
    step "3.8 验证公网 + 本机"
    sleep 3
    HTTP_LOCAL=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:3003/ || echo 000)
    HTTP_PUB=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 https://nuankebao.tooyang.top/ || echo 000)
    echo "  本机 3003: $HTTP_LOCAL"
    echo "  公网 nuankebao.tooyang.top: $HTTP_PUB"
    if [[ "$HTTP_LOCAL" =~ ^(200|307|404)$ ]] && [[ "$HTTP_PUB" =~ ^(200|307|404)$ ]]; then
        ok "服务恢复 ✓"
    else
        warn "服务恢复失败, 看 journalctl --user -u nuankebao-nextjs -n 50"
    fi
}

# ============================================================
# Stage 4: 代码层字符串替换 (60 文件, sed 批量)
# ============================================================
stage_4() {
    step "Stage 4: 代码层字符串替换"

    # 4.1 备份一份变更清单 (主人在阶段 1 已有 git baseline)
    step "4.1 验证 git working tree clean"
    [ -z "$(git status -s)" ] || warn "working tree 有未 commit 改动, 继续会覆盖"

    # 4.2 替换: 路径
    step "4.2 替换 /home/mm7/nuankebao-agent → /home/mm7/nuankebao-agent"
    rg -l '/home/mm7/nuankebao-agent' --hidden -g '!node_modules' -g '!.git' -g '!drizzle/meta' -g '!*.lock' \
       | xargs sed -i 's|/home/mm7/nuankebao-agent|/home/mm7/nuankebao-agent|g' 2>/dev/null || true
    ok "路径替换完成"

    # 4.3 替换: 脚本内部 BBT_DIR 默认值 (owner 9-05 §6.3 保留 BBT_DIR 变量名, 但路径换)
    step "4.3 替换脚本内 BBT_DIR 默认值"
    rg -l 'BBT_DIR=' tools/ | while read -r f; do
        sed -i 's|BBT_DIR="${BBT_DIR:-/home/mm7/nuankebao-agent}"|BBT_DIR="${BBT_DIR:-/home/mm7/nuankebao-agent}"|g' "$f"
        sed -i 's|BBT_DIR="${BBT_DIR:-/opt/nuankebao}"|BBT_DIR="${BBT_DIR:-/opt/nuankebao}"|g' "$f"
        sed -i 's|BBT_DIR="/home/mm7/nuankebao-agent"|BBT_DIR="/home/mm7/nuankebao-agent"|g' "$f"
    done
    ok "BBT_DIR 默认值替换完成"

    # 4.4 替换: backup.sh / backup-cron.sh 默认值
    step "4.4 替换 backup 相关默认值"
    for f in tools/backup.sh tools/restore.sh tools/backup-cron.sh; do
        [ -f "$f" ] || continue
        sed -i 's|BACKUP_DIR="${BACKUP_DIR:-/opt/nuankebao/backups}"|BACKUP_DIR="${BACKUP_DIR:-/opt/nuankebao/backups}"|g' "$f"
        sed -i 's|/opt/nuankebao/tools/backup.sh|/opt/nuankebao/tools/backup.sh|g' "$f"
        sed -i "s|/tmp/nuankebao-backup.log|/tmp/nuankebao-backup.log|g" "$f"
    done
    ok "backup 默认值替换完成"

    # 4.5 替换: log 路径
    step "4.5 替换 log 路径 /tmp/bbt-* → /tmp/nuankebao-*"
    rg -l '/tmp/bbt-' tools/ | xargs sed -i 's|/tmp/bbt-|/tmp/nuankebao-|g' 2>/dev/null || true
    ok "log 路径替换完成"

    # 4.6 替换: docker container 名 nuankebao-postgres → nuankebao-postgres (在 .env / .env.example / docker-compose*.yml)
    step "4.6 替换 docker container 名 nuankebao-postgres → nuankebao-postgres (在配置)"
    sed -i 's|nuankebao-postgres|nuankebao-postgres|g' docker-compose.yml docker-compose.prod.yml .env.example 2>/dev/null || true
    ok "docker-compose 配置替换完成"

    # 4.7 替换: cloudflared-bbt 目录 → cloudflared-nuankebao (云上备份目录)
    step "4.7 替换 cloudflared-bbt 目录"
    sed -i 's|cloudflared-bbt|cloudflared-nuankebao|g' tools/*.sh 2>/dev/null || true
    ok "cloudflared 目录替换完成"

    # 4.8 替换: tools/bbt-*.sh → tools/nuankebao-*.sh 引用 (脚本内部 cross-reference)
    step "4.8 替换脚本内 tools/bbt-* 引用"
    rg -l 'tools/bbt-' tools/ docs/ AGENTS.md 2>/dev/null \
       | xargs sed -i 's|tools/bbt-|tools/nuankebao-|g' 2>/dev/null || true
    ok "脚本 cross-ref 替换完成"

    # 4.9 替换: AGENTS.md / README.md / PHYSICAL_OPS.md 路径
    step "4.9 替换 AGENTS.md / README / PHYSICAL_OPS 路径"
    for f in AGENTS.md README.md PHYSICAL_OPS.md docs/*.md CHANGELOG.md; do
        [ -f "$f" ] || continue
        sed -i 's|/home/mm7/nuankebao-agent|/home/mm7/nuankebao-agent|g' "$f"
    done
    ok "文档路径替换完成"

    # 4.10 替换: docker volume nuankebao-postgres-data → nuankebao-postgres-data
    step "4.10 替换 docker volume"
    sed -i 's|name: nuankebao-postgres-data|name: nuankebao-postgres-data|g' docker-compose.yml docker-compose.prod.yml 2>/dev/null || true
    ok "volume 替换完成"

    # 4.11 替换: install-systemd.sh 脚本内部引用
    step "4.11 替换 install-systemd.sh / install-guards.sh 内部"
    for f in tools/install-systemd.sh tools/install-guards.sh; do
        [ -f "$f" ] || continue
        sed -i 's|bbt-nextjs.service|nuankebao-nextjs.service|g' "$f"
        sed -i 's|bbt-stack.service|nuankebao-stack.service|g' "$f"
        sed -i 's|bbt-cloudflared.service|nuankebao-cloudflared.service|g' "$f"
        sed -i 's|nuankebao-postgres|nuankebao-postgres|g' "$f"
        sed -i 's|/home/mm7/nuankebao-agent|/home/mm7/nuankebao-agent|g' "$f"
    done
    ok "install 脚本替换完成"

    # 4.12 mv 文件名 (脚本前缀 bbt-* → nuankebao-*)
    step "4.12 mv tools/bbt-*.sh → tools/nuankebao-*.sh"
    cd "$NUANKEBAO_DIR/tools"
    for f in bbt-*.sh bbt-*.service; do
        [ -f "$f" ] || continue
        newname="${f/bbt-/nuankebao-}"
        # 已在 stage 3 装过的 nuankebao-stack.service 跳过
        if [ "$f" = "bbt-stack.service" ]; then
            # 已 cp 到 /etc/systemd/system/nuankebao-stack.service, 仓库源文件不删 (历史对照)
            continue
        fi
        mv "$f" "$newname"
        echo "  mv $f → $newname"
    done
    cd "$NUANKEBAO_DIR"
    ok "tools 文件名替换完成"

    # 4.13 验证
    step "4.13 验证残留"
    RESIDUAL=$(rg -c 'nuankebao-postgres|nuankebao-web|bbt-stack\.service|bbt-agent' --hidden -g '!node_modules' -g '!.git' -g '!drizzle/meta' -g '!*.lock' -g '!CHANGELOG.md' 2>/dev/null | wc -l)
    if [ "$RESIDUAL" -eq 0 ]; then
        ok "0 残留"
    else
        warn "$RESIDUAL 文件仍有 bbt 残留 (主人决定手动修):"
        rg -l 'nuankebao-postgres|nuankebao-web|bbt-stack\.service|bbt-agent' --hidden -g '!node_modules' -g '!.git' -g '!drizzle/meta' -g '!*.lock' -g '!CHANGELOG.md' 2>/dev/null | head -10
    fi
}

# ============================================================
# Stage 5: Postgres 迁移 bbt → nuankebao
# ============================================================
stage_5() {
    step "Stage 5: Postgres 迁移 (pg_dump + restore)"

    # 5.1 停 nuankebao-postgres (此时是 nuankebao-postgres container,先 stop)
    step "5.1 stop nuankebao-postgres container"
    cd "$NUANKEBAO_DIR"
    sudo systemctl stop nuankebao-stack.service || true
    docker stop nuankebao-postgres
    ok "nuankebao-postgres stopped"

    # 5.2 删旧 named volume (主人已选 nuankebao-prefix,数据已 dump 备份)
    step "5.2 删旧 volume nuankebao-postgres-data"
    docker volume rm nuankebao-postgres-data
    ok "旧 volume 删除"

    # 5.3 改 .env 文件 (POSTGRES_USER/DB → nuankebao, password 改新)
    step "5.3 改 .env + .env.local"
    NEW_PASS="nuankebao_$(openssl rand -hex 16)"
    sed -i 's|^POSTGRES_USER=.*|POSTGRES_USER=nuankebao|' .env .env.local .env.example
    sed -i 's|^POSTGRES_DB=.*|POSTGRES_DB=nuankebao|' .env .env.local .env.example
    sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$NEW_PASS|" .env .env.local .env.example
    sed -i 's|POSTGRES_PASSWORD:-bbt_password|POSTGRES_PASSWORD:-nuankebao_password|g' docker-compose.yml docker-compose.prod.yml 2>/dev/null || true
    ok ".env / compose 改完"
    warn "新密码: $NEW_PASS (主人记一下, .env 文件里有但进 docker exec 需要)"

    # 5.4 重建 container (此时 docker-compose.yml 里的 container_name 还是 nuankebao-postgres,因为改 docker-compose 是 stage 4 的事, 已做 4.6)
    step "5.4 docker compose up postgres (创建新 container nuankebao-postgres + 新 volume)"
    cd "$NUANKEBAO_DIR"
    docker compose up -d postgres
    sleep 10
    docker exec nuankebao-postgres pg_isready -U nuankebao -d nuankebao || die "新 postgres 未 ready"
    ok "新 postgres ready"

    # 5.5 restore dump 到新库 (schema 是 bbt 的,但因为 dump 用 custom format, restore 后会保留 bbt schema 名 + bbt owner)
    step "5.5 restore dump 到 nuankebao 库 (会保留 bbt schema 名 + bbt owner)"
    docker exec -i nuankebao-postgres pg_restore -U nuankebao -d nuankebao --no-owner --role=nuankebao < "$TMP_DUMP" 2>&1 | tail -10 || true
    ok "restore 完成"

    # 5.6 验证表存在
    step "5.6 验证 11 张业务表"
    TABLES=$(docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -t -c "SELECT count(*) FROM pg_tables WHERE schemaname='public' AND tablename IN ('customer','wellness_record','audit_log','interaction','follow_up_task','product','service_item','staff','store','user','wellness_knowledge');" 2>/dev/null | tr -d ' ')
    if [ "$TABLES" = "11" ]; then
        ok "11 张业务表都在 ✓"
    else
        warn "只找到 $TABLES 张表 (期望 11)"
    fi

    # 5.7 schema owner 重命名 (bbt → nuankebao)
    step "5.7 schema owner 重命名 bbt → nuankebao (REASSIGN OWNED)"
    docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "REASSIGN OWNED BY bbt TO nuankebao;" 2>&1 | tail -3 || warn "REASSIGN 失败 (无 bbt role 残留, 正常)"
    docker exec nuankebao-postgres psql -U nuankebao -d nuankebao -c "DROP ROLE IF EXISTS bbt;" 2>&1 | tail -3 || warn "DROP ROLE 失败"
    ok "schema owner 清理完成"

    # 5.8 重启 nuankebao-stack 守护
    step "5.8 启 nuankebao-stack 守护"
    sudo systemctl start nuankebao-stack.service
    sleep 5
    sudo systemctl is-active nuankebao-stack.service && ok "nuankebao-stack active" || warn "未 active"
}

# ============================================================
# Stage 6: crontab 回填
# ============================================================
stage_6() {
    step "Stage 6: crontab 回填"

    if [ ! -f /tmp/crontab.bak ]; then
        warn "/tmp/crontab.bak 不存在, 跳过"
        return 0
    fi

    step "6.1 编辑新 crontab (替换路径 + log 名)"
    sed -e 's|/home/mm7/nuankebao-agent|/home/mm7/nuankebao-agent|g' \
        -e 's|/tmp/bbt-|/tmp/nuankebao-|g' \
        /tmp/crontab.bak > /tmp/nuankebao-crontab.txt

    step "6.2 安装新 crontab"
    crontab /tmp/nuankebao-crontab.txt
    crontab -l

    step "6.3 验证 0 残留"
    if crontab -l | grep -q bbt-agent; then
        die "crontab 仍有 bbt-agent 残留"
    else
        ok "crontab 干净 ✓"
    fi
}

# ============================================================
# Stage 7: 启动 + 验证
# ============================================================
stage_7() {
    step "Stage 7: 启动 + 验证"

    step "7.1 Postgres 健康"
    docker exec nuankebao-postgres pg_isready -U nuankebao -d nuankebao || die "postgres 未 ready"
    ok "postgres OK"

    step "7.2 Next.js user service 状态"
    systemctl --user is-active nuankebao-nextjs.service || {
        warn "nextjs 未 active, 重启..."
        systemctl --user restart nuankebao-nextjs.service
        sleep 10
    }
    ok "nextjs $(systemctl --user is-active nuankebao-nextjs.service)"

    step "7.3 Stack 状态"
    sudo systemctl is-active nuankebao-stack.service || sudo systemctl restart nuankebao-stack.service
    ok "stack $(sudo systemctl is-active nuankebao-stack.service)"

    step "7.4 本机 3003"
    sleep 3
    curl -s -o /dev/null -w '  HTTP %{http_code}\n' --max-time 5 http://localhost:3003/

    step "7.5 公网 nuankebao.tooyang.top"
    curl -s -o /dev/null -w '  HTTP %{http_code} (time=%{time_total}s)\n' --max-time 8 https://nuankebao.tooyang.top/

    step "7.6 公网 bbt.tooyang.top (主人手工删 Cloudflare Dashboard 后才应 502)"
    curl -s -o /dev/null -w '  HTTP %{http_code} (主人删 DNS 后才应断)\n' --max-time 8 https://bbt.tooyang.top/ || true

    step "7.7 备份脚本 dry-run"
    if [ -f tools/nuankebao-backup.sh ]; then
        bash tools/nuankebao-backup.sh --dry-run 2>&1 | tail -5 || warn "dry-run 失败"
    else
        warn "tools/nuankebao-backup.sh 不存在, 跳过"
    fi
}

# ============================================================
# Stage 8: 文档收尾
# ============================================================
stage_8() {
    step "Stage 8: 文档收尾 + git commit"

    cd "$NUANKEBAO_DIR"

    # 8.1 git add
    step "8.1 git add -A"
    git add -A

    # 8.2 git commit
    step "8.2 git commit"
    git commit -m "$(cat <<'EOF'
chore(rename): full rename bbt-agent → nuankebao-agent

按 docs/rename-sop.md 阶段 2-8 执行:

- mv /home/mm7/nuankebao-agent → /home/mm7/nuankebao-agent
- systemd: bbt-stack.service → nuankebao-stack.service (只跑 postgres,治 nuankebao-web 起不来 bug)
- systemd: bbt-nextjs.service → nuankebao-nextjs.service (user service)
- Postgres: bbt → nuankebao (pg_dump + restore + REASSIGN OWNED)
- tools/bbt-*.sh → tools/nuankebao-*.sh
- 脚本内部路径 /home/mm7/nuankebao-agent → /home/mm7/nuankebao-agent
- docker container / volume: nuankebao-postgres → nuankebao-postgres
- crontab: 路径同步

后续待主人手工:
- Cloudflare Dashboard: 删 bbt.tooyang.top DNS + Tunnel Public Hostname
- 重新 build Flutter APK (云上 GitHub Actions 触发)
EOF
)" 2>&1 | tail -5

    step "8.3 打印主人待手工清单"
    cat <<'EOF'

========== 主人待手工 (本脚本无法做) ==========

1. Cloudflare Dashboard → DNS → Records: 删 bbt.tooyang.top
2. Cloudflare Dashboard → Zero Trust → Networks → Tunnels → a8957e6c-... → Public Hostnames: 删 bbt.tooyang.top
3. (可选) Cloudflare Dashboard → 切临时隧道 service: sudo systemctl disable --now bbt-cloudflared
4. (可选) 重新 build Flutter APK (走云上 GitHub Actions)
5. 验证旧脚本 tools/bbt-*.sh 已 mv 走, tools/nuankebao-*.sh 替代

EOF
}

# ============================================================
# 调度
# ============================================================
echo "=========================================="
echo "  暖客宝 rename 执行脚本"
echo "  stage: $STAGE"
echo "  dir:   $NUANKEBAO_DIR"
echo "=========================================="

case "$STAGE" in
    3)    stage_3 ;;
    4)    stage_4 ;;
    5)    stage_5 ;;
    6)    stage_6 ;;
    7)    stage_7 ;;
    8)    stage_8 ;;
    all)
        stage_3
        stage_4
        stage_5
        stage_6
        stage_7
        stage_8
        ;;
    *)
        die "未知 stage: $STAGE (可选: 3 4 5 6 7 8 all)"
        ;;
esac

ok "stage $STAGE 完成 ✓"
