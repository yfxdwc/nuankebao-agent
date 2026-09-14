# ADR 索引 (Architecture Decision Records)

> **借鉴**: sales-ai 项目 [`docs/adr/INDEX.md`](https://github.com/sales-ai/sales-ai/blob/main/docs/adr/INDEX.md) 思路 (索引 + 决策摘要表).
> **格式**: Kebab-case 文件名, 编号递增. 每条 ADR 包含: 上下文 / 决策 / 候选评估 / 影响 / 风险.

---

## 索引 (按时间倒序, 最新在最上)

| # | 标题 | 状态 | 拍板日期 | 关键决策 |
|---|---|---|---|---|
| 0008 | [APK 域 + WEB 域功能清单与协作关系](./0008-apk-web-domain-spec.md) | ✅ Accepted | 2026-09-13 | 两域共存 (不是 dev↔prod 切换); 共享后端 API; WEB 域 production mode 永久 |
| 0007 | [底座 + 模块化插件架构](./0007-modular-architecture.md) | ✅ Accepted | 2026-09-13 | APK 域分 `core/` 底座 + `modules/` 业务模块; WEB 域 `dev-modules/` 文档化视图; ★ RelationSystem 接口 |
| 0006 | (预留) | — | — | — |
| 0005 | [Mobile-Only 阶段 (web admin freeze-keep + flutter-only-sync)](./0005-mobile-only-phase.md) | ✅ Accepted | 2026-09-07 | web admin 冻结, 仅 P0 fix; backend 改动只同步 Flutter service |
| 0004 | [Schema 演进红线](./0004-schema-evolution.md) | ✅ Accepted | 2026-09-05 | 6 个绝对禁止的 migration 模式 (DROP/RENAME/ALTER TYPE 无 USING 等); CI `tools/check-migration-compat.sh` |
| 0003 | [Flutter 开发工作流](./0003-flutter-dev-workflow.md) | ✅ Accepted | 2026-09-04 | Flutter + Android Studio + USB 真机 + 自动 hot reload |
| 0002 | [数据模型](./0002-data-model.md) | ✅ Accepted | 2026-09-03 | 13 表 + 字段加密 (pgcrypto) + 5 审计触发器 |
| 0001 | [技术栈选型](./0001-tech-stack.md) | ✅ Accepted | 2026-09-03 | Next.js 15 + shadcn/ui + Tailwind + Drizzle + Auth.js v5 + Flutter 3.24 |

---

## 阶段分类

### 元架构 / 项目宪章 (影响全局)
- **ADR-0007**: 双域 + 底座 + 模块化 (v0.1.3 架构基石)
- **ADR-0008**: APK + WEB 双域功能清单与协作关系 (v0.1.4 双域细化)

### 阶段策略 (影响开发模式)
- **ADR-0005**: Mobile-Only 阶段 (封闭 web admin)
- **ADR-0003**: Flutter 开发工作流

### 技术选型 / 数据
- **ADR-0001**: 技术栈
- **ADR-0002**: 数据模型
- **ADR-0004**: Schema 演进红线

---

## ADR 起草指南

新 ADR 必须:
1. 编号递增 (下一个 = `0009-...md`)
2. 文件名 kebab-case
3. 包含 7 个标准节: 上下文 / 决策 / 候选评估 / 影响 / 风险 / 关联文档 / 元数据
4. 元宪法引用: `本决策对应元宪法 [CHARTER §X](../CHARTER.md)`
5. 在本 INDEX.md 加一行 (按时间倒序插到顶部)
6. 主人拍板后才标 ✅ Accepted (未拍板 = ⏳ Draft)
