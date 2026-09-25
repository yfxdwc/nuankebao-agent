// ============================================
// IDOR 回归测试: GET /api/customers/[id]/follow-up-analysis
// ============================================
// 修法见 src/app/api/customers/[id]/follow-up-analysis/route.ts (P0 IDOR 修复, 2026-09-25)
// 与同仓 bind-account 端点同口径 (scope: customerRbacFilter(ctx))
//
// 覆盖 (任务书):
//   ① 自己可见范围内的客户 → 200 (返回体字段不变)
//   ② 不在范围内 (他人客户) → 404 (不泄漏存在性)
//   ③ 未登录 → 401
//   ④ 非法 id → 400

import { describe, it, expect, beforeAll, afterAll, vi } from "vitest";
import { NextRequest } from "next/server";
import { inArray, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { customer, interaction, user } from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";

// ===== Mock (vitest 自动 hoist, 必须先于 import route) =====
// 强制走真实 auth 校验 (跳过 dev skip-auth), 这样未登录场景才能拿到 401
vi.mock("@/lib/auth/skip-auth", () => ({
  isAuthSkipped: () => false,
}));
// auth() 返回值由测试按需 mock (用 mockResolvedValueOnce 注入)
vi.mock("@/lib/auth", () => ({
  auth: vi.fn(),
}));
// hasFeatureAccess 用不到, mock 避免真库查询
vi.mock("@/lib/billing/guard", () => ({
  hasFeatureAccess: vi.fn(async () => false),
}));

import { auth } from "@/lib/auth";
import { GET } from "@/app/api/customers/[id]/follow-up-analysis/route";

const TAG = `idor-followup-${Date.now()}`;
// 与 member-flag (139000021xx) / customer-scope 等测试错开手机号段
const PHONE_A = "13900003201"; // user A 自己的客户 (cidA)
const PHONE_B = "13900003202"; // user B 自己的客户 (cidB)

let uidA: bigint;
let uidB: bigint;
let cidA: bigint;
let cidB: bigint;

async function mkUser(name: string, phone: string, role = "sales"): Promise<bigint> {
  const [row] = await db
    .insert(user)
    .values({
      name,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      role,
    })
    .returning({ id: user.id });
  return row.id;
}

async function mkCustomer(
  name: string,
  phone: string,
  ownerId: bigint
): Promise<bigint> {
  const [row] = await db
    .insert(customer)
    .values({
      name,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      ownerId,
      createdBy: ownerId,
    })
    .returning({ id: customer.id });
  return row.id;
}

function mkRequest(id: string) {
  return new NextRequest(
    `http://localhost/api/customers/${id}/follow-up-analysis`
  );
}

beforeAll(async () => {
  uidA = await mkUser(`${TAG}-销售A`, PHONE_A);
  uidB = await mkUser(`${TAG}-销售B`, PHONE_B);
  cidA = await mkCustomer(`${TAG}-客户A(归A)`, PHONE_A, uidA);
  cidB = await mkCustomer(`${TAG}-客户B(归B)`, PHONE_B, uidB);

  // 给 A 的客户写一条互动, 让 ① 的返回体能断言到 contactTotal ≥ 1
  await db.insert(interaction).values({
    customerId: cidA,
    createdBy: uidA,
    createdAt: new Date(),
    type: "phone",
    summaryEncrypted: encryptField("电话回访"),
  });
});

afterAll(async () => {
  const custIds = [cidA, cidB].filter((v) => typeof v === "bigint");
  const userIds = [uidA, uidB].filter((v) => typeof v === "bigint");
  if (custIds.length) {
    await db.delete(interaction).where(inArray(interaction.customerId, custIds));
    await db.delete(customer).where(inArray(customer.id, custIds));
  }
  if (userIds.length) {
    await db.delete(user).where(inArray(user.id, userIds));
  }
  // audit trigger 写的行清掉 (避免噪音; 不阻塞测试)
  const allIds = [...userIds, ...custIds];
  if (allIds.length) {
    await db.execute(
      sql`DELETE FROM audit_log WHERE record_id IN (${sql.join(allIds, sql`, `)})`
    );
  }
});

describe("GET /api/customers/[id]/follow-up-analysis — IDOR 回归", () => {
  it("① 自己可见范围内的客户 → 200, analysis 字段 + aiTipAvailable 完整", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GET(mkRequest(String(cidA)), {
      params: Promise.resolve({ id: String(cidA) }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    // 返回体字段与修前完全一致 (合同不变)
    expect(body.contactTotal).toBeGreaterThanOrEqual(1);
    expect(typeof body.aiTipAvailable).toBe("boolean");
    expect(body.headline).toBeDefined();
    expect(typeof body.trend).toBe("string");
    expect(typeof body.contactLast30).toBe("number");
  });

  it("② 不在范围内 (他人客户 cidB, viewer 是 uidA) → 404 (不泄漏存在性)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GET(mkRequest(String(cidB)), {
      params: Promise.resolve({ id: String(cidB) }),
    });
    expect(res.status).toBe(404);
    // 校验不返回 analysis 字段 (防止泄漏)
    const body = await res.json();
    expect(body.contactTotal).toBeUndefined();
    expect(body.headline).toBeUndefined();
  });

  it("③ 未登录 (auth()=null) → 401", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce(null);
    const res = await GET(mkRequest(String(cidA)), {
      params: Promise.resolve({ id: String(cidA) }),
    });
    expect(res.status).toBe(401);
  });

  it("④ 非法 id (非数字) → 400", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GET(mkRequest("abc"), {
      params: Promise.resolve({ id: "abc" }),
    });
    expect(res.status).toBe(400);
  });

  it("跨用户看自己的客户 (uidB 看 cidB) → 200 (双向对称保护)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidB), role: "sales" },
    });
    const res = await GET(mkRequest(String(cidB)), {
      params: Promise.resolve({ id: String(cidB) }),
    });
    expect(res.status).toBe(200);
  });
});
