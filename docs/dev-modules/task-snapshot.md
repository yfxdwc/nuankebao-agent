# task-snapshot — 任务快照模块

> **职责**: 任务级 git 快照 + 自动 rollback (借鉴 [sales-ai](https://github.com/sales-ai/sales-ai) scripts/task-snapshot.sh, 思路一致 + 项目适配)
> **物理位置**: `scripts/task-snapshot.sh` + `.pi/extensions/auto-task-snapshot.ts`
> **入口**: `bash scripts/task-snapshot.sh <start|list|find|diff|rollback> <name>`

## 当前实现

### `scripts/task-snapshot.sh` (核心脚本, 200+ 行 bash)

5 个 action:
- `start <name>` — 捕获当前完整工作树 → commit + tag `pre-<name>-<sha>`, 备份 dirty → `.git/snapshots/<tag>.diff`
- `list` — 最近 10 个任务快照 (按 tag 创建时间倒序)
- `find <time-spec>` — 时间筛选 (e.g. `find yesterday`, `find '2 days ago'`, `find '2026-08-12'`)
- `diff <tag-or-prefix>` — 预览 HEAD vs tag 的 diff stat + commit 列表
- `rollback <tag-or-prefix>` — 真回滚 (先 stash 当前状态保命, git checkout, 应用 .git/snapshots/<tag>.diff 兜底, 重启 systemd)

**关键设计**:
- `--no-verify`: 元提交跳过 pre-commit CHARTER 检查
- `--allow-empty`: 即使没改动也能打 tag
- 不删旧 tag: git reflog + tag 历史当"自然保留策略" (90+ 天可用)
- 重启 systemd 用 sudo, 失败不阻断

### `.pi/extensions/auto-task-snapshot.ts` (自动触发)

PI WEB 扩展: 在每条 user 消息时, 检测 "改动 ≥3 文件" 或 "跨域", 自动调 task-snapshot.sh start.

主人在第一条 user 消息时, 自动 snapshot, 不用手敲命令.

### `.git/snapshots/` (备份目录)

脏状态兜底: 如果全局 git-lfs filter.process 让 git add -A silent skip, dirty 改动仍被 dump 到 `.git/snapshots/<tag>.diff` (含 untracked).

rollback 时, 如果 working tree 与 tag HEAD 仍不一致, 自动 `git apply` 该 diff.

## 扩展指南

**新增 action** (e.g. `merge <branch>`):
1. 在 `scripts/task-snapshot.sh` 加 case 分支
2. README 更新

**更换 git 底层** (e.g. 用 jj / sapling):
- 重新实现 start/list/diff/rollback
- 保持 CLI 接口兼容 (其他脚本依赖)

**与 pi agent 集成**:
- 当前 `.pi/extensions/auto-task-snapshot.ts` 是 hooks 风格 (监听 user 消息)
- 可扩展: 检测 agent 完成一轮修改后自动 snapshot (在 assistant 消息时)

## 配套规范 (per AGENTS §3 + §8.1)

- ✅ **改/加 ≥3 文件 或 跨域** → 强制先 snapshot
- ✅ **第一步 user 消息** → auto-snapshot (扩展自动)
- ⚠ **rollback 前** → 先 `diff <tag>` 看会改什么, 不要裸 rollback
- ❌ **不要**删 `.git/snapshots/` 目录 (脏状态兜底)

## 相关 SOP

- AGENTS.md §3 (协作规则) + §8.1 (snapshot SOP)
- sales-ai 项目 [task-snapshot.sh](https://github.com/sales-ai/sales-ai) (借鉴源)
- scripts/task-snapshot.sh 顶部注释 + ADR-0020 引用
