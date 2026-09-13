# docs/dev-modules/ — WEB 开发域模块清单

> **架构定位** (per [ADR-0007](../../adr/0007-modular-architecture.md) §3 + AGENTS §4.5): 暖客宝 WEB 域是**开发项目 APK 用的脚手架** (不是产品).
> 本目录是 WEB 域**开发模块的文档化视图**, 物理位置散落在 scripts/ + docs/ + .pi/ + tools/ + deploy/, **不强制迁移**.

## 7 个开发域模块 (按主人 2026-09-13 ask_user 拍板)

| # | 模块 | 物理位置 | README |
|---|---|---|---|
| 1 | **task-snapshot** — 任务快照 | `scripts/task-snapshot.sh` + `.pi/extensions/auto-task-snapshot.ts` | [task-snapshot.md](./task-snapshot.md) |
| 2 | **references** — 同类项目借鉴关注 | `docs/references.md` + 外部项目监控 SOP | [references.md](./references.md) |
| 3 | **ui-kit** — UI 方案 | `src/components/ui/` + `tailwind.config.ts` | [ui-kit.md](./ui-kit.md) |
| 4 | **project-skill** — 项目 Skill | `AGENTS.md` + `.pi/settings.json` + `.muse/skills/` | [project-skill.md](./project-skill.md) |
| 5 | **architecture** — 架构图 | `docs/CHARTER.md` §4 + 架构图生成脚本 (TBD) | [architecture.md](./architecture.md) |
| 6 | **flutter-preview** — APK 预览脚手架 | `src/app/{app-preview,preview}/` + `src/components/preview/` | [flutter-preview.md](./flutter-preview.md) |
| 7 | **deploy** — 部署脚本 | `tools/` + `deploy/` + systemd units | [deploy.md](./deploy.md) |

## 模块化约束 (per AGENTS §4.5)

- ✅ **模块清单已锁定** (7 个): 上表就是 v0.1.3 终态, 主人拍板
- ✅ **新增模块时**: 同步 `docs/dev-modules/<name>.md` README + 更新本索引
- ⚠ **物理位置**: 维持现状 (`scripts/` + `docs/` + `.pi/` + `tools/` + `deploy/`), 不强制迁移

## 设计原则

**文档化视图 vs 物理目录**:
- WEB 域的物理目录已经按功能约定组织 (`scripts/` 是脚本, `tools/` 是工具, `.pi/` 是 pi 扩展)
- **不**创建新物理目录, 避免破坏现有约定
- `docs/dev-modules/*.md` 作为"软约束视图", 让新人/agent 快速找到"WEB 域有哪些开发模块"

**借鉴 vs 重新实现** (per AGENTS §2 原则 8):
- 大部分 WEB 域模块借鉴自 [sales-ai 项目](https://github.com/sales-ai/sales-ai) 的同款结构
- 但**重新实现** + **注明出处**, 不直接 fork

## 与 APK 域对比

| 维度 | APK 域 | WEB 域 (开发脚手架) |
|---|---|---|
| **定位** | 主产品 (销售员用) | 开发项目用的脚手架 (主人/agent 用) |
| **物理位置** | `flutter_app/lib/{core,modules}/` | `scripts/` + `src/` + `.pi/` + `tools/` + `deploy/` |
| **模块组织** | 物理目录 (强制) | 文档化视图 (软约束) |
| **为什么不同** | Flutter 包结构鼓励按模块 | 现有约定已稳定 (scripts/tools/.pi), 物理迁移风险大 |

## 维护 SOP

**新增开发模块**:
1. 主人 ask_user 拍板 (L1 战略决策, per CHARTER §5)
2. 在 `docs/dev-modules/<name>.md` 新建 README (按下面模板)
3. 更新本 README 索引
4. 在 CHANGELOG 加 `[X.Y.Z]` 条目

**改进现有模块**:
- 模块改动不动其他模块 (类似 APK 域的模块独立)
- 重大改进写 ADR (L1 战略决策)

**废弃模块**:
- README 加 `> ⚠ DEPRECATED: <替代方案>` 标记
- 物理位置保留 1 周观察期 (类似 flutter `_deprecated/`), 然后真删

## README 模板

每个模块 README 按下面结构写:

```markdown
# <模块名>

**职责**: <一句话>
**物理位置**: <文件路径>
**入口**: <主要脚本/类/页面>

## 当前实现
- <关键文件 1>: <作用>
- <关键文件 2>: <作用>

## 扩展指南
<如何添加新功能 / 替换实现>

## 相关 SOP
<链接到 docs/ 下其他 SOP>
```

## 关联文档

- [CHARTER §4.3 模块化规则 WEB 域](../../../docs/CHARTER.md#43-模块化规则-v013-新增)
- [AGENTS §4.5 模块化约束 WEB 域](../../../AGENTS.md#45-模块化约束-charter-43-模块化规则)
- [ADR-0007 §3. WEB 域文档化视图](../../../docs/adr/0007-modular-architecture.md)
