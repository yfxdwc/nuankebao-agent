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
import { encryptField } from "@/lib/crypto/field";

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

  // ★ P1-A 修复 (reviewer 第二轮, 2026-09-26): (b2) 子树判定三元化
  //   原实现 `sub.path LIKE me.path || '%'` 在 me.path = '' (根用户) 时退化为 `LIKE '%'`,
  //   会把同树其他 root (path = '') 误判成下层 —— 违背「同根同枝」语义。
  //   修法: me.path = '' 走 sub.path <> ''; me.path <> '' 走 LIKE 前缀 (设计文档 §3.4)。
  //   本测试断言三件事:
  //     (a) ownedBySubordinateSql 渲染时出现三元 OR (不是单独的 LIKE)
  //     (b) 三元三个分支都拼进去 (`path = ''`, `path <> ''`, `LIKE`)
  //     (c) 同样的逻辑也被 renderIdentitySelectFields 复用 (list 与 single 同口径)
  describe("P1-A: 根用户不会把同树其他根算成下层 (三元化子树判定)", () => {
    it("ownedBySubordinateSql 渲染后是三元 OR 表达式, 不是单独的 LIKE 前缀", async () => {
      // 用外部 import 避免与上面 vi.mock 冲突 (loadIdentityRow 会触发 db.execute → mock)
      vi.resetModules();
      vi.doMock("@/lib/db", () => ({
        db: {
          execute: vi.fn(async () => []), // 不会被调用
        },
      }));
      const { ownedBySubordinateSql } = await import("@/lib/customer/identity");
      const sqlExpr = ownedBySubordinateSql(
        viewer({ userId: BigInt(101), franchiseeId: BigInt(75) })
      );
      const q = dialect.sqlToQuery(sqlExpr);
      // ★ 三元化: 三部分都出现
      //   (1) `me.placement_path = '' AND sub.placement_path <> ''`
      //   (2) `OR`
      //   (3) `me.placement_path <> '' AND sub.placement_path LIKE me.placement_path || '%'`
      expect(q.sql).toContain("placement_path = ''");
      expect(q.sql).toContain("placement_path <> ''");
      expect(q.sql).toContain("placement_path LIKE");
      expect(q.sql).toMatch(/\bOR\b/); // 上下两支用 OR 连接
      // ★ 不能再出现 "只有 LIKE 单一支" (这是原 bug 的根源)
      //   原 bug: `sub_f.placement_path LIKE (me.placement_path || '%')` 单条 WHERE
      //   修后: LIKE 之前必须有 `me.placement_path <> '' AND` 前缀 (三元化右边支)
      //   检验: 截取 LIKE 所在那行, 紧邻其前是不是 `me.placement_path <> '' AND`
      const likeIdx = q.sql.indexOf("placement_path LIKE");
      const beforeLike = q.sql.slice(Math.max(0, likeIdx - 100), likeIdx);
      expect(
        beforeLike,
        "LIKE 前缀前必须有 me.placement_path <> '' AND (三元化右边支)"
      ).toContain("placement_path <> ''");
      vi.doUnmock("@/lib/db");
      vi.resetModules();
    });

    it("renderIdentitySelectFields 复用同一三元化 (list口径 / single口径 同口径)", async () => {
      vi.resetModules();
      vi.doMock("@/lib/db", () => ({
        db: { execute: vi.fn(async () => []) },
      }));
      const { renderIdentitySelectFields } = await import("@/lib/customer/identity");
      const fields = renderIdentitySelectFields(
        viewer({ userId: BigInt(101), franchiseeId: BigInt(75) })
      );
      // ownedBySub 片段必须带三元化 (与上例同口径)
      const q = dialect.sqlToQuery(fields.ownedBySub);
      expect(q.sql).toContain("placement_path = ''");
      expect(q.sql).toContain("placement_path <> ''");
      expect(q.sql).toContain("placement_path LIKE");
      expect(q.sql).toMatch(/\bOR\b/);
      vi.doUnmock("@/lib/db");
      vi.resetModules();
    });
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

  // ★ P1-A 修复后 (2026-09-26): renderIdentitySelectFields 也要走与单条 resolveCustomerIdentity
  //   **同一套** SQL 片段。 抽这个出口 = list口径 与 single口径 不可能再漂移。
  it("renderIdentitySelectFields 渲染后仍带 customer.id 表限定 + 三元化子树 (P1-A 修复)", async () => {
    vi.resetModules();
    const identityMod = await import("@/lib/customer/identity");
    const fields = identityMod.renderIdentitySelectFields(
      viewer({ userId: BigInt(101), franchiseeId: BigInt(75) })
    );
    // renderIdentitySelectFields 本身返回 SQL 片段, 渲染时仍要限定 customer.id
    // (包装进 customer-select 模板里, 模拟生产用法)
    const sqlText = db
      .select({
        row: customer,
        ...({
          isFranchisee: fields.isFranchisee as never,
          direct: fields.direct as never,
          ownedByMe: fields.ownedByMe as never,
          ownedBySub: fields.ownedBySub as never,
          ownedByUpl: fields.ownedByUpl as never,
          ownerIdCol: fields.ownerId as never,
          isMember: fields.isMember as never,
          hasAccount: fields.hasAccount as never,
          acquireSourceCol: fields.acquireSource as never,
          sourceReferrerNameCol: fields.sourceReferrerName as never,
        } as never),
      })
      .from(customer)
      .toSQL().sql;
    // 所有片段都要带 customer.id 限定 (防裸 id 解析成 u.id)
    expect(sqlText).toContain('"customer"."id"');
    // 子树判定走三元化 (P1-A 修复): root = '' AND sub <> '' OR 非 root LIKE 前缀
    expect(sqlText).toContain("placement_path = ''");
    expect(sqlText).toContain("placement_path <> ''");
    expect(sqlText).toContain("placement_path LIKE");
  });
});

// ============================================
// 6) 列表口径 vs 单条口径 一致性 (reviewer P1 收口, 防两套口径漂移)
// ============================================
// 背景: 原 listCustomers 不传 identity 给 toView → ownership 恒 "none",
//       前端五态渲染永远看到「我的」。修法 = 列表按行算 identity, 共用
//       renderIdentitySelectFields + identityFromFlags (与单条 resolveCustomerIdentity 同)。
// 测试策略 (避免动真 DB):
//   - mock @/lib/db, 两条路径 (execute 给 resolveCustomerIdentity, select 链给 listCustomers)
//   - 同一组 5 行数据 (mine / direct_downline / subordinate / upline_placeholder / none)
//   - assert 两边产出的 ownership / affiliation / source 完全一致
//   ★ 关键防漂移点: list口径 改变量时, identityFromFlags 是同步改的, 两边不可能再岔开
describe("list口径 vs single口径 一致性 (防漂移回归)", () => {
  // ⚠ Phase A 状态: upline 恒 false (Phase D 接入 customer_share) → 这里走同型路径 (全部 false)
  const FLAG_CASES = [
    {
      label: "mine",
      flags: {
        isFranchisee: false,
        direct: false,
        ownedByMe: true,
        ownedBySub: false,
        ownedByUpl: false,
        ownerId: BigInt(101),
        isMember: true,
        hasAccount: true,
        acquireSource: "referral" as const,
        sourceReferrerName: "李四",
      },
      expectedOwnership: "mine" as const,
      expectedAffiliation: "none" as const,
    },
    {
      label: "direct_downline (归属我 + 是我的直推加盟商)",
      flags: {
        isFranchisee: true,
        direct: true,
        ownedByMe: true,
        ownedBySub: false,
        ownedByUpl: false,
        ownerId: BigInt(101),
        isMember: true,
        hasAccount: true,
        acquireSource: "friend" as const,
        sourceReferrerName: null,
      },
      expectedOwnership: "mine" as const,
      expectedAffiliation: "direct" as const,
    },
    {
      label: "subordinate (owner = 我的下层 user, 不是我的直推)",
      flags: {
        isFranchisee: false,
        direct: false,
        ownedByMe: false,
        ownedBySub: true,
        ownedByUpl: false,
        ownerId: BigInt(999),
        isMember: false,
        hasAccount: false,
        acquireSource: null,
        sourceReferrerName: null,
      },
      expectedOwnership: "subordinate" as const,
      expectedAffiliation: "none" as const,
    },
    {
      label: "upline_placeholder (Phase A 恒 false, 测试路径一致)",
      flags: {
        isFranchisee: true,
        direct: false,
        ownedByMe: false,
        ownedBySub: false,
        ownedByUpl: false, // Phase D 才变 true
        ownerId: BigInt(999),
        isMember: false,
        hasAccount: true,
        acquireSource: "cold_visit" as const,
        sourceReferrerName: null,
      },
      expectedOwnership: "other" as const, // ownerId 有值但不是 mine/sub/upline
      expectedAffiliation: "nondirect" as const,
    },
    {
      label: "none (owner_id NULL)",
      flags: {
        isFranchisee: false,
        direct: false,
        ownedByMe: false,
        ownedBySub: false,
        ownedByUpl: false,
        ownerId: null,
        isMember: false,
        hasAccount: false,
        acquireSource: null,
        sourceReferrerName: null,
      },
      expectedOwnership: "none" as const,
      expectedAffiliation: "none" as const,
    },
  ] as const;

  it("identityFromFlags: 5 个用例的 ownership / affiliation 都映射到预期 (纯函数回归)", async () => {
    const { identityFromFlags } = await import("@/lib/customer/identity");
    for (const c of FLAG_CASES) {
      const id = identityFromFlags({
        exists: true,
        ...c.flags,
      });
      expect(id.ownership, `case=${c.label}`).toBe(c.expectedOwnership);
      expect(id.affiliation, `case=${c.label}`).toBe(c.expectedAffiliation);
      expect(id.source.kind, `case=${c.label}`).toBe(c.flags.acquireSource);
      expect(id.source.referrerName, `case=${c.label}`).toBe(
        c.flags.sourceReferrerName
      );
      expect(id.member, `case=${c.label}`).toBe(c.flags.isMember);
      expect(id.registered, `case=${c.label}`).toBe(c.flags.hasAccount);
    }
  });

  it("listCustomers 与 resolveCustomerIdentity 走同一 identityFromFlags → 同 viewer / 同数据产出完全一致", async () => {
    vi.resetModules();

    // 把同一组 flags 包装成两种 DB 返回值:
    //   - execute 返回 1 行 (resolveCustomerIdentity 单条)
    //   - select 链返回 5 行 (listCustomers 列表)
    // 业务字段 (name / phone 等) 取最小集, 让 toView 不报错
    const rowBase = {
      id: BigInt(0),
      name: "row",
      // 使用真加密避免 toView 报错 (PGCRYPTO_KEY 在 setup.ts 填了全零密钥)
      phoneEncrypted: encryptField("13800000000"),
      phoneHash: "0".repeat(64),
      gender: null,
      birthYear: null,
      birthMonth: null,
      birthDay: null,
      birthCalendar: "solar",
      birthdayRemindDays: null,
      healthTagsEncrypted: null,
      diseaseHistoryEncrypted: null,
      allergyHistoryEncrypted: null,
      notesEncrypted: null,
      referrerId: null,
      avatar: null,
      isSeed: false,
      acquireSource: null,
      sourceReferrerName: null,
      ownerId: null,
      createdBy: BigInt(0),
      lastInteractionAt: null,
      lastVisitAt: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      deletedAt: null,
    };

    const buildListRow = (i: number, f: (typeof FLAG_CASES)[number]["flags"]) => ({
      row: { ...rowBase, id: BigInt(i + 1) },
      // listCustomers 提取这些字段给 identityFromFlags
      isFranchisee: f.isFranchisee,
      direct: f.direct,
      ownedByMe: f.ownedByMe,
      ownedBySub: f.ownedBySub,
      ownedByUpl: f.ownedByUpl,
      ownerIdCol: f.ownerId == null ? null : String(f.ownerId),
      isMember: f.isMember,
      hasAccount: f.hasAccount,
      acquireSourceCol: f.acquireSource,
      sourceReferrerNameCol: f.sourceReferrerName,
    });

    const buildSingleRow = (i: number, f: (typeof FLAG_CASES)[number]["flags"]) => ({
      // loadIdentityRow 用 AS 别名取这些字段
      is_franchisee: f.isFranchisee,
      direct: f.direct,
      owned_by_me: f.ownedByMe,
      owned_by_sub: f.ownedBySub,
      owned_by_upl: f.ownedByUpl,
      owner_id: f.ownerId == null ? null : String(f.ownerId),
      is_member: f.isMember,
      has_account: f.hasAccount,
      acquire_source: f.acquireSource,
      source_referrer_name: f.sourceReferrerName,
    });

    const listRows = FLAG_CASES.map((c, i) => buildListRow(i, c.flags));
    let resolveIdx = 0; // 逐次推进, 对应 5 次 resolveCustomerIdentity

    // drizzle select builder mock: 跟住 orderBy → limit → offset → then
    const makeSelectBuilder = (thenResult: unknown) => {
      const builder: any = {};
      builder.from = () => builder;
      builder.where = () => builder;
      builder.orderBy = () => builder;
      builder.limit = () => builder;
      builder.offset = () => builder;
      builder.then = (onFulfilled: any, onRejected: any) =>
        Promise.resolve(thenResult).then(onFulfilled, onRejected);
      return builder;
    };

    // listCustomers 里 db.select 被调 2 次 (Promise.all): 第一次 count, 第二次 rows
    // (在 query 包装里顺序不保证, 但我们按调用顺序交替返回)
    let selectCallIdx = 0;

    vi.doMock("@/lib/db", () => ({
      db: {
        // resolveCustomerIdentity → loadIdentityRow → db.execute
        execute: vi.fn(async () => {
          const f = FLAG_CASES[resolveIdx % FLAG_CASES.length].flags;
          const idx = resolveIdx % FLAG_CASES.length;
          resolveIdx++;
          return [buildSingleRow(idx, f)];
        }),
        // listCustomers → db.select (主 + count)
        // 靠调用顺序区分: 第一次 → count; 第二次 → rows (在 listCustomers 里 Promise.all 同时发起,
        // 我们这里选 “第一次 → rows, 第二次 → count” 也能跑, 但 listCustomers 实际是先
        // db.select({row, ...flags}) → rows, 再 db.select({count}) → count)
        select: vi.fn((_fields: unknown) => {
          const isFirstCall = selectCallIdx === 0;
          selectCallIdx++;
          return makeSelectBuilder(
            isFirstCall ? listRows : [{ count: FLAG_CASES.length }]
          );
        }),
      },
    }));

    const { listCustomers } = await import("@/lib/db/queries/customer");
    const { resolveCustomerIdentity } = await import("@/lib/customer/identity");

    const viewerCtx = viewer({
      userId: BigInt(101),
      franchiseeId: BigInt(75),
      customerId: null, // excludeCustomerId 不在这里处理
    });

    const listResult = await listCustomers({
      viewerFranchiseeId: BigInt(75),
      rbacCtx: {
        userId: BigInt(101),
        role: "sales",
        defaultStoreId: null,
        managedStoreIds: [],
        franchiseeId: BigInt(75),
      },
    });

    // ★ 防漂移断言: 列表 5 行的 ownership / affiliation / source
    //   与单条 resolveCustomerIdentity 完全一致
    expect(listResult.items.length).toBe(FLAG_CASES.length);
    for (let i = 0; i < FLAG_CASES.length; i++) {
      const listItem = listResult.items[i];
      const single = await resolveCustomerIdentity(BigInt(i + 1), viewerCtx);
      expect(single, `case=${FLAG_CASES[i].label}`).not.toBeNull();
      expect(
        listItem.ownership,
        `case=${FLAG_CASES[i].label}: list.ownership vs resolveCustomerIdentity.ownership`
      ).toBe(single!.ownership);
      expect(
        listItem.affiliation,
        `case=${FLAG_CASES[i].label}: list.affiliation vs single.affiliation`
      ).toBe(single!.affiliation);
      expect(
        listItem.source.kind,
        `case=${FLAG_CASES[i].label}: list.source.kind vs single.source.kind`
      ).toBe(single!.source.kind);
      expect(
        listItem.source.referrerName,
        `case=${FLAG_CASES[i].label}: list.source.referrerName vs single.source.referrerName`
      ).toBe(single!.source.referrerName);
      // 同时验证它们都符合预期 (双锁)
      expect(listItem.ownership, `case=${FLAG_CASES[i].label}`).toBe(
        FLAG_CASES[i].expectedOwnership
      );
      expect(listItem.affiliation, `case=${FLAG_CASES[i].label}`).toBe(
        FLAG_CASES[i].expectedAffiliation
      );
    }

    vi.doUnmock("@/lib/db");
    vi.resetModules();
  });

  it("listCustomers 渲染的 SQL 字段与 loadIdentityRow 一致 (防字段顺序漂移)", async () => {
    // 渲染守卫: listCustomers 用的 renderIdentitySelectFields(viewer) 必须产出与
    // loadIdentityRow 同样顺序的字段。 改其中之一时另一边同步变化 —— 这是结构
    // 保险, 防“list 加字段忘了同步 single”之类的隐错。
    // ⚠ drizzle 在 select 里**不会**给 raw SQL 片段加 AS 别名 (只有列名/聚合加);
    //   所以按“应该出现在 SQL 里的表达式特征”验证, 而不是别名。
    const { renderIdentitySelectFields } = await import("@/lib/customer/identity");
    const fields = renderIdentitySelectFields(
      viewer({ userId: BigInt(101), franchiseeId: BigInt(75) })
    );
    const sqlText = db
      .select({
        row: customer,
        ...({
          isFranchisee: fields.isFranchisee as never,
          direct: fields.direct as never,
          ownedByMe: fields.ownedByMe as never,
          ownedBySub: fields.ownedBySub as never,
          ownedByUpl: fields.ownedByUpl as never,
          ownerIdCol: fields.ownerId as never,
          isMember: fields.isMember as never,
          hasAccount: fields.hasAccount as never,
          acquireSourceCol: fields.acquireSource as never,
          sourceReferrerNameCol: fields.sourceReferrerName as never,
        } as never),
      })
      .from(customer)
      .toSQL().sql;
    // 10 个字段的表达式特征都在渲染后的 SQL 里
    // (1) is_franchisee / direct: 两个 EXISTS 查 franchisee f JOIN user u
    expect(sqlText).toContain("EXISTS (");
    expect(sqlText).toContain("f.deleted_at IS NULL");
    expect(sqlText).toContain("u.franchisee_id = f.id");
    expect(sqlText).toContain("referrer_id"); // direct 口径
    // (2) ownedByMe: owner_id = $2
    expect(sqlText).toContain('"owner_id" = $2');
    // (3) ownedBySub: 三元化子树判定 (P1-A 修复)
    expect(sqlText).toContain("placement_path = ''");
    expect(sqlText).toContain("placement_path <> ''");
    expect(sqlText).toContain("placement_path LIKE");
    // (4) ownedByUpl: Phase D 起 = customer_share 推送判定 (不再是恒 false)
    expect(sqlText).toContain("customer_share");
    expect(sqlText).toContain("cs.to_user_id");
    expect(sqlText).toContain("cs.revoked_at IS NULL");
    // (5) ownerIdCol / acquireSourceCol / sourceReferrerNameCol: 直接读列
    expect(sqlText).toContain('"customer"."owner_id"');
    expect(sqlText).toContain('"customer"."acquire_source"');
    expect(sqlText).toContain('"customer"."source_referrer_name"');
    // (6) isMember: memberExistsSql 走 LEFT JOIN membership
    expect(sqlText).toContain("LEFT JOIN membership");
    expect(sqlText).toContain("member_until > NOW()");
    // (7) hasAccount: 单一 EXISTS ("customer"."id")
    expect(sqlText).toContain('WHERE u.customer_id = "customer"."id"');
  });
});