// 客户类型判定单测 (混合方案 C + 图谱同口径, 主人 2026-09-18 拍)
//
// 规则:
//   加盟 franchisee = 客户手机号对应一位 franchisee, **且该加盟商在我的 placement 子树里**
//                     (= 我的下级, 跟客户页图谱 tab 同口径 getPlacementTree / ADR-0010)
//   种子 seed       = customer.is_seed = true (显式勾选)
//   普通 normal     = 其余 (默认)
//   优先级: 加盟 > 种子 > 普通
//
// 这里只测纯函数 resolveCustomerType + CUSTOMER_TYPES 契约 (不连 DB);
// 「我的子树」SQL (myDownlineFranchiseeSql) / 计数 (customerTypeCounts) / API 400
// 走 dev server 实测 — 见 CHANGELOG 2026-09-18 条目:
//   viewer=75 时 stats = { all: 46, franchisee: 30, seed: 5, normal: 11 }
//   且 30+5+11 === 46 (三类互斥穷尽), 图谱 depth=4 也显示「共 30 位」→ 两边一致

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
