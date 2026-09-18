// 「我的」页后端纯函数单测 (无 DB 依赖)
//   - maskPhone: 手机号打码 (GET /api/me 的 masked 字段)
//   - parseAppVersionSpec: pubspec 版本号 (0.2.2+3) → 版本 + build number
import { describe, it, expect } from "vitest";
import { maskPhone } from "@/lib/utils";
import { parseAppVersionSpec } from "@/lib/apk";

describe("maskPhone", () => {
  it("11 位手机号 → 138****8000", () => {
    expect(maskPhone("13800138000")).toBe("138****8000");
    expect(maskPhone("19912345678")).toBe("199****5678");
  });

  it("带分隔符的数字 → 只取数字再打码", () => {
    expect(maskPhone("138-0013-8000")).toBe("138****8000");
    expect(maskPhone("138 0013 8000")).toBe("138****8000");
  });

  it("空 / null → 空串 (调用方自己决定占位符)", () => {
    expect(maskPhone(null)).toBe("");
    expect(maskPhone(undefined)).toBe("");
    expect(maskPhone("")).toBe("");
  });

  it("非 11 位 → 头 3 尾 2, 不整串露出", () => {
    expect(maskPhone("01012345678")).toBe("010*****78");
    expect(maskPhone("1234567")).toBe("123**67");
  });

  it("极短 → 全打码", () => {
    expect(maskPhone("1234")).toBe("****");
    expect(maskPhone("1")).toBe("*");
  });

  it("打码后永远不含完整原串 (回归: 别把 11 位以外的号明文带出去)", () => {
    for (const p of ["13800138000", "01012345678", "1234567", "4008001234"]) {
      expect(maskPhone(p)).not.toBe(p);
      expect(maskPhone(p)).toContain("*");
    }
  });
});

describe("parseAppVersionSpec", () => {
  it("0.2.2+3 → version 0.2.2 / build 3", () => {
    expect(parseAppVersionSpec("0.2.2+3")).toEqual({
      version: "0.2.2",
      buildNumber: 3,
    });
  });

  it("缺 +build → buildNumber 0 (老 pubspec 也能跑)", () => {
    expect(parseAppVersionSpec("1.0.0")).toEqual({
      version: "1.0.0",
      buildNumber: 0,
    });
  });

  it("空 / 脏数据 → 0.0.0 + 0 (不抛异常)", () => {
    expect(parseAppVersionSpec("")).toEqual({ version: "0.0.0", buildNumber: 0 });
    expect(parseAppVersionSpec("  ")).toEqual({ version: "0.0.0", buildNumber: 0 });
    expect(parseAppVersionSpec("0.1.0+abc")).toEqual({
      version: "0.1.0",
      buildNumber: 0,
    });
  });
});
