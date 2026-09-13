# references — 同类项目借鉴关注模块

> **职责**: 学习借鉴成熟项目的设计思路, 避免重复造轮子
> **物理位置**: `docs/references.md` (借鉴清单) + 外部项目监控 SOP (TBD)
> **入口**: `cat docs/references.md`

## 当前实现

### `docs/references.md` (借鉴清单, 100+ 行)

8 个借鉴维度 + 借鉴边界 (借鉴 / 复用 / 复制):
- ✅ **借鉴** (主线): 看懂思路 + 自己重新实现
- ⚠ **复用** (偶尔): 引入包 / 用代码片段 (需协议允许)
- ❌ **复制** (不采用): 直接 fork / clone

**借鉴清单** (按 nuankebao 实际功能):
1. **数据建模设计模式** ← NocoBase / Twenty / Frappe
2. **字段加密 + 查询索引模式** ← HashiCorp Vault / pgcrypto
3. **审计日志 + 触发器** ← 企业级 CRM / PostgreSQL 文档
4. **AI Builder / 工作流嵌入** ← NocoBase AI Builder / LangChain
5. **权限系统设计** ← Oso / Auth0 / Casbin / NocoBase
6. **工作流引擎简化版** ← NocoBase 工作流 / Temporal
7. **元层 + 操作层治理结构** ← [sales-ai](https://github.com/sales-ai/sales-ai) (本项目最直接借鉴源)
8. **任务快照机制** ← sales-ai scripts/task-snapshot.sh (思路借鉴, 实际重写)

### 外部项目监控 SOP (TBD)

未来实施:
- 周一 / 月一扫描 sales-ai 等项目的 release notes
- 比对 nuankebao 治理结构 / 工具链差异
- 主人 review 后决定是否吸收

## 扩展指南

**新增借鉴维度** (e.g. 想学 Odoo 的 ORM):
1. 在 `docs/references.md` 加新章节
2. 注明出处 + 协议
3. 写"我们的实现"段 (不是"复制代码")

**借鉴新项目** (e.g. 发现 Twenty 有好用的 Row-Level Security):
1. 读懂思路, 写 ADR 提案
2. 主人 ask_user 拍板 (L1 战略决策)
3. 重新实现, 注明出处 + 协议允许
4. 不直接 import 他们的代码

**借鉴代码片段** (e.g. Vue 的某个 utils 函数):
- 必须协议允许 (MIT / Apache 2.0 / BSD ✅, AGPL ❌ per CHARTER §3.2)
- 在代码顶部加注释: `// Adapted from <project> <commit-sha> (<license>)`
- 不能整文件 fork

## 相关 SOP

- [AGENTS.md §2 原则 8 借鉴思路 ≠ 复制代码](../..//AGENTS.md)
- [CHARTER.md §3.2 技术栈红线 (AGPL 永不用, OpenAI 永不用)](../../CHARTER.md)
- 主人 review 反模式: "❌ 引入 dep 不写进 package.json"

## 待办

- [ ] 外部项目监控 SOP (定期扫 sales-ai release notes)
- [ ] 借鉴清单季度审查 (主人 review 是否仍适用)
- [ ] 加"借鉴效果评估"段 (借鉴后实际改了哪些代码)
