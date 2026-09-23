#!/bin/bash
# scripts/task-snapshot.sh — 任务级快照 (W8 治本)
#
# 借鉴自 sales-ai 项目 scripts/task-snapshot.sh (AGENTS.md 原则 8: 借鉴思路不复制代码;
# 但本脚本本身是 mechanical 镜像 + nuankebao 适配, 不重写 — 跟 sales-ai 版本几乎 1:1,
# 差异仅在 systemd glob + 顶部注释. 后续如果 sales-ai 改了 dirty backup / rollback
# 兜底逻辑, 主人可手动 sync; 或同步反映到 ~/.muse/skills/scaffold-task-snapshot/SKILL.md).
#
# 复用 git 作为快照系统. 不引入新存储, 不引入新进程.
# 工作流: 任务开始 -> start; 出错 -> rollback (秒级).
#
# 用法:
#   scripts/task-snapshot.sh start <task-name>
#       捕获当前工作树 -> commit + tag pre-<name>-<sha>
#       ⚠ 只捕获**已跟踪文件的改动** (git add -u); untracked **不进 commit**,
#         但完整 dump 在 .git/snapshots/<tag>.diff (见下方 nuankebao 适配 ③)
#   scripts/task-snapshot.sh list
#       最近 10 个任务快照 (序号/标签/绝对时间/相对时间/commit 标题)
#   scripts/task-snapshot.sh find <time-spec>
#       列出指定时间之后的任务快照 + commits
#       时间规范: yesterday, 2 days ago, 2026-08-12, '2026-08-12 15:00'
#   scripts/task-snapshot.sh diff <tag-or-prefix>
#       预览: HEAD vs 指定 tag 的 diff stat + commit 列表
#   scripts/task-snapshot.sh rollback <tag-or-prefix>
#       回滚: 先 stash 当前未提交状态保命, 再 git checkout, 重启 systemd
#
# 设计取舍:
#   - --no-verify 跳过 pre-commit hook: 这是元提交, 不该被 CHARTER 阻拦
#   - --allow-empty: 即使没改动也能打 tag (dirty 已被 .git/snapshots/ 备份, 见 ADR 0020 D2)
#   - 不删旧 tag: 让 git reflog + tag 历史当"自然保留策略" (90+ 天可用)
#   - 重启 systemd 用 sudo, 失败不阻断 (可能服务根本没启)
#
# ADR 0020 caveat — 实际覆盖范围 (2026-08-15 改; 2026-09-23 nuankebao 改):
#   - 在工作树 dirty 时, snapshot commit 是否捕获改动, 依赖 git 的 `git add -u` 是否被任何
#     `filter.<driver>.process` (例如 git-lfs) 跳过; 全局 git config 下可能 silent skip.
#   - 作为兜底, dirty 改动一定被 dump 到 `.git/snapshots/<tag>.diff` (含 untracked).
#   - rollback 在 checkout 之后检查 working tree 仍 dirty 时, 自动 `git apply` 该 diff.
#   - 不要在未读 .git/snapshots/<tag>.diff 之前回滚; 这是 §7.3 失败反馈要求的兜底.
#
# 与 deploy/code_snapshot.sh (每日全量 tar) 职责互补:
#   - 全量快照: 灾难恢复 (硬盘挂/系统炸)
#   - 任务快照: 开发回滚 (agent 改错/想撤销任务)
#
# 见 AGENTS.md §8.1 + ~/.muse/skills/scaffold-task-snapshot/SKILL.md (canonical 文档源).
#
# nuankebao 适配 (2026-09-13):
#   - 移除 `source _lib.sh`: task-snapshot.sh 全文不引用 _lib 变量 (grep 验证),
#     sales-ai 的 _lib.sh 是 project-specific (硬编码 SALES_AI_HOME 等), 不复制
#   - systemd glob: sales-ai-*.service → nuankebao-*.service (见下方 SERVICES 段)

set -uo pipefail

# PROJECT: 从当前 git 仓库自动推断 (替代 v4.2.0 之前的 hardcoded ${SALES_AI_HOME}).
# 必须 git 仓库 — 脚本要打 tag + commit, 非 git 环境是设计错误.
PROJECT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$PROJECT" ]; then
    echo "❌ 不在 git 仓库内, task-snapshot 必须 git init 后才能用" >&2
    echo "   (脚本设计: 复用 git tag 作为快照, 见 ADR 0020)" >&2
    exit 1
fi
cd "$PROJECT" || { echo "❌ 无法 cd $PROJECT" >&2; exit 1; }

# SERVICES: 动态从 systemd --user unit list 读 sales-ai-* service.
# 替代 v4.2.0 之前的 hardcoded mm7-sales-ai-* (LK 用 mm7- 前缀, TC 不用).
# 这样 LK / TC / 任何其他部署方式都自动适配, 不依赖具体 service 名.
# nuankebao 适配 (2026-09-13 借鉴自 sales-ai/scripts/task-snapshot.sh, 改动最小):
#   1. glob: sales-ai-*.service → nuankebao-*.service (对齐主人机器 service 命名, 见 AGENTS.md §6.1)
#   2. 保留 --user (nuankebao deploy/systemd/*.service 设计为 user-level; 见 deploy/README.md §10.4)
#   3. 当前 dev 机器 systemd --user 实际有的 nuankebao service: nuankebao-nextjs.service (部署栈启了才更多)
#
# nuankebao 适配 (2026-09-23, 主人拍板): `start` 的 `git add -A` → **`git add -u`**
#   背景: 本仓经常**多个 pi/codex session 同时在同一工作目录**干活, 而 `git add -A`
#     会把**别人新加的 untracked 文件**一并 stage + commit → 别人的在制品被扫进
#     本次快照 commit (实测发生过: 把另一 session 的 /admin/plam 未提交改动扫进别人 commit)。
#   改法: 只暂存**已跟踪文件的改动/删除** (`-u` = --update, 天然忽略 untracked)。
#     untracked 不丢失 —— 它们在 `start` 开头已完整 dump 到
#     `.git/snapshots/<tag>.diff` (逐文件内容都写进去了)。
#   ⚠ 代价 (已知取舍, 不是 bug): **任务开始时就存在的 untracked 文件, 若任务中被删掉,
#     `rollback` 不会自动恢复它** (它不在 tag 指向的 commit 里, 而 checkout 后工作树
#     与 HEAD 一致 → 不会触发动 diff 兜底)。要恢复就去
#     `.git/snapshots/<tag>.diff` 里捞 (rollback 会把路径打出来)。
#   为什么接受这个代价: "扫走别人在制品"是**不可逆的数据事故**(别人的新文件被提交进
#     你的 commit, 且 message 与内容无关); 而"任务中删掉一个 task-start 就存在的
#     untracked 文件且需要回滚恢复"是**极罕**且**有 dump 可手捞**的场景。
SERVICES=($(systemctl --user list-unit-files 'nuankebao-*.service' --no-legend 2>/dev/null \
    | awk '{print $1}' \
    | sed 's/\.service$//'))
# 兜底: 如果 systemd 读不到 (e.g. 容器环境 / CI), 用 git config 推断
# 主人可手动: git config task-snapshot.services "nuankebao-nextjs.service nuankebao-stack.service"
if [ ${#SERVICES[@]} -eq 0 ]; then
    SERVICES=($(git config --get-all task-snapshot.services 2>/dev/null))
fi
# 兜底 2: 完全没配置就空数组, rollback 会跳过 restart (只是 warning, 不阻断)

usage() {
    sed -n '2,/^set -/p' "$0" | grep -v '^#!' | sed 's/^# \?//'
}

action="${1:-help}"
name="${2:-}"

case "$action" in
    start)
        [ -z "$name" ] && { echo "❌ 用法: $0 start <task-name>" >&2; exit 1; }
        if ! echo "$name" | grep -qE '^[a-zA-Z0-9._-]+$'; then
            echo "❌ task-name 仅允许 [a-zA-Z0-9._-]" >&2
            exit 1
        fi
        # === ADR 0020: dirty 备份兜底 (D2) ===
        # 在某些 git config (e.g. global git-lfs filter.process) 下, git add -A 可能让 dirty 跳过.
        # 为了让 rollback 真正可回 (即 dirty 改动也回), 先 dump working tree diff 到 .git/snapshots/<tag>.diff.
        # 备份失败也不阻断主路径 (只记 warning).
        mkdir -p .git/snapshots
        dirty_diff=$(git -c core.attributesfile=/dev/null diff --cached HEAD 2>/dev/null || true)
        untracked_list=$(git -c core.attributesfile=/dev/null ls-files --others --exclude-standard 2>/dev/null || true)
        snap_diff=".git/snapshots/pre-${name}-PLACEHOLDER.diff"
        if [ -n "$dirty_diff" ] || [ -n "$untracked_list" ]; then
            {
                echo "# Working tree snapshot diff (created $(date -Iseconds))"
                echo "# tag 即将生成; 占位符 PLACEHOLDER 会在下面被替换."
                echo ""
                [ -n "$dirty_diff" ] && printf '%s\n' "$dirty_diff"
                if [ -n "$untracked_list" ]; then
                    echo "=== untracked files ==="
                    echo "$untracked_list" | while IFS= read -r f; do
                        [ -z "$f" ] && continue
                        printf '\n--- /dev/null\n+++ b/%s\n' "$f"
                        cat -- "$f" 2>/dev/null || echo "(binary or unreadable: $f)"
                    done
                fi
            } > "$snap_diff" || echo "⚠️  dirty 备份失败 (不影响 snapshot, 仅 rollback 时无 diff 兜底)" >&2
        fi

        # 捕获已跟踪文件的改动/删除 (**不用 `git add -A`**) ——
        #   -A 会把 untracked 一并 stage: 本仓多 session 同工作目录时,
        #   会把**别人新加的文件**扫进本次快照 commit (实测事故, 见文件头 nuankebao 适配 ③)。
        #   untracked 不会丢: 上面已完整 dump 到 .git/snapshots/<tag>.diff。
        git add -u
        # --no-verify: 元提交, 跳过 pre-commit CHARTER 检查
        # --allow-empty: 即使没改动也能打 tag (dirty 已被 .git/snapshots/ 备份)
        git commit --no-verify --allow-empty \
            -m "[SNAPSHOT] task-start: ${name}" >/dev/null
        sha=$(git rev-parse --short HEAD)
        tag="pre-${name}-${sha}"
        git tag "$tag"

        # 把占位符 PLACEHOLDER 替换为真 tag.
        if [ -f "$snap_diff" ]; then
            mv "$snap_diff" ".git/snapshots/${tag}.diff" 2>/dev/null || true
        fi

        echo "✅ 任务快照: ${tag}"
        echo "   HEAD:   $(git rev-parse --short HEAD)"
        # 工作树干净时 $tag.diff 根本不存在; wc -c < 不存在的文件即使 2>/dev/null 也会报 bash 内部错.
        # 先 [ -f ] 检查, 避免 "行 N: ...: 没有那个文件或目录" 噪音.
        if [ -f ".git/snapshots/${tag}.diff" ]; then
            dirty_size=$(wc -c < ".git/snapshots/${tag}.diff")
        else
            dirty_size=0
        fi
        echo "   dirty 备份: .git/snapshots/${tag}.diff (${dirty_size} bytes)"
        echo "   回滚:   $0 rollback ${name}"
        echo "   预览:   $0 diff ${name}"
        ;;
    list)
        echo "=== 最近 10 个任务快照 (按创建时间倒序) ==="
        printf "  %s  %-44s  %-16s  %-12s  %s\n" "#" "tag" "created" "(相对)" "subject"
        git for-each-ref --sort=-creatordate \
            --format='%(refname:short)|%(creatordate:format:%Y-%m-%d %H:%M)|%(creatordate:relative)|%(subject)' \
            refs/tags/ \
          | grep '^pre-' | head -10 \
          | awk -F'|' '{printf "  %2d  %-44s  %-16s  %-12s  %s\n", NR, $1, $2, $3, $4}'
        echo ""
        echo "提示: $0 find <时间> 按时间筛选 (e.g. find '2 days ago', find '2026-08-12')"
        ;;
    find)
        # find <time-spec> — 列出指定时间之后的任务快照 + commits
        # 时间规范同 date -d: yesterday, 2 days ago, 2026-08-12, '2026-08-12 15:00'
        [ -z "$name" ] && { echo "用法: $0 find <time-spec>" >&2; echo "  例: $0 find yesterday" >&2; echo "  例: $0 find '2 days ago'" >&2; echo "  例: $0 find '2026-08-12 15:00'" >&2; exit 1; }
        cutoff=$(date -d "$name" +%s 2>/dev/null) || true
        # 特殊处理: today/yesterday 默认从 0:00 开始 (date -d "today" 返回当前时刻, 不符合直觉)
        case "$name" in
            today)    cutoff=$(date -d "today 0:00" +%s) ;;
            yesterday) cutoff=$(date -d "yesterday 0:00" +%s) ;;
        esac
        [ -n "$cutoff" ] || {
            echo "❌ 无法解析时间: '$name'" >&2
            echo "   支持: yesterday | 2 days ago | 2026-08-12 | '2026-08-12 15:00'" >&2
            exit 1
        }
        echo "=== 活动 since [$name] ==="
        echo ""
        echo "--- task snapshots (created >= $name) ---"
        git for-each-ref --sort=-creatordate \
            --format='%(creatordate:unix)|%(refname:short)|%(subject)' \
            refs/tags/ \
          | grep '|pre-' \
          | awk -F'|' -v c="$cutoff" '$1 >= c {
              printf "  %s  %-44s  %s\n", strftime("%Y-%m-%d %H:%M", $1), $2, $3
            }'
        echo ""
        echo "--- commits (git log --since=$name, 最多 30 条) ---"
        git log --oneline --pretty=format:'%h %ad %s' --date=short --since="$name" -30
        echo ""
        echo ""
        echo "找到目标 snapshot 后:"
        echo "  $0 diff <tag-or-prefix>      # 预览会改什么"
        echo "  $0 rollback <tag-or-prefix>  # 真正回滚"
        ;;
    diff)
        [ -z "$name" ] && { echo "❌ 用法: $0 diff <tag-or-prefix>" >&2; exit 1; }
        # 精确匹配优先, 前缀匹配兜底
        full=$(git tag -l "pre-*" | grep -Fx "$name")
        [ -z "$full" ] && full=$(git tag -l "pre-*" | grep -F "$name" | head -1)
        [ -z "$full" ] && { echo "❌ 找不到 tag: ${name}" >&2; exit 1; }
        echo "=== diff stat (HEAD vs ${full}) ==="
        git diff --stat "${full}..HEAD"
        echo ""
        echo "=== commit 列表 ==="
        git log --oneline "${full}..HEAD"
        ;;
    rollback)
        [ -z "$name" ] && { echo "❌ 用法: $0 rollback <tag-or-prefix>" >&2; exit 1; }
        # 精确匹配优先, 前缀匹配兜底
        full=$(git tag -l "pre-*" | grep -Fx "$name")
        [ -z "$full" ] && full=$(git tag -l "pre-*" | grep -F "$name" | head -1)
        [ -z "$full" ] && { echo "❌ 找不到 tag: ${name}" >&2; $0 list >&2; exit 1; }
        echo "⚠️  即将回滚到: ${full}"
        # 保命: stash 当前未提交状态 (含 untracked)
        if ! git diff --quiet HEAD 2>/dev/null || [ -n "$(git ls-files --others --exclude-standard)" ]; then
            stash_name="auto-stash-rollback-$(date +%s)"
            git stash push -u -m "$stash_name" >/dev/null
            echo "   💾 当前状态已 stash: ${stash_name}"
        fi
        git checkout "$full" 2>&1 | tail -3
        # === ADR 0020: dirty 备份兜底 (D3) ===
        # checkout 之后, working tree 可能仍带未被回滚的 dirty (例如源头 commit 就是空).
        # 此时 patch 应用 .git/snapshots/<tag>.diff 来兜底. 仅在 diff 存在且 working tree 与 tag HEAD 仍不一致时触发.
        snap_diff=".git/snapshots/${full}.diff"
        if [ -f "$snap_diff" ] && ! git diff --quiet HEAD 2>/dev/null; then
            echo "   🩹 检测到工作树 dirty 未被 commit 覆盖, 应用 .git/snapshots/${full}.diff 兜底回滚..."
            if git apply --check "$snap_diff" 2>/dev/null; then
                git apply "$snap_diff"
                echo "   ✅ dirty 兜底回滚完成"
            elif git apply --check --reverse "$snap_diff" 2>/dev/null; then
                echo "   ⏭️  diff 与 working tree 已一致, 无需兜底"
            else
                echo "   ⚠️  diff 应用失败 (可能有冲突), 请手动: less ${snap_diff}"
            fi
        fi
        # === untracked 提示 (2026-09-23 nuankebao 适配 ③) ===
        # start 现在用 `git add -u` —— **untracked 不进 commit**(避免扫走别的 session 的新文件),
        # 所以任务中若删过"快照时就存在的 untracked 文件", 这里不会自动恢复它
        # (checkout 后工作树与 HEAD 一致 → 不会触发上面的 diff 兜底)。
        # 别让人干着急: 直接把备份路径打出来。
        if [ -f "$snap_diff" ] && grep -q '^=== untracked files ===' "$snap_diff" 2>/dev/null; then
            echo "   ℹ️  快照含 untracked 文件 —— 它们**不在 commit 里**, 备份在: ${snap_diff}"
            echo "      (若任务中删过其中某个, 需要手动从该文件的 '=== untracked files ===' 段抄回来)"
        fi
        for svc in "${SERVICES[@]}"; do
            if sudo systemctl restart "$svc" 2>/dev/null; then
                echo "   🔄 重启 ${svc}"
            else
                echo "   ⏭️  ${svc} 未启动 (跳过)"
            fi
        done
        echo "✅ 回滚完成, HEAD: $(git rev-parse --short HEAD)"
        echo "   验证: curl -fs http://localhost:3001/health"
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        echo "❌ 未知 action: ${action}" >&2
        usage >&2
        exit 1
        ;;
esac
