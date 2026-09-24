// ============================================
// setup-guard 单测 (reviewer 拍: 收紧 endsWith → 显式正则 + 抽纯函数)
//
// 不依赖真 DB, 纯函数级断言:
//   - 拒绝 /nuankebao / /production / /_test (后者以下划线开头不是小写字母)
//   - 接受 /test / /nuankebao_test
//
// 跑: DATABASE_URL=postgres://nuankebao:<pwd>@localhost:5432/nuankebao_test \
//     npx vitest run tests/setup-guard.test.ts
// ============================================

import { describe, it, expect } from "vitest";
import {
  assertTestDatabase,
  isTestDbName,
  parseDbName,
} from "./setup-guard";

describe("parseDbName", () => {
  it("从 URL 抽 pathname 去前缀 /", () => {
    expect(parseDbName("postgres://u:p@h:5432/nuankebao_test")).toBe(
      "nuankebao_test"
    );
    expect(parseDbName("postgres://u:p@h:5432/nuankebao")).toBe("nuankebao");
    expect(parseDbName("")).toBe("");
  });

  it("URL 解析失败返回空串 (不抛)", () => {
    expect(parseDbName("not a url")).toBe("");
    expect(parseDbName("://broken")).toBe("");
  });
});

describe("isTestDbName", () => {
  it("接受 /test", () => {
    expect(isTestDbName("test")).toBe(true);
  });

  it("接受 /nuankebao_test (主人机器上 dev 测试库的名字)", () => {
    expect(isTestDbName("nuankebao_test")).toBe(true);
  });

  it("接受 /my_app_v2_test (字母开头的多段)", () => {
    expect(isTestDbName("my_app_v2_test")).toBe(true);
  });

  it("拒绝 /nuankebao (dev 库)", () => {
    expect(isTestDbName("nuankebao")).toBe(false);
  });

  it("拒绝 /production (prod 库)", () => {
    expect(isTestDbName("production")).toBe(false);
  });

  it("拒绝 /_test (下划线开头, endsWith 之前能绕过; 新正则不接受)", () => {
    expect(isTestDbName("_test")).toBe(false);
  });

  it("拒绝 /prod_test_data (后缀不是 _test)", () => {
    expect(isTestDbName("prod_test_data")).toBe(false);
  });

  it("拒绝空串", () => {
    expect(isTestDbName("")).toBe(false);
  });

  it("拒绝大写字母开头 (如 /Nuankebao_test)", () => {
    expect(isTestDbName("Nuankebao_test")).toBe(false);
  });
});

describe("assertTestDatabase", () => {
  it("测试库 URL → 不抛", () => {
    expect(() =>
      assertTestDatabase("postgres://u:p@h:5432/nuankebao_test")
    ).not.toThrow();
    expect(() =>
      assertTestDatabase("postgres://u:p@h:5432/test")
    ).not.toThrow();
  });

  it("dev 库 URL → 抛错 (含明确提示)", () => {
    expect(() =>
      assertTestDatabase("postgres://u:p@h:5432/nuankebao")
    ).toThrowError(/拒绝对非测试库运行/);
  });

  it("prod 库 URL → 抛错", () => {
    expect(() =>
      assertTestDatabase("postgres://u:p@h:5432/production")
    ).toThrowError(/拒绝对非测试库运行/);
  });

  it("解析失败的 URL → 当作非测试库抛错 (不静默放过)", () => {
    expect(() => assertTestDatabase("not a url")).toThrowError(
      /拒绝对非测试库运行/
    );
  });
});