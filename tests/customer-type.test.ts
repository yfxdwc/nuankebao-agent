// 客户类型判定单测 (混合方案 C, 主人 2026-09-18 拍)
//
// 规则:
//   加盟 franchisee = franchisee 表存在同 phone_hash 记录 (派生)
//   种子 seed       = customer.is_seed = true (显式勾选)
//   普通 normal     = 其余 (默认)
//   优先级: 加盟 > 种子 > 普通
//
// 这里只测纯函数 resolveCustomerType + CUSTOMER_TYPES 契约 (不连 DB);
// 端到端 (SQL EXISTS 子查询 / type 筛选 / API 400) 走 dev server curl 验证,
// 见 CHANGELOG [2026-09-18] 条目。

import { describe, it, expect } from "vitest";
import { resolveCustomerType, CUSTOMER_TYPES } from "@/lib/db/queries/customer";

describe("queries/customer — resolveCustomerType", () => {
  it("加盟商 (phone_hash 命中 franchisee 表) → franchisee", () => {
    const type = resolveCustomerType(
      { phoneHash: "abc", isSeed: false },
      new Set(["abc"])
    );
    expect(type).toBe("franchisee");
  });

  it("加盟 > 种子 (误标种子的加盟商还是加盟)", () => {
    const type = resolveCustomerType(
      { phoneHash: "abc", isSeed: true },
      new Set(["abc"])
    );
    expect(type).toBe("franchisee");
  });

  it("is_seed=true 且非加盟 → seed", () => {
    const type = resolveCustomerType(
      { phoneHash: "zzz", isSeed: true },
      new Set(["abc"])
    );
    expect(type).toBe("seed");
  });

  it("默认 (非加盟 + 未标种子) → normal", () => {
    const type = resolveCustomerType(
      { phoneHash: "zzz", isSeed: false },
      new Set(["abc"])
    );
    expect(type).toBe("normal");
  });

  it("空加盟集 (没有加盟商数据时) 不影响种子/普通判定", () => {
    const empty = new Set<string>();
    expect(resolveCustomerType({ phoneHash: "a", isSeed: true }, empty)).toBe("seed");
    expect(resolveCustomerType({ phoneHash: "b", isSeed: false }, empty)).toBe("normal");
  });

  it("三种类型枚举稳定 (前端胶囊 + API zod 共用这套值)", () => {
    expect([...CUSTOMER_TYPES]).toEqual(["franchisee", "seed", "normal"]);
  });
});
