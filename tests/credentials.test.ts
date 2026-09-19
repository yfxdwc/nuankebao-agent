import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { inArray } from "drizzle-orm";
import { db } from "@/lib/db";
import { user } from "@/lib/db/schema";
import { hashPassword } from "@/lib/auth/password";
import { isPhoneIdentifier, verifyCredentials } from "@/lib/auth/credentials";
import { encryptField, hashForLookup } from "@/lib/crypto/field";

// ============================================
// 账号密码登录 集成测试 (需要 nuankebao_test 库, 见 CI / pnpm test:run 说明)
// ============================================

const FIXTURES = [
  { username: "t_cred_ok", phone: "13911110001", password: "Abcd1234", active: true },
  { username: "t_cred_phone", phone: "13911110002", password: "Abcd1234", active: true },
  { username: "t_cred_wrong", phone: "13911110003", password: "Abcd1234", active: true },
  { username: "t_cred_off", phone: "13911110004", password: "Abcd1234", active: false },
];

beforeAll(async () => {
  for (const f of FIXTURES) {
    await db
      .insert(user)
      .values({
        name: `测试-${f.username}`,
        role: "sales",
        isActive: f.active,
        phoneEncrypted: encryptField(f.phone),
        phoneHash: hashForLookup(f.phone),
        username: f.username,
        passwordHash: hashPassword(f.password),
      })
      .onConflictDoNothing({ target: user.phoneHash });
  }
});

afterAll(async () => {
  await db
    .delete(user)
    .where(inArray(user.username, FIXTURES.map((f) => f.username)));
});

describe("verifyCredentials (账号密码登录)", () => {
  it("登录名 + 正确密码 → 返回真实身份 (id 是真实用户 id)", async () => {
    const u = await verifyCredentials("t_cred_ok", "Abcd1234");
    expect(u).not.toBeNull();
    expect(u!.name).toBe("测试-t_cred_ok");
    expect(u!.id).toMatch(/^\d+$/);
  });

  it("手机号 + 正确密码 → 返回身份并回填 phone", async () => {
    const u = await verifyCredentials("13911110002", "Abcd1234");
    expect(u).not.toBeNull();
    expect(u!.name).toBe("测试-t_cred_phone");
    expect(u!.phone).toBe("13911110002");
  });

  it("密码错误 → null", async () => {
    expect(await verifyCredentials("t_cred_wrong", "Wrong9999")).toBeNull();
  });

  it("停用账号 (登录名 / 手机号) → null", async () => {
    expect(await verifyCredentials("t_cred_off", "Abcd1234")).toBeNull();
    expect(await verifyCredentials("13911110004", "Abcd1234")).toBeNull();
  });

  it("不存在账号 / 空参数 → null", async () => {
    expect(await verifyCredentials("t_cred_missing", "Abcd1234")).toBeNull();
    expect(await verifyCredentials("", "Abcd1234")).toBeNull();
    expect(await verifyCredentials("t_cred_ok", "")).toBeNull();
  });

  it("手机号判断 helper", () => {
    expect(isPhoneIdentifier("13911110001")).toBe(true);
    expect(isPhoneIdentifier("admin")).toBe(false);
  });
});
