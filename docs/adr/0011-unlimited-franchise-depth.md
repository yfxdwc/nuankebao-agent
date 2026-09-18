# ADR-0011: 加盟树层级**不限** (取消深度上限 + 图谱懒加载)

**日期**: 2026-09-18
**状态**: ✅ Accepted (主人 ask 拍板)
**决策者**: 主人 (虾王)
**影响范围**: `src/lib/db/queries/franchisee-tree.ts` + `src/app/api/franchisees/**` +
`flutter_app/lib/modules/customer/screens/customers_page.dart` + `core/models/franchisee.dart`
**对应元宪法**: [`CHARTER.md`](../CHARTER.md) §3 红线 + §7 反模式沉淀
**Supersedes**: [ADR-0010](./0010-franchise-tree-depth-4-dev-override.md) (≤4 层上限的最后一版)
**依赖**: [ADR-0006 加盟体系 + 合规边界](./0006-franchise-boundary.md) (本 ADR 的合规依据)

---

## 1. 上下文

主人 2026-09-18 看到我在 CHANGELOG 里写"层级超过 4 层时胶囊数字会大于图谱节点数"后提出质疑:

> 「层级超过 4 层时（ADR-0010 上限）？我没理解这个限制，**层级不应该做限制，理论上是可以无限层级的**」

核实结果 (两件事):

1. **数据模型确实不限层**: `franchisee.placement_path` 是物化路径 (text), 子树查询
   (`path LIKE me.path || '%'`) 与层级无关; 只有 3 处人为上限:
   | 位置 | 代码 | 性质 |
   |---|---|---|
   | 服务层 | `franchisee-tree.ts` `MAX_DEPTH = 4` | **硬拦** (第 4 层节点不能再加下线) |
   | 接口层 | `me/tree` route `Math.min(depth, 4)` | 查询封顶 |
   | DB 层 | `schema.ts` 的 `franchisee_max_depth_4` CHECK | **只是注释, 从未 migrate** → 物理无约束 |
2. **这个上限是合规保守值, 不是技术限制**: ADR-0006 初值 ≤3 (《禁止传销条例》保守口径)
   → ADR-0010 缓到 ≤4 (仅为 dev seed 能造 31 位加盟商)。
3. **我上一版 CHANGELOG 那句是错的**: 第 5 层根本建不出来 (`POST /api/franchisees` 实测 HTTP 400
   「加盟树深度上限 4 层」) → 数字不可能对不上。已在 CHANGELOG 更正 (commit `f629119`)。

## 2. 候选评估

| 候选 | 说明 | 评价 |
|---|---|---|
| A. 保持 ≤4 | 只补 ADR-0006 文档缺口 | 不合主人判断: 层级不是风险源, 硬限制会挡真实业务发展 |
| B. 只放开"查询/展示" | 图谱可看全树, 新增仍 ≤4 | 半吊子: 第 5 层还是建不出来, 数据永远长不深 |
| **C. 层级不限 (数据 + 服务) + 运维手闸 + 图谱懒加载** | 本 ADR | ✅ 主人拍板 |
| D. 放开到固定更值 (6/8 层) | 小步放开 | 仍是拍脑袋数字, 下次还得改 |

## 3. 决策

1. **取消业务层级上限** — `placeNewFranchisee` 不再按层拦; BFS 会一直下降到第一个空位
   (二叉树天然只会往浅处填, 但不再人为截断)
2. **保留运维手闸** — env `FRANCHISEE_MAX_DEPTH=<n>` (默认 `0` = 不限) 可临时封顶
   (异常数据/风控需要时, 不动代码即可收紧)
3. **合规依据** (ADR-0006 §2): 传销红线在"入门费 / 拉人头计酬 / 团队计酬";
   系统**没有金额字段 + 不做计酬**, 层级深度本身不构成风险 → 不设上限
4. **图谱改懒加载** (主人选「按需展开」):
   - 初始只请求 2 层 (`getMyTree(depth: 2)`), 深节点由用户展开
   - 新端点 `GET /api/franchisees/:id/children` — 取**直接子级** (带 `hasChildren`),
     载荷 O(子级数), 不再随层级爆炸
   - 树节点新增 `hasChildren` (全深度真值, 不受本次 depth 限制) + 根节点 `totalDescendants`
   - Flutter: 选中节点 → 顶部信息条出现「展开下级 / 收起」; 顶部计数显示
     `共 N 位 (服务端全深度) · 已展开 M`
5. **接口 `depth` 参数语义变更**: 从"业务层级上限"变成"**单次请求的载荷旋钮**",
   上限 16 层 (防单请求拉超大 JSON), 不再是业务约束

## 4. 影响

| 位置 | 旧 | 新 |
|---|---|---|
| `franchisee-tree.ts` | `MAX_DEPTH = 4` 硬拦 + BFS 按层剪枝 | 无上限 (env 手闸可选) |
| `POST /api/franchisees` (referrerId=depth4) | 400「深度上限 4 层」 | 201, 可继续往下建 |
| `GET /api/franchisees/me/tree?depth=N` | N 截到 4 | N 截到 16 (载荷保护, 语义变了) |
| `GET /api/franchisees/:id/children` | (无) | 新增: 懒加载一级子级 |
| 图谱初始视图 | 4 层全画 | 2 层 + 按需展开 |
| 图谱顶部计数 | 本地计数 (受 depth 限制) | 服务端 `totalDescendants` 全深度真值 |

**实测 (dev 库, 31 位加盟商满二叉 5 层)**:
- `POST /api/franchisees {referrerId: 90(depth=4)}` → **201**, `placementPath=L.L.L.L.L.`, `depth=5` ✅
- 新加盟商自动生成客户档案 (打通流程) → 客户列表「加盟」31 == 图谱 `totalDescendants` 31 ✅
- `GET /api/franchisees/90/children` → `[{五层验证, depth 5, hasChildren=false}]` ✅

## 5. 风险 + 缓解

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| 超大网络 (万级节点) 一次拉树打爆 JSON | 中 | 高 | 懒加载 (一次一级) + `depth` 载荷闸 16 层 |
| 深树图谱渲染/性能 | 中 | 中 | 懒加载天然控制可见节点数; 布局已有"上百节点"优化 |
| 深层级引发"多层分销"误解 | 低 | 中 | ADR-0006 §2 红线 (无金额字段/不计酬) |
| 直连 DB 写入超深数据 (绕过 service) | 低 | 低 | env 手闸只能在 service 生效; ⏳ TODO: 需要时补 DB CHECK |
| 旧客户端仍传 `depth=4` 期望"全树" | 低 | 低 | 图谱已改懒加载; 老版本 Web/APK 仍能工作 (只是看不到更深层, 可自行展开? 旧版无展开入口 → 需重新 build) |

## 6. 回滚

- **一键收紧**: 设 env `FRANCHISEE_MAX_DEPTH=4` 重启服务 (无需改代码)
- **彻底回退**: `franchisee-tree.ts` 恢复 `MAX_DEPTH = 4` + `me/tree` 改回 `Math.min(depth, 4)`
  + Flutter 图谱恢复固定 depth (1 处常量) —— 已建的超深节点保留可查, 只是不能再加深
- 数据无需迁移 (无 schema 变更)

## 7. 关联文档

- [ADR-0006 加盟体系 + 合规边界](./0006-franchise-boundary.md) — **合规判定来源** (本 ADR 的前提)
- [ADR-0010 深度 ≤4](./0010-franchise-tree-depth-4-dev-override.md) — 被本 ADR 取代
- [ADR-0004 Schema 演进红线](./0004-schema-evolution.md) — 本次**无 schema 变更** (只改查询/接口/UI)
- CHANGELOG 2026-09-18「列表加盟 = 我的下级 + 胶囊计数 + 图谱深度 4」→ 后续更正条目

## 8. 决策时间线

| 时间 | 事件 |
|---|---|
| 2026-09-18 下午 | 我在 CHANGELOG 写"层级 >4 时数字会对不上" |
| 2026-09-18 晚 | 主人质疑「层级不应该做限制」→ 我核实并承认备注有误 (commit f629119) |
| 2026-09-18 晚 | 主人 ask 拍板三件: 层级**不限** / 图谱**懒加载** / **补写 ADR-0006** |
| 2026-09-18 晚 | 本 ADR + 代码落地 (service / API / children 端点 / Flutter 懒加载) |

**Follow-up (⏳ 未做)**:
- [ ] ADR-0010 顶部加 "Superseded by ADR-0011" 标注 (本次已加, 见该文件)
- [ ] 若未来出现万级节点网络, 评估图谱按层分页 / 虚拟化渲染 (P2)
- [ ] 需要时补 DB CHECK (超深写入兜底) + CI 校验 (P3)
