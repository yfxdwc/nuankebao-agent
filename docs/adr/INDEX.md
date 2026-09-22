# ADR 索引 (Architecture Decision Records)

> **借鉴**: sales-ai 项目 [`docs/adr/INDEX.md`](https://github.com/sales-ai/sales-ai/blob/main/docs/adr/INDEX.md) 思路 (索引 + 决策摘要表).
> **格式**: Kebab-case 文件名, 编号递增. 每条 ADR 包含: 上下文 / 决策 / 候选评估 / 影响 / 风险.

---

## 索引 (按时间倒序, 最新在最上)

| # | 标题 | 状态 | 拍板日期 | 关键决策 |
|---|---|---|---|---|
| 0016 | [身份锚与同号识别 —— 邀请码是唯一识别码, 手机号只是联系方式](./0016-identity-anchor.md) | ✅ Accepted | 2026-09-22 | 唯一识别码 = **邀请码** (手机号不是身份); 系统内部连接一律走 ID (`user.customer_id` / `user.franchisee_id`); 同号 → 识别提醒 (不静默合并); 沙龙客人归带来人 (不加转化入口); 同号不允许两条档案 (定案); 生命周期初步机制 (停用/软删/退出图谱 + admin 入口); UI 区分「已注册」vs「凭空建档」 |
| 0015 | [主体模型 —— 人 / 账号 / 客户 / 节点 (消歧 + 单一真相源)](./0015-subject-model.md) | ✅ Accepted | 2026-09-22 | 主人「系统视角 / 用户视角」口径入档: 充值/免费用户 + 6 位推荐码=身份识别; 图谱可见性 (系统=全森林, 用户=自枝全部下层 + 上 3 层直系); 4 条边分工 (推荐码关系不表达关系); 客户归属 = 建档 vs 归属分离 (Q11); 「我的客户」= 归属 ∪ 直推; 废弃 `customer.referrer_id`; 落 `user.customer_id` (additive) |
| 0013 | [账号 = 客户 (建号即强制建档) + 推荐码必填](./0013-account-customer-binding.md) | ✅ Accepted | 2026-09-19 | 唯一建号入口 `createAccountWithProfile`; 非 admin 必须有推荐码; 推荐码**不写** `customer.referrer_id` (no_link); 存量补齐 7/7 + 0 无推荐人 |
| 0011 | [加盟树层级**不限** (取消深度上限 + 图谱懒加载)](./0011-unlimited-franchise-depth.md) | ✅ Accepted | 2026-09-18 | 层级不限 (合规依据 ADR-0006); env `FRANCHISEE_MAX_DEPTH` 手闸; `GET /:id/children` 懒加载; Supersedes ADR-0010 |
| 0009 | [预览框架冻结 (4 层防御)](./0009-preview-framework-freeze.md) | ✅ Accepted | 2026-09-16 | tag baseline + pre-commit guard (block) + ADR + Vitest/Playwright 测试; 9 个路径冻结 |
| 0010 | [加盟树深度 ≤3 → ≤4 放宽 (主人 override, dev/test seed data)](./0010-franchise-tree-depth-4-dev-override.md) | ⚠️ Superseded | 2026-09-16 | 主人 ask_user d234bdd4 拍板; 单 tree 1+2+4+8+16=31 节点; 3 文件各改 1-3 行; ADR-0006 amendment (非废弃) |
| 0008 | [APK 域 + WEB 域功能清单与协作关系](./0008-apk-web-domain-spec.md) | ✅ Accepted | 2026-09-13 | 两域共存 (不是 dev↔prod 切换); 共享后端 API; WEB 域 production mode 永久 |
| 0007 | [底座 + 模块化插件架构](./0007-modular-architecture.md) | ✅ Accepted | 2026-09-13 | APK 域分 `core/` 底座 + `modules/` 业务模块; WEB 域 `dev-modules/` 文档化视图; ★ RelationSystem 接口 |
| 0006 | [加盟体系 + 合规边界](./0006-franchise-boundary.md) | ✅ Accepted (2026-09-18 补写) | 2026-09-18 | 关系展示/客户维护定位; 红线 = 无金额字段 + 不团队计酬; 层级深度本身非风险 |
| 0005 | [Mobile-Only 阶段 (web admin freeze-keep + flutter-only-sync)](./0005-mobile-only-phase.md) | ✅ Accepted | 2026-09-07 | web admin 冻结, 仅 P0 fix; backend 改动只同步 Flutter service |
| 0004 | [Schema 演进红线](./0004-schema-evolution.md) | ✅ Accepted | 2026-09-05 | 6 个绝对禁止的 migration 模式 (DROP/RENAME/ALTER TYPE 无 USING 等); CI `tools/check-migration-compat.sh` |
| 0003 | [Flutter 开发工作流](./0003-flutter-dev-workflow.md) | ✅ Accepted | 2026-09-04 | Flutter + Android Studio + USB 真机 + 自动 hot reload |
| 0002 | [数据模型](./0002-data-model.md) | ✅ Accepted | 2026-09-03 | 13 表 + 字段加密 (pgcrypto) + 5 审计触发器 |
| 0001 | [技术栈选型](./0001-tech-stack.md) | ✅ Accepted | 2026-09-03 | Next.js 15 + shadcn/ui + Tailwind + Drizzle + Auth.js v5 + Flutter 3.24 |

---

## 阶段分类

### 业务结构 (加盟体系)
- **ADR-0014**: 多根加盟树 (`root_id`) + 向上认领上级 (`kind=promote`)
- **ADR-0011**: 加盟树层级不限 (+ 图谱懒加载)
- **ADR-0006**: 加盟体系 + 合规边界 (关系展示定位 + 无金额字段红线)

### 元架构 / 项目宪章 (影响全局)
- **ADR-0007**: 双域 + 底座 + 模块化 (v0.1.3 架构基石)
- **ADR-0008**: APK + WEB 双域功能清单与协作关系 (v0.1.4 双域细化)
- **ADR-0009**: 预览框架冻结 (4 层防御, 治理基础设施)

### 阶段策略 (影响开发模式)
- **ADR-0005**: Mobile-Only 阶段 (封闭 web admin)
- **ADR-0003**: Flutter 开发工作流

### 技术选型 / 数据
- **ADR-0001**: 技术栈
- **ADR-0002**: 数据模型
- **ADR-0004**: Schema 演进红线

### 业务/合规范畴
- **ADR-0006**: 加盟体系 + 合规边界 (关系展示定位 + 无金额字段红线)
- **ADR-0010**: 加盟树深度 ≤4 (已被 ADR-0011 取代)
- **ADR-0011**: 加盟树层级不限 (+ 图谱懒加载)
- **ADR-0012**: 会员 + 推荐码
- **ADR-0013**: 账号 = 客户 (建号即强制建档)
- **ADR-0016**: 身份锚与同号识别 (邀请码 = 唯一识别码)
- **ADR-0015**: 主体模型 (人 / 账号 / 客户 / 节点 —— 消歧 + 单一真相源; ⏳ Draft 待拍板)

---

## ADR 起草指南

新 ADR 必须:
1. 编号递增 (下一个 = `0015-...md`)
2. 文件名 kebab-case
3. 包含 7 个标准节: 上下文 / 决策 / 候选评估 / 影响 / 风险 / 关联文档 / 元数据
4. 元宪法引用: `本决策对应元宪法 [CHARTER §X](../CHARTER.md)`
5. 在本 INDEX.md 加一行 (按时间倒序插到顶部)
6. 主人拍板后才标 ✅ Accepted (未拍板 = ⏳ Draft)
