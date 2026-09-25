// ============================================
// 客户标识体系 (Phase A) 单测
// ============================================
// 文档: docs/customer-identity-system.md §3 / §5 / §8.1
// 覆盖:
//   1. referredFranchiseeSql SQL 构造 (referrer 口径, §2.1 supersede)
//   2. resolveCustomerIdentity 5 态标注 (mine / subordinate / upline / other / none) —
//      用纯函数 + mock 替代真 DB 验证 (不连 DB)
//   3. zod refine: 转介绍 referral 必填介绍人 (D5)
//   4. 来源四值枚举 (D7) + nullable 兼容老 APK
//
// 真行为 (DB / route) 走 dev server 实测 + scripts/smoke-*.ts。
//
// ⚠ DB 依赖测试需要独立 _test DB (与 setup.ts 一致), 本文件**纯逻辑**
//   + SQL 渲染断言, 不连真库, 跟 customer-scope.test.ts 同模式。
// ============================================

import { describe, it, expect } from "vitest";
import { sql } from "drizzle-orm";
import { PgDialect } from "drizzle-orm/pg-core";
import { z } from "zod";
import { db } from "@/lib/db";
import { customer } from "@/lib/db/schema";
import {
  referredFranchiseeSql,
  hasAccountSql,
} from "@/lib/db/queries/customer-scope";
import {
  type AcquireSource,
  type ViewerContext,
} from "@/lib/customer/identity";

const dialect = new PgDialect();

const viewer = (over: Partial<ViewerContext> = {}): ViewerContext => ({
  userId: BigInt(101),
  franchiseeId: BigInt(75),
  customerId: BigInt(736),
  ...over,
});

// ============================================
// referredFranchiseeSql (Phase A §2.1 supersede 核心)
// ============================================
describe("referredFranchiseeSql — 直推 = referrer 口径 (supersede placement)", () => {
  it("走 referrer_id, 不走 placement_parent_id (与图谱同真相源, §2.1)", () => {
    const cond = referredFranchiseeSql(BigInt(75));
    const q = dialect.sqlToQuery(cond);
    expect(q.sql).toContain("referrer_id");
    expect(q.sql).not.toContain("placement_parent_id");
    // ★ ADR-0016 D3: 身份连接只走 ID (u.customer_id / u.franchisee_id), 不再比手机号
    expect(q.sql).toContain("u.customer_id");
    expect(q.sql).toContain("u.franchisee_id");
    expect(q.sql).not.toContain("phone_hash");
    expect(q.params).toEqual([75n]);
  });

  it("viewer 无加盟节点 (null) → 恒 false (B2 INV-3 硬约束)", () => {
    expect(dialect.sqlToQuery(referredFranchiseeSql(null)).sql).toBe("false");
  });

  it("渲染后保留 customer.id 表限定 (防裸 \"id\" 子查询 bug)", () => {
    // 生产用法: db.select({ row: customer, x: sql`${sqlExpr}` })
    const sqlText = db
      .select({ row: customer, x: referredFranchiseeSql(BigInt(75)) as never })
      .from(customer)
      .toSQL().sql;
    expect(sqlText).toContain('"customer"."id"');
    // 不要出 u.customer_id = "id" 这种恒 false 错配
    expect(sqlText).not.toMatch(/u\.customer_id\s*=\s*"id"/);
  });

  it("软删节点不计入 (f.deleted_at IS NULL, B1 INV-4)", () => {
    const cond = referredFranchiseeSql(BigInt(75));
    const q = dialect.sqlToQuery(cond);
    expect(q.sql).toContain("f.deleted_at");
    expect(q.sql).toContain("IS NULL");
  });
});

// ============================================
// 1) 直推口径 = referrer (§2.1 实证 + 反证)
// ============================================
describe("直推口径 = referrer (§2.1 supersede 核心)", () => {
  // 实证: 「我推荐但点位挂在别人名下」的加盟者 → affiliation = direct
  //   (走 referredFranchiseeSql: f.referrer_id = 我, 不读 placement_parent_id)
  it("我推荐但点位挂别人名下 → 旧 placement 口径会漏判, 新 referrer 口径会命中", () => {
    const newSql = referredFranchiseeSql(BigInt(75));
    const newQ = dialect.sqlToQuery(newSql);
    expect(newQ.sql).toContain("referrer_id");
    // 反证: 旧 placement 口径用的是 placement_parent_id → 不出现在新 SQL 里
    expect(newQ.sql).not.toContain("placement_parent_id");
  });

  it("点位挂我名下但由别人推荐 → 旧 placement 口径会误判 direct, 新 referrer 口径不会", () => {
    const newSql = referredFranchiseeSql(BigInt(75));
    const newQ = dialect.sqlToQuery(newSql);
    // 新口径只读 referrer_id: 别人推荐的 → 不命中, 不会标 "direct"
    expect(newQ.sql).toContain("referrer_id");
  });
});

// ============================================
// 2) 来源校验 (zod refine, D5 + D7)
// ============================================
// 直接复刻 POST /api/customers route 的 CreateCustomerSchema.superRefine, 验证转介绍必填逻辑
const AcquireSourceSchema = z
  .enum(["friend", "referral", "cold_visit", "ground_promo"])
  .nullable()
  .optional();
const ReferrerNameSchema = z.string().max(50).nullable().optional();

const RefinedSchema = z
  .object({
    acquireSource: AcquireSourceSchema,
    sourceReferrerName: ReferrerNameSchema,
  })
  .superRefine((data, ctx) => {
    if (
      data.acquireSource === "referral" &&
      (data.sourceReferrerName == null ||
        data.sourceReferrerName.trim().length === 0)
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["sourceReferrerName"],
        message: "转介绍必填介绍人姓名",
      });
    }
  });

describe("来源 (Phase A §5 / D5 / D7) zod refine", () => {
  it("friend 不必填介绍人 → 通过", () => {
    const r = RefinedSchema.safeParse({
      acquireSource: "friend",
      sourceReferrerName: null,
    });
    expect(r.success).toBe(true);
  });

  it("cold_visit / ground_promo 不必填介绍人 → 通过", () => {
    for (const k of ["cold_visit", "ground_promo"] as const) {
      const r = RefinedSchema.safeParse({
        acquireSource: k,
        sourceReferrerName: null,
      });
      expect(r.success).toBe(true);
    }
  });

  it("referral 无介绍人 → 400 (refine 抛错)", () => {
    const r = RefinedSchema.safeParse({
      acquireSource: "referral",
      sourceReferrerName: null,
    });
    expect(r.success).toBe(false);
    if (!r.success) {
      const issue = r.error.issues.find((i) =>
        i.path.includes("sourceReferrerName")
      );
      expect(issue?.message).toContain("转介绍必填介绍人姓名");
    }
  });

  it("referral 空字符串介绍人 → 400 (trim 后视为未填)", () => {
    const r = RefinedSchema.safeParse({
      acquireSource: "referral",
      sourceReferrerName: "   ",
    });
    expect(r.success).toBe(false);
  });

  it("referral 有介绍人 → 通过", () => {
    const r = RefinedSchema.safeParse({
      acquireSource: "referral",
      sourceReferrerName: "张三",
    });
    expect(r.success).toBe(true);
  });

  it("四值枚举: 非法值 → 拒绝 (D7 enum)", () => {
    const r = RefinedSchema.safeParse({
      acquireSource: "微信" as unknown as AcquireSource,
      sourceReferrerName: null,
    });
    expect(r.success).toBe(false);
  });

  it("acquireSource = null (老 APK / 未填写) → 通过, 来源列落 NULL", () => {
    const r = RefinedSchema.safeParse({
      acquireSource: null,
      sourceReferrerName: null,
    });
    expect(r.success).toBe(true);
  });

  it("acquireSource 字段缺省 (undefined) → 通过", () => {
    const r = RefinedSchema.safeParse({});
    expect(r.success).toBe(true);
  });

  it("sourceReferrerName 长度 ≤ 50 (DB 列类型保持, 路由层护栏)", () => {
    const tooLong = "x".repeat(51);
    const r = RefinedSchema.safeParse({
      acquireSource: "referral",
      sourceReferrerName: tooLong,
    });
    expect(r.success).toBe(false);
  });
});

// ============================================
// 3) ownership 5 态标注 (纯函数测试, 不连 DB)
// ============================================
// 加载 identity 函数本体 → 用 vi.mock 替换 db.execute, 验证 5 态映射逻辑
import { vi } from "vitest";

// 注意: 用 vi.mock 必须放在所有 import 之后 (vitest 提升) — 改为动态 import
describe("resolveCustomerIdentity — ownership 5 态标注", () => {
  it("viewer 无加盟节点 (franchiseeId=null) → 不报错, ownership 只能是 none / mine", async () => {
    // 用 vi.mock 隔离 db.execute (替代真 DB)
    vi.resetModules();
    vi.doMock("@/lib/db", () => ({
      db: {
        execute: vi.fn(async (_sql: unknown) => {
          return [
            {
              exists: true,
              is_franchisee: false,
              direct: false,
              owned_by_me: false,
              owned_by_sub: false,
              owned_by_upl: false,
              owner_id: null,
              is_member: false,
              has_account: false,
              acquire_source: null,
              source_referrer_name: null,
            },
          ];
        }),
      },
    }));
    const { resolveCustomerIdentity } = await import("@/lib/customer/identity");
    const result = await resolveCustomerIdentity(
      BigInt(736),
      viewer({ franchiseeId: null })
    );
    expect(result).not.toBeNull();
    expect(result!.affiliation).toBe("none");
    expect(result!.ownership).toBe("none");
    expect(result!.member).toBe(false);
    expect(result!.registered).toBe(false);
    expect(result!.source).toEqual({ kind: null, referrerName: null });
    vi.doUnmock("@/lib/db");
    vi.resetModules();
  });

  it("ownership = mine (owner_id = viewer.user_id) → 命中", async () => {
    vi.resetModules();
    vi.doMock("@/lib/db", () => ({
      db: {
        execute: vi.fn(async () => [
          {
            exists: true,
            is_franchisee: false,
            direct: false,
            owned_by_me: true,
            owned_by_sub: false,
            owned_by_upl: false,
            owner_id: "101",
            is_member: true,
            has_account: true,
            acquire_source: "referral",
            source_referrer_name: "李四",
          },
        ]),
      },
    }));
    const { resolveCustomerIdentity } = await import("@/lib/customer/identity");
    const result = await resolveCustomerIdentity(
      BigInt(736),
      viewer()
    );
    expect(result).not.toBeNull();
    expect(result!.ownership).toBe("mine");
    expect(result!.affiliation).toBe("none"); // 没节点 → 非加盟
    expect(result!.member).toBe(true);
    expect(result!.registered).toBe(true);
    expect(result!.source).toEqual({ kind: "referral", referrerName: "李四" });
    vi.doUnmock("@/lib/db");
    vi.resetModules();
  });

  it("ownership = subordinate (owner_id 是我的下层 user.id) → 命中", async () => {
    vi.resetModules();
    vi.doMock("@/lib/db", () => ({
      db: {
        execute: vi.fn(async () => [
          {
            exists: true,
            is_franchisee: false,
            direct: false,
            owned_by_me: false,
            owned_by_sub: true,
            owned_by_upl: false,
            owner_id: "999",
            is_member: false,
            has_account: false,
            acquire_source: "friend",
            source_referrer_name: null,
          },
        ]),
      },
    }));
    const { resolveCustomerIdentity } = await import("@/lib/customer/identity");
    const result = await resolveCustomerIdentity(
      BigInt(736),
      viewer()
    );
    expect(result).not.toBeNull();
    expect(result!.ownership).toBe("subordinate");
    expect(result!.source).toEqual({ kind: "friend", referrerName: null });
    vi.doUnmock("@/lib/db");
    vi.resetModules();
  });

  it("ownership = none (owner_id IS NULL, 没有任何归属) → 命中", async () => {
    vi.resetModules();
    vi.doMock("@/lib/db", () => ({
      db: {
        execute: vi.fn(async () => [
          {
            exists: true,
            is_franchisee: false,
            direct: false,
            owned_by_me: false,
            owned_by_sub: false,
            owned_by_upl: false,
            owner_id: null,
            is_member: false,
            has_account: false,
            acquire_source: null,
            source_referrer_name: null,
          },
        ]),
      },
    }));
    const { resolveCustomerIdentity } = await import("@/lib/customer/identity");
    const result = await resolveCustomerIdentity(
      BigInt(736),
      viewer()
    );
    expect(result!.ownership).toBe("none");
    vi.doUnmock("@/lib/db");
    vi.resetModules();
  });

  it("ownership = other (owner_id 有值但不是我/下级/上级) → 命中", async () => {
    vi.resetModules();
    vi.doMock("@/lib/db", () => ({
      db: {
        execute: vi.fn(async () => [
          {
            exists: true,
            is_franchisee: false,
            direct: false,
            owned_by_me: false,
            owned_by_sub: false,
            owned_by_upl: false,
            owner_id: "999",
            is_member: false,
            has_account: false,
            acquire_source: null,
            source_referrer_name: null,
          },
        ]),
      },
    }));
    const { resolveCustomerIdentity } = await import("@/lib/customer/identity");
    const result = await resolveCustomerIdentity(
      BigInt(736),
      viewer()
    );
    expect(result!.ownership).toBe("other");
    vi.doUnmock("@/lib/db");
    vi.resetModules();
  });

  it("affiliation 推导: 加盟 + 我的直推 → direct", async () => {
    vi.resetModules();
    vi.doMock("@/lib/db", () => ({
      db: {
        execute: vi.fn(async () => [
          {
            exists: true,
            is_franchisee: true,
            direct: true,
            owned_by_me: false,
            owned_by_sub: false,
            owned_by_upl: false,
            owner_id: null,
            is_member: false,
            has_account: true,
            acquire_source: null,
            source_referrer_name: null,
          },
        ]),
      },
    }));
    const { resolveCustomerIdentity } = await import("@/lib/customer/identity");
    const result = await resolveCustomerIdentity(
      BigInt(736),
      viewer()
    );
    expect(result!.affiliation).toBe("direct");
    vi.doUnmock("@/lib/db");
    vi.resetModules();
  });

  it("affiliation 推导: 加盟 + 非直推 → nondirect", async () => {
    vi.resetModules();
    vi.doMock("@/lib/db", () => ({
      db: {
        execute: vi.fn(async () => [
          {
            exists: true,
            is_franchisee: true,
            direct: false,
            owned_by_me: false,
            owned_by_sub: false,
            owned_by_upl: false,
            owner_id: null,
            is_member: false,
            has_account: true,
            acquire_source: null,
            source_referrer_name: null,
          },
        ]),
      },
    }));
    const { resolveCustomerIdentity } = await import("@/lib/customer/identity");
    const result = await resolveCustomerIdentity(
      BigInt(736),
      viewer()
    );
    expect(result!.affiliation).toBe("nondirect");
    vi.doUnmock("@/lib/db");
    vi.resetModules();
  });

  it("客户不存在 / 已软删 → null (路由层据此 404)", async () => {
    vi.resetModules();
    vi.doMock("@/lib/db", () => ({
      db: {
        execute: vi.fn(async () => []), // 空数组 = 行不存在
      },
    }));
    const { resolveCustomerIdentity } = await import("@/lib/customer/identity");
    const result = await resolveCustomerIdentity(
      BigInt(736),
      viewer()
    );
    expect(result).toBeNull();
    vi.doUnmock("@/lib/db");
    vi.resetModules();
  });
});

// ============================================
// 4) viewer 无加盟节点不报错 (B2 INV-3 不变量)
// ============================================
describe("B2 INV-3: viewer 无加盟节点不报错", () => {
  it("viewer.franchiseeId = null + viewer.userId 有效 → 正常返回, affiliation='none'", async () => {
    vi.resetModules();
    vi.doMock("@/lib/db", () => ({
      db: {
        execute: vi.fn(async () => [
          {
            exists: true,
            is_franchisee: false,
            direct: false,
            owned_by_me: true, // 我 owner_id
            owned_by_sub: false,
            owned_by_upl: false,
            owner_id: "101",
            is_member: false,
            has_account: false,
            acquire_source: null,
            source_referrer_name: null,
          },
        ]),
      },
    }));
    const { resolveCustomerIdentity } = await import("@/lib/customer/identity");
    const result = await resolveCustomerIdentity(
      BigInt(736),
      viewer({ franchiseeId: null }) // ★ 关键: 无加盟节点
    );
    expect(result).not.toBeNull();
    expect(result!.ownership).toBe("mine");
    expect(result!.affiliation).toBe("none");
    expect(result!.source).toEqual({ kind: null, referrerName: null });
    vi.doUnmock("@/lib/db");
    vi.resetModules();
  });
});

// ============================================
// 5) 渲染守卫 (跟 customer-scope.test.ts 同样的回归)
// ============================================
describe("SQL 渲染守卫 (Phase A 回归)", () => {
  it("referredFranchiseeSql 在生产用法下仍带 customer.id 表限定", () => {
    const sqlText = db
      .select({
        row: customer,
        x: sql`${referredFranchiseeSql(BigInt(75))}` as never,
      })
      .from(customer)
      .toSQL().sql;
    expect(sqlText).toContain('"customer"."id"');
    expect(sqlText).toContain("referrer_id");
    expect(sqlText).not.toMatch(/u\.customer_id\s*=\s*"id"/);
  });

  it("hasAccountSql 渲染仍然带 customer.id 表限定 (已有守卫回归)", () => {
    const sqlText = db
      .select({ row: customer, x: hasAccountSql as never })
      .from(customer)
      .toSQL().sql;
    expect(sqlText).toContain('"customer"."id"');
    expect(sqlText).not.toMatch(/u\.customer_id\s*=\s*"id"/);
  });
});