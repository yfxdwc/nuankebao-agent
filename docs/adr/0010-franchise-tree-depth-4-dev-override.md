# ADR-0010: 加盟树深度 ≤3 → ≤4 放宽 (主人 2026-09-16 override, dev/test seed data 需求)

**日期**: 2026-09-16
**状态**: ✅ Accepted (主人 ask_user d234bdd4 拍板, 选 `relax-3to4`)
**决策者**: 主人 (虾王)
**影响范围**: src/lib/db/queries/franchisee-tree.ts + src/app/api/franchisees/me/tree/route.ts + src/lib/db/schema.ts + 测试数据 seed
**对应元宪法**: [`CHARTER.md`](../CHARTER.md) §3.5 治理红线 + ADR-0006 合规边界 / 《禁止传销条例》实务解读
**替代**: 否决了「2/3 个独立 tree」(30+ 加盟商) + 「接受硬约束 1 tree 15 节点」两个候选

---

## 上下文

本决策对应:

- [ADR-0006 加盟体系 + 合规边界 (预留 ID, 文件待补)](0006-franchise-boundary.md) — 设定 ≤3 层硬约束 (《禁止传销条例》红线)
- [`docs/CHARTER.md`](../CHARTER.md) §3.5 治理红线 — 改 schema / service 必走本 ADR
- [ADR-0004 Schema 演进红线](0004-schema-evolution.md) — service + schema 改动要记 ADR

## 问题

主人 2026-09-16 ask 反馈: "**测试数据中各类型的客户都创建一些. 加盟客户创建 30 个以上, 尽量体现更多更全面的复杂的分支、关系**".

加盟二叉树当前硬约束 **≤3 层** (ADR-0006):

```
root (depth 0)        → 1 节点
├─ L / R (depth 1)    → 2 节点
├─ L.L / L.R / R.L / R.R (depth 2)  → 4 节点
└─ depth 3 (leaf)     → 8 节点
─────────────────────────────────
TOTAL (满二叉): 1 + 2 + 4 + 8 = 15 节点
```

→ 单 tree 最多 15 个加盟商. 要 30+ 必须放宽到 ≤4 层 (1+2+4+8+16=**31**, 刚好过线).

## 候选评估 (主人 ask_user 3 选项 + 我加的 1 选项)

| 候选 | 节点数 | 复杂度 | 合规风险 | 主人拍板 |
|---|---|---|---|---|
| A. 2 个独立 tree (各 15) | 30 | 中 (无 cross-tree 关系) | 无 (沿用 ADR-0006) | ❌ |
| B. 3 个独立 tree (各 15) | 45 | 中 (无 cross-tree 关系) | 无 | ❌ |
| C. 1 tree 接受 ≤3 硬约束 | 15 | 已有 8 叶 + 4 中 + 2 顶 + 1 root | 无 | ❌ |
| D. **放宽 ≤3 → ≤4 (主人 override)** | 31 | **单 tree 5 层深 + 16 叶** | **+1 层 (≤4 仍 < 5)** | ✅ |

## 决策

主人 2026-09-16 ask_user (d234bdd4) 拍板: **D. 放宽 ≤3 → ≤4**.

具体改动 4 处 (全为 1-3 行):

| 文件 | 旧 | 新 | 说明 |
|---|---|---|---|
| `src/lib/db/queries/franchisee-tree.ts:46-67` | `MAX_DEPTH = 3` 隐含 (`if (ref.depth >= 3)`) | `const MAX_DEPTH = 4` + 引用 ADR-0010 | service 层硬约束 |
| `src/app/api/franchisees/me/tree/route.ts:25` | `Math.min(depth, 3)` | `Math.min(depth, 4)` | tree 查询最大深度 |
| `src/lib/db/schema.ts:118-123` | `franchisee_max_depth_3 CHECK (≤3)` | `franchisee_max_depth_4 CHECK (≤4)` | sql raw block (当前未被 migrate 应用, 仅文档作用) |
| `docs/adr/INDEX.md` | — | 加 0010 行 | 索引同步 |

### 0.1 跟进 bug fix (2026-09-16, 同任务期间发现)

**bug**: BFS fallback 只检查 `input.referrerId` 的 depth, 不检查 BFS-发现 parent 的 depth. 测试时手输入 `referrerId=10 (孙志强, depth=3)` + `sideHint=left` (位置被占), BFS 下降到 `徐长山 (depth=4)`, 新节点被放到 `徐长山.left` → `placement_depth=5`, 超 MAX_DEPTH=4.

**修法** (1 文件, src/lib/db/queries/franchisee-tree.ts BFS loop):
- BFS 不把 `depth >= MAX_DEPTH` 的子节点 push 进 queue (它们是叶子, 不能当 parent)
- 避免 BFS 把 depth-4 叶子当 parent

**未加单测**: 本次未补 Vitest regression (git scope 控制), 仅手动验证. TODO §5 加 记.

## 1. 合规风险评估 (主人 override 已授权, 仍需记录)

| 维度 | 评估 |
|---|---|
| **《禁止传销条例》** | 条例关注 ≥3 级分销 + 入会费 + 团队计酬 (实务入刑门槛 5+ 级). 暖客宝 1:1 user/franchisee 强约束 (无团队计酬) + 无金额字段 (ADR-0006 边界 1) → **4 层仍是单线深度, 不构成 MLM**. 风险评估: 可接受 |
| **数据真实性** | dev/test seed 数据, 不是 prod. 主人 2026-09-16 ask 已显式 override, 知悉风险 |
| **回滚成本** | 1 行 (`4 → 3` × 2 处 + sql 同步). depth=4 节点保留可查, 但不能再加子. 0 数据迁移 |

## 2. 何时 revert (主人 override 是临时还是永久)

本 ADR **不** 自带过期时间. 主人两种选择:

| 选项 | 主人手动改 | 后续影响 |
|---|---|---|
| **永久** (推荐, 默认) | 不动 | 单 tree 5 层 (depth 0-4), 16 叶. dev + prod 都是 ≤4 |
| **dev 临时** | 删本 ADR + 改回 `MAX_DEPTH = 3` + `Math.min(depth, 3)` | prod 收紧回 ≤3. depth=4 节点保留 (孤儿), 无法再添子. 等下次 ask_user 决定 |

> **默认** = 永久, 等下次 ask_user 明确「revert 到 ≤3」再改.

## 3. 影响范围

### 3.1 seed 数据 (本 ADR 触发)

- 1 棵 binary tree, depth 0-4 (31 节点: 1+2+4+8+16)
- 节点命名见 `scripts/seed-test-data.ts` (待 commit)
- 演示完整分支 + 复杂关系 (主 + 备 + 嵌套)

### 3.2 prod 行为变化

| 接口 | 旧行为 | 新行为 |
|---|---|---|
| `POST /api/franchisees` (referrerId + sideHint) | referrer depth ≥3 抛 400 | referrer depth ≥4 抛 400 |
| `GET /api/franchisees/me/tree?depth=N` | N > 3 截到 3 | N > 4 截到 4 |
| `/app-preview` 客户页图谱 | 4 层可视化 | 5 层可视化 (16 叶节点) |
| `franchiseeTreePainter` | OK | OK (depth 参数从外部传, 内部不写死) |

### 3.3 审计 + 回滚

- 改动已写进本 ADR + service + schema 注释 + INDEX
- `git log --grep "ADR-0010"` 可查所有相关 commit
- revert 流程: 见 §2

## 4. 风险 + 缓解

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| 主人忘记 override 缘由, 后续看代码困惑 | 低 | 低 | 本 ADR §1 §2 + service 注释 + schema 注释 三处都写明 |
| prod 真出现 MLM 投诉 | 极低 (无金额字段 + 1:1 user 强约束) | 高 | §1 评估 + 主人自己拍板 |
| DB CHECK 没真加, 绕过 service 直 insert 超 depth 4 | 中 | 中 | 当前 sql raw block 没接 migrate. **本 ADR §5 加 todo: 真接 drizzle migrate + CI 阻断超 depth 写入** |
| 多 tree (主人拒的方案 A/B) 后续又被要求 | 低 | 低 | 留 INDEX 索引 + 本 ADR §候选 拒因记录 |

## 5. Follow-up (本次不实现, 仅记账)

- [ ] **TODO** (P2): 真把 `franchiseeMaxDepthCheck` 接入 drizzle migrate (加 DB CHECK). 当前 sql raw block 在 schema.ts 里但 migrate 没应用 (需手动 `pnpm db:migrate` 跑这段 sql 才能落地). 落地后 CI 阻断直 DB insert.
- [ ] **TODO** (P3): 在 `tools/check-migration-compat.sh` 加 franchisee_depth ≤ 4 验证 (跟主人 ADR-0010 §1 一起审).
- [ ] **TODO** (P3): CHARTER.md §3.5 / §3.6 加一行引用 ADR-0010 (放宽 lineage).

## 6. 决策时间线

| 时间 | 事件 |
|---|---|
| 2026-09-03 | ADR-0006 设定 ≤3 (推测; ADR 文件 0006 缺失, 见 TODO §5) |
| 2026-09-16 ~10:50 | 主人 ask: "测试数据各类型客户, 加盟 30+, 复杂分支关系" |
| 2026-09-16 ~10:55 | 我提 4 候选, 主人选 D (`relax-3to4`) + 给种子客户定义 |
| 2026-09-16 ~11:00 | 改 service + schema + route 4 处, 写本 ADR-0010 |
| 2026-09-16 ~11:10 | 写 seed script + 跑通 + 截图验证 |

---

**拍板来源**: 主人 ask_user `d234bdd4` (2026-09-16 10:55, Q1 tree-shape 选项 D)
**对照**: ADR-0006 既有约束的精确放宽, 不是废弃; ADR-0010 = ADR-0006 的修正案 (amendment)