# project-skill — 项目 Skill 模块

> **职责**: 项目专属的 pi / agent Skill (操作层规约 + pi 扩展 + muse skill)
> **物理位置**: `AGENTS.md` + `.pi/settings.json` + `.pi/extensions/` + `.muse/skills/`
> **入口**: 主人启动 pi session 自动加载 (per `.pi/settings.json` 配置)

## 当前实现

### `AGENTS.md` (操作层规约, 250+ 行)

项目协作约定, 给 pi / Codex / 任何 agent 读:
- §1 vibe (CHARTER §1 宗旨)
- §2 技术栈 (CHARTER §3.2)
- §3 pi 协作规则 (强制 + 禁止)
- §4 文件组织约定 (v0.1.3 底座 + 模块化插件)
- §5 反模式 (踩过的坑)
- §6 命名一致性 (all-nuankebao)
- §7 当前进度 (路线图)
- §8 task-snapshot SOP

**引用约定**: 每个 `## §X` 标题后标注 `(CHARTER §Y)`, 对齐元宪法.

### `.pi/settings.json` (pi 配置)

```json
{
  "extensions": ["./.pi/extensions/auto-task-snapshot.ts"],
  "model": "minimax/minimax-m3",
  ...
}
```

### `.pi/extensions/auto-task-snapshot.ts` (pi 扩展, TypeScript)

自动触发 task-snapshot 的 pi 扩展:
- 监听 user 消息
- 检测 "改动 ≥3 文件" 或 "跨域" 信号
- 自动调 `bash scripts/task-snapshot.sh start <task-name>`

### `.muse/skills/` (muse skill, 历史)

主人机器的 ~/.muse/skills/ 下的 skill (canonical 文档源):
- `dev-domain-backup` (备份 SOP, v1.0)
- `scaffold-task-snapshot` (task-snapshot skill, canonical 文档)
- 其他主人手工加的 skill

**注意**: `.muse/skills/` 是**主人机器全局**, 不在仓库内. 引用时写 `~/.muse/skills/<name>/SKILL.md`.

## 扩展指南

**新增 §X 到 AGENTS.md** (e.g. §9 部署 SOP):
1. 主人 ask_user 拍板 (L2 操作决策, agent 自治可不问, 但建议问)
2. 在 AGENTS.md 加 `## §9. <标题>` + 引用 `(CHARTER §Y)`
3. 同步更新 AGENTS.md 索引 (如有)

**新增 pi 扩展** (e.g. 自动 lint 检查):
1. 在 `.pi/extensions/<name>.ts` 新建 TypeScript 文件
2. 在 `.pi/settings.json` 加 `extensions: [..., "./.pi/extensions/<name>.ts"]`
3. README / 注释说明触发条件

**新增 muse skill**:
- skill 是**主人的工具**, 不在仓库内
- 在 `~/.muse/skills/<name>/SKILL.md` 新建
- nuankebao 项目可通过 AGENTS.md 引用 (`~/.muse/skills/<name>/SKILL.md`)

## 与 CHARTER 关系

| 文档 | 角色 | 谁改 |
|---|---|---|
| `docs/CHARTER.md` | L0 元层 (治理哲学 / 红线) | 主人拍板 |
| `AGENTS.md` | L2 操作层 (具体怎么做) | agent 写, 主人审 |
| `.pi/settings.json` | pi session 配置 | 主人拍 (session 级) |
| `.muse/skills/*/SKILL.md` | 主人机器全局 skill | 主人手工 |

**修改顺序**: 主人先改 CHARTER → 同步改 AGENTS / pi settings / muse skill.

## 相关 SOP

- [CHARTER.md §8 文档维护责任](../../CHARTER.md) + §9 操作层引用约定
- [AGENTS.md §3 协作规则](../../AGENTS.md)
- pi 文档 (主人 ~/.pi/ 下的 pi 配置)

## 待办

- [ ] AGENTS.md 章节自动生成 (从 CHARTER 推导)
- [ ] pi extension 加更多 hook (lint / type check / commit msg 检查)
- [ ] muse skill 加 "phase-snapshot" (自动为每个 phase 打 tag)
