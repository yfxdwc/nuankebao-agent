// ============================================
// 「我的客户」可见范围单测 (ADR-0015 Q2 / 步骤 1, 主人 2026-09-22 拍)
// ============================================
// 口径 = 归属我 (customer.owner_id = 我) ∪ 我的直推加盟 (点位父 = 我的节点)
//
// 这里只测纯 SQL 构造 (不连 DB):
//   - queries/customer-scope.ts   → 单一真相源 (列表 / 计数 / 概览 / 行级过滤共用)
//   - auth/rbac.ts::customerRbacFilter → 行级过滤入口
// 真行为 (谁能看到谁) 走 dev server 实测 + scripts/smoke-*.ts。
//
// 守卫点 (漂移预防):
//   1. sales 过滤**不再**读 store_id (门店维度已冻结, ADR-0015 Q8)
//   2. sales 过滤**不再**读 created_by (建档 ≠ 归属, Q11 拆栏)
//   3. 直推判定必须走 placement_parent_id (AGENTS §6.8 拆栏), 不是 referrer_id / placement_path
//   4. admin 不过滤 (全森林); 未加盟 sales 的直推半边恒 false

import { describe, it, expect } from "vitest";
import { PgDialect } from "drizzle-orm/pg-core";
import {
  directDownlineFranchiseeSql,
  myCustomerScopeSql,
  ownedByUserSql,
} from "@/lib/db/queries/customer-scope";
import { customerRbacFilter, type RbacContext } from "@/lib/auth/rbac";

const dialect = new PgDialect();

const ctx = (over: Partial<RbacContext>): RbacContext => ({
  userId: BigInt(101),
  role: "sales",
  defaultStoreId: null,
  managedStoreIds: [],
  franchiseeId: null,
  ...over,
});

describe("customer-scope — 我的客户 = 归属我 ∪ 直推加盟", () => {
  it("ownedByUserSql: owner_id = 我", () => {
    const q = dialect.sqlToQuery(ownedByUserSql(BigInt(101)));
    expect(q.sql).toContain("owner_id");
    expect(q.params).toEqual([101n]);
  });

  it("myCustomerScopeSql: owner_id ∪ placement_parent_id (两个半边都在)", () => {
    const q = dialect.sqlToQuery(
      myCustomerScopeSql({ ownerUserId: BigInt(101), franchiseeId: BigInt(75) })
    );
    expect(q.sql).toContain("owner_id");
    expect(q.sql).toContain("placement_parent_id");
    // ★ ADR-0016 D3: 身份连接只走 ID (u.customer_id / u.franchisee_id), 不再比手机号
    expect(q.sql).toContain("u.customer_id");
    expect(q.sql).toContain("u.franchisee_id");
    expect(q.sql).not.toContain("phone_hash");
    // 结构判定读点位父, 不读推荐人/路径
    expect(q.sql).not.toContain("referrer_id");
    expect(q.sql).not.toContain("placement_path");
    expect(q.params).toEqual(expect.arrayContaining([101n, 75n]));
  });

  it("未加盟 (franchiseeId = null): 直推半边恒 false, 归属半边照常", () => {
    const q = dialect.sqlToQuery(
      myCustomerScopeSql({ ownerUserId: BigInt(101), franchiseeId: null })
    );
    expect(q.sql).toContain("owner_id");
    expect(q.sql).toContain("false");
    expect(q.params).toEqual([101n]);
  });

  it("directDownlineFranchiseeSql(null) 就是字面 false", () => {
    expect(dialect.sqlToQuery(directDownlineFranchiseeSql(null)).sql).toBe("false");
  });
});

describe("rbac.customerRbacFilter — 行级过滤入口", () => {
  it("admin → 不过滤 (undefined = 全森林)", () => {
    expect(customerRbacFilter(ctx({ role: "admin" }))).toBeUndefined();
  });

  it("sales → 归属 ∪ 直推; **不再**读 store_id / created_by (Q8/Q11 冻结)", () => {
    const filter = customerRbacFilter(
      ctx({ role: "sales", userId: BigInt(101), franchiseeId: BigInt(75) })
    );
    expect(filter).toBeDefined();
    const q = dialect.sqlToQuery(filter!);
    expect(q.sql).toContain("owner_id");
    expect(q.sql).toContain("placement_parent_id");
    expect(q.sql).not.toContain("store_id");
    expect(q.sql).not.toContain("created_by");
    expect(q.params).toEqual(expect.arrayContaining([101n, 75n]));
  });

  it("sales 未加盟 (franchiseeId=null) → 仍能看自己的归属客户", () => {
    const filter = customerRbacFilter(ctx({ role: "sales", franchiseeId: null }));
    expect(filter).toBeDefined();
    const q = dialect.sqlToQuery(filter!);
    expect(q.sql).toContain("owner_id");
    expect(q.sql).toContain("false");
    expect(q.params).toEqual([101n]);
  });

  it("manager 仍按门店 (⚠ store 已冻结, ADR-0015 Q8; 无店 = 看不到任何)", () => {
    const none = dialect.sqlToQuery(
      customerRbacFilter(ctx({ role: "manager", managedStoreIds: [] }))!
    );
    expect(none.sql).toContain('"customer"."id" = 0');

    const some = dialect.sqlToQuery(
      customerRbacFilter(ctx({ role: "manager", managedStoreIds: [BigInt(7)] }))!
    );
    expect(some.sql).toContain("store_id");
    expect(some.params).toEqual([7n]);
  });
});
