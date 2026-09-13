# 暖客宝 Phase 3 — SaaS 化架构设计

> 主人 W8-W9-W10 选 d (Phase 2 AI 增强) 已完成
> Phase 3: 把"内部用"扩展为"卖给别人"
> 本文档是**设计准备**, 不实现代码 (等主人拍板)

---

## 1. 现状分析

### v0.1.0 (Phase 1 + 1.5 + 2 完成)
- 25 commits / 109 文件 / 59 测试
- 单租户 (所有数据共享, 没有"哪个店"的隔离)
- 自托管: 主人自己服务器
- 适合: 1 家店 / 1 个销售团队

### 限制
- 多个客户用同一份数据, 不能分账
- 不能限"张三只能看自己的客户"
- 销售 / 店长 / 老板 权限无差别
- 备份 / 计费 / 套餐 都没有

---

## 2. Phase 3 目标

把 暖客宝 从"1 家店用"扩展为"100 家店都能用", 主线业务流**不变**:

```
[不变]
- 客户 / 养生记录 / 跟进 / 联系 业务功能
- 字段加密 + 审计
- AI 集成 (MiniMax)
- Flutter / Web 双端

[新增]
- 多租户: 每家店 = 一个 tenant
- 角色权限: 老板 / 店长 / 销售 (三级)
- 计费层: 套餐 (试用 / 基础 / 专业)
- 限流持久化: Redis 替代内存
- 错误监控: Sentry
- 客户成功: 引导 / 文档 / 客服
```

---

## 3. 架构变更

### 3.1 数据隔离 (3 种方案对比)

| 方案 | 描述 | 优点 | 缺点 |
|---|---|---|---|
| **A. 共享 DB + tenant_id 列** | 所有表加 tenant_id, 查询时 WHERE | 简单, 改造成本低 | 应用必须强制过滤, 漏一处就泄露 |
| **B. Schema 隔离** | 每个 tenant 一个 schema (customer_1, customer_2) | 物理隔离 | schema 多了 DB 性能差, 迁移复杂 |
| **C. DB 隔离** | 每个 tenant 一个 DB | 最安全 | 运维噩梦 (几百个 DB) |

**推荐 A** (多租户 + 强制过滤), 风险控制:
- 强制使用 `getTenantDb(tenantId)` 包装, 业务代码不直接拿 db
- 用 Drizzle 中间件自动加 `WHERE tenant_id = ?`
- CI 加 lint 规则禁止裸 `db.select()`(只能 `getTenantDb().select()`)

### 3.2 schema 改动 (预留, 不实施)

```sql
-- 新增 tenant 表
CREATE TABLE tenant (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,           -- 用于子域名 (shop1.nuankebao.com)
  plan TEXT NOT NULL DEFAULT 'trial',  -- trial / basic / pro
  status TEXT NOT NULL DEFAULT 'active',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  trial_ends_at TIMESTAMPTZ,
  subscription_ends_at TIMESTAMPTZ
);

-- 所有业务表加 tenant_id (Phase 3 启动时执行)
ALTER TABLE customer ADD COLUMN tenant_id BIGINT NOT NULL REFERENCES tenant(id);
ALTER TABLE wellness_record ADD COLUMN tenant_id BIGINT NOT NULL REFERENCES tenant(id);
-- ... 其他表

-- 索引
CREATE INDEX idx_customer_tenant ON customer(tenant_id);
-- 联合索引 (性能)
CREATE UNIQUE INDEX idx_customer_tenant_phone ON customer(tenant_id, phone_hash);
```

### 3.3 应用层

```typescript
// src/lib/db/tenant.ts (新)
import { db } from "@/lib/db";
import type { Tenant } from "@/lib/db/schema";

export async function getTenantDb(tenantId: bigint) {
  // 包装 Drizzle, 强制 WHERE tenant_id = ?
  return {
    select: (...args: any[]) => db.select(...args).where(eq(table.tenantId, tenantId)),
    insert: ...,
    // etc.
  };
}

// 从 session / header 提取 tenant
export async function getCurrentTenantId(): Promise<bigint> {
  // 从 session.user.tenantId 读
  // 或从 subdomain (shop1.nuankebao.com → slug "shop1" → tenant.id 1)
}
```

### 3.4 角色权限 (RBAC)

```
SuperAdmin (暖客宝 官方)     ← SaaS 平台管理员
    ↓
TenantOwner (店主)         ← 一个店的老板
    ↓
TenantManager (店长)       ← 店里的管理
    ↓
TenantStaff (销售)         ← 一线操作
```

```typescript
// 角色矩阵
const PERMISSIONS = {
  SuperAdmin: ["*"],
  TenantOwner: [
    "customer.*", "wellness_record.*", "follow_up.*",
    "user.invite", "user.remove", "billing.*", "settings.*",
  ],
  TenantManager: [
    "customer.*", "wellness_record.*", "follow_up.*",
    "report.view", "user.invite",
  ],
  TenantStaff: [
    "customer.create", "customer.read", "customer.update",
    "wellness_record.*", "follow_up.*", "interaction.*",
  ],
};

// 简化版 (Phase 3 早期, 后期用 Oso / Casbin)
export function can(role: Role, action: string): boolean {
  const perms = PERMISSIONS[role];
  return perms.includes("*") || perms.some((p) => action.startsWith(p));
}
```

### 3.5 计费层

```
Trial       7 天 / 5 个客户 / 1 用户
Basic       ¥99/月  / 500 客户 / 5 用户
Pro         ¥299/月 / 5000 客户 / 20 用户
Enterprise  定制
```

集成: 微信支付 / 支付宝 (国内首选)
- 后端 webhook 接收支付通知
- 续费 / 过期自动降级到 Trial

### 3.6 多端路由

```
主域名: nuankebao.com (营销 + 登录)
子域名: {tenant}.nuankebao.com (客户登录 + 工作台)
```

DNS:
- 通配符 `*.nuankebao.com → 同一 IP`
- Nginx 配 server_name 匹配
- 应用层从 host 提取 subdomain → 查 tenant.slug

### 3.7 限流持久化 (Upstash Redis)

```typescript
// 替代内存限流
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

const redis = new Redis({
  url: process.env.UPSTASH_REDIS_REST_URL!,
  token: process.env.UPSTASH_REDIS_REST_TOKEN!,
});

const limiter = new Ratelimit({
  redis,
  // sliding window
  limiter: Ratelimit.slidingWindow(60, "1 m"),
});

// API 守卫
const limit = await limiter.limit(`api:${userId}`);
if (!limit.success) return 429;
```

优点:
- 跨实例共享 (多 Next.js 实例也能用同一份限流)
- 持久化 (server 重启不丢)
- 全球低延迟 (Upstash edge)

成本: 免费 10K 请求/天, 够小 SaaS

---

## 4. 实施路线 (建议)

### Phase 3.1: 多租户基础 (4-6 周)
- [ ] schema 加 tenant + tenant_id
- [ ] getTenantDb() 包装 + lint 规则
- [ ] 租户注册 / 登录 / 子域名
- [ ] 角色 + 权限
- [ ] 套餐 + 计费 (基础)

### Phase 3.2: SaaS 化 (4-6 周)
- [ ] Upstash Redis 限流
- [ ] Sentry 错误监控
- [ ] 微信支付集成
- [ ] 客户引导 / 文档 / 客服
- [ ] 管理后台 (SuperAdmin 看所有租户)

### Phase 3.3: 增长 (持续)
- [ ] 推荐系统 (老客带新客)
- [ ] 培训认证 (体系化学习)
- [ ] 营销工具 (节日活动 / 优惠券)
- [ ] 第三方集成 (企微 / 钉钉)

---

## 5. 风险与兜底

| 风险 | 兜底 |
|---|---|
| 多租户数据泄露 | 强制 tenant_id 过滤 + 定期 SQL 审计 |
| 老板看所有数据 | RBAC + 审计日志 + 数据脱敏 |
| 计费纠纷 | 明确套餐 + 邮件确认 + 7 天退款 |
| 子域名 DNS 复杂 | 主备 Cloudflare + 自动证书 |
| 计费 + 限流成本 | Upstash 按用量, 小客户 < ¥10/月 |
| Flutter 端权限 | 服务端鉴权 + 路由级中间件 |

---

## 6. Phase 3 启动条件

**必须先做完:**
- [x] Phase 1 + 1.5 + 2 完成 (W1-W10, 25 commits)
- [ ] 物理操作完成 (A/B/C, 见 PHYSICAL_OPS.md)
- [ ] 1-2 销售内测反馈 (W6 收尾)
- [ ] 主人确认"我要做 SaaS" (不是"我自用就行")

**满足后启动 Phase 3.1**, 预计 4-6 周完工。

---

## 7. 配套文档 (Phase 3 启动时写)

- `docs/multi-tenant.md` - 详细多租户架构
- `docs/rbac.md` - 角色权限矩阵
- `docs/billing.md` - 套餐 + 支付集成
- `docs/deployment-multi-region.md` - 多区域部署
- ADR 0003-0008 (Phase 3 决策)

---

**当前状态**: Phase 3 准备中, 等主人物理操作完成 + 1-2 销售内测反馈
**下一步**: 主人做完 a/b/c 后, 跑 1-2 周内测, 收集反馈, 决定是否启动 Phase 3.1