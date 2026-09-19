import { describe, it, expect } from "vitest";
import {
  hashPassword,
  verifyPassword,
  isValidPassword,
} from "@/lib/auth/password";

describe("password (scrypt)", () => {
  it("hashPassword 输出 scrypt$N$salt$hash 格式, 且两次加盐不同", () => {
    const a = hashPassword("Abcd1234");
    const b = hashPassword("Abcd1234");
    expect(a).toMatch(/^scrypt\$16384\$[0-9a-f]{32}\$[0-9a-f]{128}$/);
    expect(a).not.toBe(b); // 随机盐
  });

  it("正确密码校验通过", () => {
    const stored = hashPassword("Abcd1234");
    expect(verifyPassword("Abcd1234", stored)).toBe(true);
  });

  it("错误密码 / 空存储 / 垃圾格式 一律 false", () => {
    const stored = hashPassword("Abcd1234");
    expect(verifyPassword("Wrong9999", stored)).toBe(false);
    expect(verifyPassword("Abcd1234", null)).toBe(false);
    expect(verifyPassword("Abcd1234", "")).toBe(false);
    expect(verifyPassword("Abcd1234", "bcrypt$xx$yy")).toBe(false);
    expect(verifyPassword("Abcd1234", "scrypt$notanumber$aabb$ccdd")).toBe(false);
    expect(verifyPassword("Abcd1234", "scrypt$16384$zz$aa")).toBe(false);
  });

  it("密码强度: ≥8 位且同时含字母和数字", () => {
    expect(isValidPassword("Abcd1234")).toBe(true);
    expect(isValidPassword("a1b2c3d4")).toBe(true);
    expect(isValidPassword("12345678")).toBe(false); // 纯数字
    expect(isValidPassword("abcdefgh")).toBe(false); // 纯字母
    expect(isValidPassword("Ab1")).toBe(false); // 太短
    expect(isValidPassword("")).toBe(false);
  });
});
