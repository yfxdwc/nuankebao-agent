# ADR-0006: 加盟体系 + 合规边界

> **补写说明 (2026-09-18)**: 本 ADR 早年只在 [ADR-0010](./0010-franchise-tree-depth-4-dev-override.md) 里被引用
> ("ADR-0006 设定 ≤3 层硬约束 + 边界 1 = 无金额字段"), **文件本体一直缺失** (INDEX 里标 "（预留）")。
> 2026-09-18 主人拍板放开加盟树层级 ([ADR-0011](./0011-unlimited-franchise-depth.md)) 时, 要求
> **先把本 ADR 补上**——否则没人能说清"层级红线到底怎么来的"。
> 本文件按 **现有代码事实 + ADR-0010/0011 的引用 + 《禁止传销条例》口径** 反推补写,
> 不引入任何当前代码里不存在的机制 (缺失之处标 ⏳ TODO)。

**日期**: 2026-09-18 (补写; 原始决策可追溯到 2026-09-03 数据模型设计)
**状态**: ✅ Accepted (补写版; 层级部分已被 [ADR-0011](./0011-unlimited-franchise-depth.md) 修正)
**决策者**: 主人 (虾王)
**影响范围**: `franchisee` 表 + `modules/relation/**` + `modules/customer/**` (图谱) + 合规红线
**对应元宪法**: [`CHARTER.md`](../CHARTER.md) §3 技术红线 + §4 域划分 + §7 反模式沉淀

---

## 1. 上下文

暖客宝 的用户是**大健康行业的销售 / 客服人员**, 业务形态是"加盟 + 老带新":

- 一个销售员 = 一个加盟商 (`user.franchiseeId` 1:1 绑定)
- 加盟商之间有**推荐关系** (`referrerId`) 和**二叉树排位** (`placementSide` / `placementPath` / `placementDepth`)
- 客户之间另有**老带新推荐链** (`customer.referrerId`), 跟加盟体系是两套关系
- 客户页「图谱」tab 画的是**加盟商网络** (以"我"为根); 客户列表画的是**客户档案**

> ⚠ 这两套档案靠 `phone_hash` 对齐, 但不自动互联 —— 2026-09-18 修过一次
> (列表「加盟」= 我的下级加盟商; 见 CHANGELOG「客户列表胶囊筛选」条目)

## 2. 合规红线 (本 ADR 的核心)

《禁止传销条例》(国务院令第 444 号) 识别传销的三个特征:

| 特征 | 暖客宝现状 | 结论 |
|---|---|---|
| **入门费** (交钱/买货才取得资格) | 系统**不收任何费用**, `franchisee` 表**无金额字段** | ✅ 不构成 |
| **拉人头** (以发展人员数量为计酬依据) | 有推荐关系 (关系展示 / 老带新), **但不按人头计酬** | ✅ 不构成 |
| **团队计酬** (以下线业绩为报酬依据) | `franchisee` / `customer` 表**无佣金 / 对碰 / 层奖 / 见点 / 提成字段**; 系统不做业绩计算 | ✅ 不构成 |

**红线 (任何 feature 都不得突破)**:

1. ❌ 不得在 `franchisee` / `customer` 及任何关联表加**金额类字段** (入门费/佣金/返利/对碰奖/层奖/见点奖/提成)
2. ❌ 不得以"发展了几个下线 / 团队多大"作为**计酬 / 分红 / 返利**依据 (展示统计 OK)
3. ✅ 层级**深度本身**不构成传销 (见 [ADR-0011](./0011-unlimited-franchise-depth.md)); 构成风险的是**计酬机制**
4. ✅ 加盟关系只用于: 关系展示 (图谱) + 客户维护 (谁的人谁服务) + RBAC 行级过滤

> 依据: 条例关注"以发展人员数量/下线业绩计酬 + 入门费", 与"关系展示"是两个层面的事。
> 本判断是**工程合规口径**, 不替代法律意见; 真要对外商用前建议请律师复核 (⏳ TODO)。

## 3. 决策

1. **关系模型**: 加盟商之间 = 推荐人 (`referrerId`) + 二叉树位置 (`placementSide` left/right, 物化路径 `placementPath`)
2. **1:1 强约束**: 用户 = 加盟商 = 销售员, 不存在"一个用户多个加盟身份"
3. **无金额字段**: 见 §2 红线 1 (代码事实: `schema.ts` 的 `franchisee` 表 15 列无金额列)
4. **关系系统可替换**: 加盟只是关系系统的一个**默认实现** (`RelationSystem` 接口,
   默认 `FranchiseRelationSystem`, 见 [ADR-0007](./0007-modular-architecture.md));
   换成"分销/推荐"等形态时不改调用方
5. **层级深度**: 初版设 ≤3 层 (合规保守) → [ADR-0010](./0010-franchise-tree-depth-4-dev-override.md) 放宽 ≤4
   → **[ADR-0011](./0011-unlimited-franchise-depth.md) 取消上限** (层级不是风险点, 计酬才是)

## 4. 影响 + 边界

| 领域 | 约定 |
|---|---|
| 数据 | 手机号走 pgcrypto (`phoneEncrypted` + `phoneHash`); 备注加密; 表上有 audit trigger |
| 关系表 | `franchisee` 无 FK 自引用 (应用层校验环 + 位置合法性) |
| 展示 | 图谱只展示关系/层级/线别, 不做业绩排行 |
| RBAC | 客户行级过滤走 `store_id` (CHARTER §3.6) |
| 导出 | 加盟关系可导出用于**服务**, 不得用于计酬结算 |

## 5. 风险

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| 后续 feature 顺手加"返利/佣金"字段 | 中 | 高 (合规) | 本 ADR + ADR-0011 写死红线; code review 必查金额字段 |
| 层级很深被误读为"多层分销" | 低 | 中 | 无计酬机制 + 本 ADR §2 口径; 对外材料统一说明 |
| 关系系统替换时逻辑泄漏 | 低 | 中 | 走 `RelationSystem` 接口 (ADR-0007 §RelationSystem) |

## 6. 关联文档

- [ADR-0007 底座 + 模块化](./0007-modular-architecture.md) — `RelationSystem` 接口 + `modules/relation/`
- [ADR-0010 加盟树深度 ≤4](./0010-franchise-tree-depth-4-dev-override.md) — 本 ADR §3.5 的第一次放宽
- [ADR-0011 加盟树层级不限](./0011-unlimited-franchise-depth.md) — 本 ADR §3.5 的最终口径 (Supersedes ADR-0010)
- [CHARTER §3 红线](../CHARTER.md) / [security-compliance.md](../security-compliance.md)

## 7. 元数据 / 时间线

| 时间 | 事件 |
|---|---|
| 2026-09-03 | 数据模型设计含 `franchisee` 二叉树 (ADR-0002); 层级初值 ≤3 (本 ADR 追认) |
| 2026-09-16 | ADR-0010 放宽 ≤4 (dev/test seed 需求) |
| 2026-09-18 | 主人拍板层级不限 → 触发本 ADR **补写** (原文件缺失) |

**Follow-up (⏳ 未做)**:
- [ ] 对外商用前请律师复核 §2 合规口径 (P2)
- [ ] `docs/security-compliance.md` 加一节"加盟体系合规"引用本 ADR (P3)
- [ ] CHARTER §3 红线加一行引用本 ADR (P3)
