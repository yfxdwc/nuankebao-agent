// 客户类型判定单测 (混合方案 C, 主人 2026-09-18 拍; 2026-09-22 改「加盟」口径)
//
// 规则:
//   加盟 franchisee = 客户手机号对应一位 franchisee, **且她是我的直推**
//                     (点位父 placement_parent_id = 我, 第 1 层)
//                     ⚠ 主人 2026-09-22 拍: 列表「加盟」只算直推, **不再**算整个子树;
//                       图谱 tab 仍是全子树 (getPlacementTree) → 列表 ⊆ 图谱, 故意不同口径
//   种子 seed       = customer.is_seed = true (显式勾选)
//   普通 normal     = 其余 (默认)
//   优先级: 加盟 > 种子 > 普通
//
// 这里只测纯函数 resolveCustomerType + CUSTOMER_TYPES 契约 (不连 DB);
// 直推 SQL (myDirectDownlineFranchiseeSql) / 计数 (customerTypeCounts) / API 400
// 走 dev server 实测 — 见 CHANGELOG 2026-09-18 条目 (注: 那条记的是**旧**的子树口径
//   viewer=75 时 franchisee=30; 改直推后该数字会变小, 属预期)

import { describe, it, expect } from "vitest";
import { resolveCustomerType, CUSTOMER_TYPES } from "@/lib/db/queries/customer";

describe("queries/customer — resolveCustomerType", () => {
  it("是我的下级加盟商 → franchisee", () => {
    expect(resolveCustomerType({ isSeed: false }, true)).toBe("franchisee");
  });

  it("加盟 > 种子 (误标种子的下级加盟商还是加盟)", () => {
    expect(resolveCustomerType({ isSeed: true }, true)).toBe("franchisee");
  });

  it("is_seed=true 且不是我的下级 → seed", () => {
    expect(resolveCustomerType({ isSeed: true }, false)).toBe("seed");
  });

  it("默认 (不是我的下级 + 未标种子) → normal", () => {
    expect(resolveCustomerType({ isSeed: false }, false)).toBe("normal");
  });

  it("未加盟 viewer (没有下级) 时只剩 种子/普通 两类", () => {
    expect(resolveCustomerType({ isSeed: true }, false)).toBe("seed");
    expect(resolveCustomerType({ isSeed: false }, false)).toBe("normal");
  });

  it("三种类型枚举稳定 (前端胶囊 + API zod 共用这套值)", () => {
    expect([...CUSTOMER_TYPES]).toEqual(["franchisee", "seed", "normal"]);
  });
});

// ============================================
// 「自己不应该是自己的客户」排除条件 (主人 2026-09-22; ADR-0016 D3 已 ID 化)
// ============================================
// 背景: 建号即强制建档 (AGENTS §6.6) → 每个账号有一条自己的 customer 档案,
//       语义是"她作为别人的客户"; 但**她自己**的客户列表/概览不该出现它。
// 口径: **ID** —— customer.id = 我的档案 id (user.customer_id)。
//       ⚠ 旧口径按 phone_hash 排除已废 (ADR-0016: 手机号不是身份, 同号不同人会误伤)。
// 边界: 未登录 / admin 无档案 → 返回 null = 不加条件 = 老行为 (web admin 不传也不变)。

import { PgDialect } from "drizzle-orm/pg-core";
import {
  selfCustomerExclusionSql,
  myDirectDownlineFranchiseeSql,
} from "@/lib/db/queries/customer";

const dialect = new PgDialect();

describe("queries/customer — selfCustomerExclusionSql", () => {
  it("有我的档案 id → 产出「customer.id <> $1」条件并带参 (ID 化)", () => {
    const cond = selfCustomerExclusionSql(BigInt(736));
    expect(cond).not.toBeNull();
    const q = dialect.sqlToQuery(cond!);
    expect(q.sql).toContain("<>");
    expect(q.sql).toContain("id");
    expect(q.sql).not.toContain("phone_hash"); // ADR-0016 D3: 手机号不再是身份
    expect(q.params).toEqual([736n]);
  });

  it("null / undefined → 不加条件 (不排除任何行)", () => {
    expect(selfCustomerExclusionSql(null)).toBeNull();
    expect(selfCustomerExclusionSql(undefined)).toBeNull();
  });
});

// ============================================
// 「加盟 = 直推」口径 (主人 2026-09-22)
// ============================================
// 列表/徽标的「加盟」只算**直推** (点位父 = 我), 不是整个 placement 子树;
// 图谱 tab 才显示全子树 → 两者故意不同口径, 列表加盟数 ≤ 图谱加盟节点数。

describe("queries/customer — myDirectDownlineFranchiseeSql", () => {
  it("走点位父 (placement_parent_id) + ID 连接 (u.customer_id), 不再用手机号/子树前缀", () => {
    const cond = myDirectDownlineFranchiseeSql(BigInt(75));
    const q = dialect.sqlToQuery(cond);
    expect(q.sql).toContain("placement_parent_id");
    // ★ ADR-0016 D3: 「同一个人」只认 ID (账号↔档案 customer_id / 账号↔节点 franchisee_id)
    expect(q.sql).toContain("u.customer_id");
    expect(q.sql).toContain("u.franchisee_id");
    expect(q.sql).not.toContain("phone_hash");
    // 旧子树口径的特征是 placement_path LIKE —— 必须彻底不再出现
    expect(q.sql).not.toContain("placement_path");
    expect(q.params).toContain(75n);
  });

  it("未加盟 (null) → 恒 false (加盟桶必为 0)", () => {
    expect(dialect.sqlToQuery(myDirectDownlineFranchiseeSql(null)).sql).toBe("false");
  });
});
