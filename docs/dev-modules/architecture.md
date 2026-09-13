# architecture — 架构图模块

> **职责**: 项目架构图 (域边界 / 模块依赖 / 数据流) 的文档化与自动生成
> **物理位置**: `docs/CHARTER.md` §4 (v0.1.3 文字版架构图) + 架构图生成脚本 (TBD)
> **入口**: `cat docs/CHARTER.md` 读 §4.1 总架构图

## 当前实现

### `docs/CHARTER.md` §4.1 总架构图 (v0.1.3)

文字版 ASCII 架构图 (双域 + 底座 + 模块化插件):

```
┌────────────────────────── APK 域 (主产品) ──────────────────────────┐
│  ┌─ APK 底座 (flutter_app/lib/core/: 不可替换) ────────────────┐   │
│  │  router / providers / http / theme / models / widgets        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ↑ 复用                                │
│  ┌─ 业务模块 (flutter_app/lib/modules/: 可独立替换/改进) ─────┐    │
│  │  • auth / customer / wellness / follow_up                    │    │
│  │  • presentation (graph + list 合并)                          │    │
│  │  • relation ★ (客户/加盟关系 — 接口 + 默认实现)               │    │
│  │  • meeting (占位)                                            │    │
│  └──────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘

┌────────────────────────── WEB 域 (脚手架) ──────────────────────────┐
│  ┌─ WEB 底座 (Next.js 15 + shadcn + Tailwind + Route Handlers) ─┐  │
│  │  App Router + shadcn/ui + Tailwind + Drizzle API + Auth.js    │  │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌─ 开发域模块 (docs/dev-modules/: 文档化视图, 物理位置不动) ───┐  │
│  │  • task-snapshot / references / ui-kit                       │  │
│  │  • project-skill / architecture                              │  │
│  │  • flutter-preview / deploy                                  │  │
│  └──────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

### 架构图自动生成脚本 (TBD, 待实施)

**当前是文字版 ASCII**, 未来可能:
- 用 mermaid (`docs/architecture.mmd`) 渲染成 SVG/PNG
- 用 structurizr DSL (`.dsl` 文件) → 自动生成 C4 图
- 嵌入到 README / docs/

## 扩展指南

**新增架构图** (e.g. 数据流图):
1. 在 `docs/architecture/` 下新建 `<name>.md` 或 `<name>.mmd`
2. 主人 review 后同步到 CHARTER §4 引用

**升级为图形版**:
- 评估: mermaid (易维护) vs structurizr (专业) vs draw.io (灵活)
- 主人 ask_user 拍板
- 保持文字版 ASCII 作为 fallback (CLI 友好)

**架构变更流程**:
1. 主人拍板 (L1 战略决策)
2. 写 ADR (docs/adr/<N>.md)
3. 改 CHARTER §4 (升版本号)
4. 改 AGENTS §4 (文件组织)
5. 同步改 docs/dev-modules/architecture.md (本文件)

## 与其他 dev-modules 的关系

- **dev-modules/project-skill/** — 引用本文件的架构图 (e.g. AGENTS §4 提到架构图)
- **dev-modules/task-snapshot/** — 架构变更前必 snapshot
- **dev-modules/references/** — 借鉴其他项目的架构 (NocoBase / Twenty / Frappe)

## 相关 SOP

- [CHARTER.md §4 域划分](../../CHARTER.md) (v0.1.3 架构图所在)
- [ADR-0007 底座 + 模块化插件架构](../adr/0007-modular-architecture.md) (本架构的决策记录)
- mermaid 文档: <https://mermaid.js.org/> (未来选型)

## 待办

- [ ] 评估 mermaid vs structurizr (W6 内测后)
- [ ] 写架构图自动生成脚本 (per ADR-0007 §4.4 "实际边界图")
- [ ] 把当前 ASCII 改成 mermaid (验证可读性)
- [ ] 加数据流图 (e.g. 客户录入流程)
