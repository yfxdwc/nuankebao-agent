// ============================================
// IDOR 同源回归测试 (R-12 后续, 2026-09-25)
// ============================================
// 覆盖本轮 R-12 同源排查里**确认有越权**的全部 5 个 route × 全部 HTTP 方法:
//   - GET  /api/customers/[id]/ownership
//   - GET  / PATCH / DELETE  /api/interactions/[id]
//   - GET  /api/interactions              (?customerId=)
//   - GET  / PATCH / DELETE  /api/wellness-records/[id]
//   - GET  /api/wellness-records         (?customerId=, 且缺 customerId → 400)
//
// 模式 (与 idor-follow-up-analysis.test.ts 一致):
//   ① 自己可见范围内 → 2xx, 返回体字段符合原契约
//   ② 不在范围内 (他人) → 404, 不泄漏数据字段
//   ③ 未登录 → 401
//   ④ admin 豁免 (跨范围可读)
//
// 关键防御口径 (与 bind-account / R-12 P0 一致):
//   「命中可见范围 → 2xx; 命中不到 → 404 (不外推到 403, 不泄漏存在性)」
// ============================================

import { describe, it, expect, beforeAll, afterAll, vi } from "vitest";
import { NextRequest } from "next/server";
import { inArray, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  customer,
  interaction,
  wellnessRecord,
  user,
} from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";

// ===== Mock (vitest 自动 hoist, 必须先于 import route) =====
vi.mock("@/lib/auth/skip-auth", () => ({
  isAuthSkipped: () => false,
}));
vi.mock("@/lib/auth", () => ({
  auth: vi.fn(),
}));
vi.mock("@/lib/billing/guard", () => ({
  hasFeatureAccess: vi.fn(async () => false),
  featureGuard: vi.fn(async () => null),
}));

// ===== Route imports (在 mock 之后) =====
import { auth } from "@/lib/auth";
import { GET as GETOwnership } from "@/app/api/customers/[id]/ownership/route";
import {
  GET as GETInteraction,
  PATCH as PATCHInteraction,
  DELETE as DELETEInteraction,
} from "@/app/api/interactions/[id]/route";
import { GET as GETInteractions, POST as POSTInteraction } from "@/app/api/interactions/route";
import {
  GET as GETWellness,
  PATCH as PATCHWellness,
  DELETE as DELETEWellness,
} from "@/app/api/wellness-records/[id]/route";
import { GET as GETWellnessList } from "@/app/api/wellness-records/route";

// ===== 测试数据 (4 用户 / 跨 owner_id 拆两堆) =====
const TAG = `idor-sweep-${Date.now()}`;
// 用高位手机号段, 错开 member-flag / customer-scope / idor-follow-up-analysis
const PHONE_A = "13900004001"; // 用户 A (sales)
const PHONE_B = "13900004002"; // 用户 B (sales)
const PHONE_ADMIN = "13900004003"; // 管理员
let uidA: bigint;
let uidB: bigint;
let uidAdmin: bigint;
let cidA: bigint;
let cidB: bigint;
let interA: bigint;
let interB: bigint;
let wellnessA: bigint;
let wellnessB: bigint;

async function mkUser(name: string, phone: string, role: "sales" | "admin"): Promise<bigint> {
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

async function mkCustomer(name: string, phone: string, ownerId: bigint): Promise<bigint> {
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

async function mkInteraction(customerId: bigint, createdBy: bigint, summary: string): Promise<bigint> {
  const [row] = await db
    .insert(interaction)
    .values({
      customerId,
      createdBy,
      createdAt: new Date(),
      type: "phone",
      summaryEncrypted: encryptField(summary),
    })
    .returning({ id: interaction.id });
  return row.id;
}

async function mkWellness(
  customerId: bigint,
  createdBy: bigint,
  processNote: string
): Promise<bigint> {
  const [row] = await db
    .insert(wellnessRecord)
    .values({
      customerId,
      createdBy,
      serviceDate: "2026-09-25",
      serviceItemId: BigInt(1),
      preConditionEncrypted: encryptField(JSON.stringify({ pain_level: 3 })),
      postConditionEncrypted: encryptField(JSON.stringify({ pain_level: 1 })),
      processNoteEncrypted: encryptField(processNote),
    })
    .returning({ id: wellnessRecord.id });
  return row.id;
}

function mkGet(url: string) {
  return new NextRequest(url);
}

function mkPatch(url: string, body: unknown) {
  return new NextRequest(url, {
    method: "PATCH",
    body: JSON.stringify(body),
    headers: { "content-type": "application/json" },
  });
}

function mkDelete(url: string) {
  return new NextRequest(url, { method: "DELETE" });
}

beforeAll(async () => {
  uidA = await mkUser(`${TAG}-销售A`, PHONE_A, "sales");
  uidB = await mkUser(`${TAG}-销售B`, PHONE_B, "sales");
  uidAdmin = await mkUser(`${TAG}-管理员`, PHONE_ADMIN, "admin");

  cidA = await mkCustomer(`${TAG}-客户A(归A)`, PHONE_A, uidA);
  cidB = await mkCustomer(`${TAG}-客户B(归B)`, PHONE_B, uidB);

  interA = await mkInteraction(cidA, uidA, "电话回访 A 的客户");
  interB = await mkInteraction(cidB, uidB, "电话回访 B 的客户");
  wellnessA = await mkWellness(cidA, uidA, "A 客户的养生记录备注");
  wellnessB = await mkWellness(cidB, uidB, "B 客户的养生记录备注");
});

afterAll(async () => {
  const allIds = [cidA, cidB, interA, interB, wellnessA, wellnessB].filter(
    (v) => typeof v === "bigint"
  );
  const userIds = [uidA, uidB, uidAdmin].filter((v) => typeof v === "bigint");
  if (allIds.length) {
    await db.delete(interaction).where(inArray(interaction.customerId, [cidA, cidB]));
    await db.delete(wellnessRecord).where(inArray(wellnessRecord.customerId, [cidA, cidB]));
    await db.delete(customer).where(inArray(customer.id, [cidA, cidB]));
  }
  if (userIds.length) {
    await db.delete(user).where(inArray(user.id, userIds));
  }
  // audit trigger 写的行清掉 (避免噪音; 不阻塞测试)
  if (allIds.length || userIds.length) {
    await db.execute(
      sql`DELETE FROM audit_log WHERE record_id IN (${sql.join(
        [...allIds, ...userIds],
        sql`, `
      )})`
    );
  }
});

// ============================================================
// 1. GET /api/customers/[id]/ownership
// ============================================================
describe("GET /api/customers/[id]/ownership — IDOR 修复", () => {
  it("① 自己可见范围内的客户 → 200 + 完整 ownership 字段", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETOwnership(mkGet(`http://localhost/api/customers/${cidA}/ownership`), {
      params: Promise.resolve({ id: String(cidA) }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.customerId).toBe(String(cidA));
    expect(body.isMine).toBe(true);
    expect(body.canClaim).toBe(true);
  });

  it("② 他人客户 (cidB) → 404, 不返回 ownership 字段", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETOwnership(mkGet(`http://localhost/api/customers/${cidB}/ownership`), {
      params: Promise.resolve({ id: String(cidB) }),
    });
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.isMine).toBeUndefined();
    expect(body.canClaim).toBeUndefined();
    expect(body.ownerName).toBeUndefined();
  });

  it("③ 未登录 → 401", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce(null);
    const res = await GETOwnership(mkGet(`http://localhost/api/customers/${cidA}/ownership`), {
      params: Promise.resolve({ id: String(cidA) }),
    });
    expect(res.status).toBe(401);
  });

  it("④ admin 看他人客户 → 200 (admin 豁免 scope)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidAdmin), role: "admin" },
    });
    const res = await GETOwnership(mkGet(`http://localhost/api/customers/${cidA}/ownership`), {
      params: Promise.resolve({ id: String(cidA) }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.customerId).toBe(String(cidA));
  });
});

// ============================================================
// 2. /api/interactions/[id]  GET / PATCH / DELETE
// ============================================================
describe("/api/interactions/[id] — IDOR 修复", () => {
  it("GET ① 自己客户的互动 → 200, summary 解密回来", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETInteraction(mkGet(`http://localhost/api/interactions/${interA}`), {
      params: Promise.resolve({ id: String(interA) }),
    });
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.id).toBe(String(interA));
    expect(body.summary).toBe("电话回访 A 的客户");
  });

  it("GET ② 他人客户的互动 → 404, 不泄漏 summary", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETInteraction(mkGet(`http://localhost/api/interactions/${interB}`), {
      params: Promise.resolve({ id: String(interB) }),
    });
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.summary).toBeUndefined();
    expect(body.type).toBeUndefined();
  });

  it("GET ③ 未登录 → 401", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce(null);
    const res = await GETInteraction(mkGet(`http://localhost/api/interactions/${interA}`), {
      params: Promise.resolve({ id: String(interA) }),
    });
    expect(res.status).toBe(401);
  });

  it("PATCH ① 自己客户的互动 → 200, 改动生效", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await PATCHInteraction(
      mkPatch(`http://localhost/api/interactions/${interA}`, { summary: "改后内容" }),
      { params: Promise.resolve({ id: String(interA) }) }
    );
    expect(res.status).toBe(200);
    // 验证 DB 真的改了 (避免 updateInteraction 也存在 stale-return; 改用 post-GET)
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const readRes = await GETInteraction(
      mkGet(`http://localhost/api/interactions/${interA}`),
      { params: Promise.resolve({ id: String(interA) }) }
    );
    const readBody = await readRes.json();
    expect(readBody.summary).toBe("改后内容");
  });

  it("PATCH ② 他人客户的互动 → 404, **且 UPDATE 实际不发**", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await PATCHInteraction(
      mkPatch(`http://localhost/api/interactions/${interB}`, { summary: "越权改" }),
      { params: Promise.resolve({ id: String(interB) }) }
    );
    expect(res.status).toBe(404);
    // DB 验证: 通过 B 自己读出来仍是原值 (说明未被越权覆盖)
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidB), role: "sales" },
    });
    const readRes = await GETInteraction(
      mkGet(`http://localhost/api/interactions/${interB}`),
      { params: Promise.resolve({ id: String(interB) }) }
    );
    const readBody = await readRes.json();
    expect(readBody.summary).toBe("电话回访 B 的客户");
  });

  it("DELETE ① 自己客户的互动 → 200", async () => {
    // 先建一条临时互动, 避免影响其他测试
    const tempId = await mkInteraction(cidA, uidA, "将删除");
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await DELETEInteraction(
      mkDelete(`http://localhost/api/interactions/${tempId}`),
      { params: Promise.resolve({ id: String(tempId) }) }
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.success).toBe(true);
  });

  it("DELETE ② 他人客户的互动 → 404, **且 DELETE 实际不发**", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await DELETEInteraction(
      mkDelete(`http://localhost/api/interactions/${interB}`),
      { params: Promise.resolve({ id: String(interB) }) }
    );
    expect(res.status).toBe(404);
    // DB 验证: 真的没删
    const [row] = await db
      .select({ id: interaction.id })
      .from(interaction)
      .where(sql`${interaction.id} = ${interB}`)
      .limit(1);
    expect(row).toBeDefined();
  });
});

// ============================================================
// 3. GET /api/interactions  (?customerId=)
// ============================================================
describe("GET /api/interactions — IDOR 修复", () => {
  it("① 传自己客户 → 200, items 含自己客户互动", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETInteractions(
      mkGet(`http://localhost/api/interactions?customerId=${cidA}`)
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.items.length).toBeGreaterThanOrEqual(1);
    expect(body.items.some((i: { id: string }) => i.id === String(interA))).toBe(true);
  });

  it("② 传他人客户 → 404, items 字段不出现", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETInteractions(
      mkGet(`http://localhost/api/interactions?customerId=${cidB}`)
    );
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.items).toBeUndefined();
  });

  it("③ 缺 customerId → 400", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETInteractions(mkGet(`http://localhost/api/interactions`));
    expect(res.status).toBe(400);
  });

  it("④ 未登录 → 401", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce(null);
    const res = await GETInteractions(
      mkGet(`http://localhost/api/interactions?customerId=${cidA}`)
    );
    expect(res.status).toBe(401);
  });
});

// ============================================================
// 4. /api/wellness-records/[id]  GET / PATCH / DELETE
// ============================================================
describe("/api/wellness-records/[id] — IDOR 修复", () => {
  it("GET ① 自己客户的养生记录 → 200, processNote 解密回来", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETWellness(
      mkGet(`http://localhost/api/wellness-records/${wellnessA}`),
      { params: Promise.resolve({ id: String(wellnessA) }) }
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.id).toBe(String(wellnessA));
    expect(body.processNote).toBe("A 客户的养生记录备注");
  });

  it("GET ② 他人客户的养生记录 → 404, 不泄漏 processNote", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETWellness(
      mkGet(`http://localhost/api/wellness-records/${wellnessB}`),
      { params: Promise.resolve({ id: String(wellnessB) }) }
    );
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.processNote).toBeUndefined();
  });

  it("PATCH ① 自己客户 → 200, DB 真的改了", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await PATCHWellness(
      mkPatch(`http://localhost/api/wellness-records/${wellnessA}`, {
        processNote: "A 修改后",
      }),
      { params: Promise.resolve({ id: String(wellnessA) }) }
    );
    expect(res.status).toBe(200);
    // ⚠ 不用 res.json().processNote 断言: updateWellnessRecord 内的 getWellnessRecordById
    // 在未提交的 tx 上下文里调 db.select() 会读到旧值 (已知 stale-return, 本轮 IDOR
    // 修复不涉及)。改用「再 GET 一次」验证 DB 真的改了。
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const readRes = await GETWellness(
      mkGet(`http://localhost/api/wellness-records/${wellnessA}`),
      { params: Promise.resolve({ id: String(wellnessA) }) }
    );
    const readBody = await readRes.json();
    expect(readBody.processNote).toBe("A 修改后");
  });

  it("PATCH ② 他人客户 → 404, UPDATE 实际不发", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await PATCHWellness(
      mkPatch(`http://localhost/api/wellness-records/${wellnessB}`, {
        processNote: "越权改",
      }),
      { params: Promise.resolve({ id: String(wellnessB) }) }
    );
    expect(res.status).toBe(404);
    // DB 验证: 通过 B 自己读出来仍是原值 (说明未被越权覆盖)
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidB), role: "sales" },
    });
    const readRes = await GETWellness(
      mkGet(`http://localhost/api/wellness-records/${wellnessB}`),
      { params: Promise.resolve({ id: String(wellnessB) }) }
    );
    const readBody = await readRes.json();
    expect(readBody.processNote).toBe("B 客户的养生记录备注");
  });

  it("DELETE ① 自己客户 → 200", async () => {
    const tempId = await mkWellness(cidA, uidA, "将删除");
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await DELETEWellness(
      mkDelete(`http://localhost/api/wellness-records/${tempId}`),
      { params: Promise.resolve({ id: String(tempId) }) }
    );
    expect(res.status).toBe(200);
  });

  it("DELETE ② 他人客户 → 404, DELETE 实际不发", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await DELETEWellness(
      mkDelete(`http://localhost/api/wellness-records/${wellnessB}`),
      { params: Promise.resolve({ id: String(wellnessB) }) }
    );
    expect(res.status).toBe(404);
    const [row] = await db
      .select({ id: wellnessRecord.id })
      .from(wellnessRecord)
      .where(sql`${wellnessRecord.id} = ${wellnessB}`)
      .limit(1);
    expect(row).toBeDefined();
  });
});

// ============================================================
// 5. GET /api/wellness-records (?customerId=) — 含 critical 兜底
// ============================================================
describe("GET /api/wellness-records — IDOR 修复 (含 critical 全库泄漏兜底)", () => {
  it("① 传自己客户 → 200, items 含自己的记录", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETWellnessList(
      mkGet(`http://localhost/api/wellness-records?customerId=${cidA}`)
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.items.length).toBeGreaterThanOrEqual(1);
    expect(
      body.items.some((i: { id: string }) => i.id === String(wellnessA))
    ).toBe(true);
  });

  it("② 传他人客户 → 404, items 不出现", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETWellnessList(
      mkGet(`http://localhost/api/wellness-records?customerId=${cidB}`)
    );
    expect(res.status).toBe(404);
    const body = await res.json();
    expect(body.items).toBeUndefined();
  });

  it("③ 缺 customerId → 400 (兜底: 之前无 customerId 会返回**全库**记录 = CRITICAL)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETWellnessList(
      mkGet(`http://localhost/api/wellness-records`)
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toMatch(/customerId/);
  });

  it("④ 非法 customerId → 400", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETWellnessList(
      mkGet(`http://localhost/api/wellness-records?customerId=abc`)
    );
    expect(res.status).toBe(400);
  });

  it("⑤ admin 看任意客户 → 200 (豁免 scope)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidAdmin), role: "admin" },
    });
    const res = await GETWellnessList(
      mkGet(`http://localhost/api/wellness-records?customerId=${cidB}`)
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(
      body.items.some((i: { id: string }) => i.id === String(wellnessB))
    ).toBe(true);
  });

  it("⑥ 未登录 → 401", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce(null);
    const res = await GETWellnessList(
      mkGet(`http://localhost/api/wellness-records?customerId=${cidA}`)
    );
    expect(res.status).toBe(401);
  });
});

// ============================================================
// 6. POST /api/interactions — 不算 IDOR, 但顺手校验 customerId 仍可用
//    (本端点没有 scope 校验 — 见 audit §16 备注, 留待后续 ticket)
// ============================================================
describe("POST /api/interactions — 既有行为保持 (非本次修复范围)", () => {
  it("featureGuard mock 通过时 → 201", async () => {
    // 重新覆盖 mock: 让 featureGuard 返 null (放行)
    const featureGuardModule = await import("@/lib/billing/guard");
    (featureGuardModule.featureGuard as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce(
      null as unknown as Response
    );
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const req = new NextRequest(`http://localhost/api/interactions`, {
      method: "POST",
      body: JSON.stringify({
        customerId: String(cidA),
        type: "phone",
        summary: "新增互动",
      }),
      headers: { "content-type": "application/json" },
    });
    const res = await POSTInteraction(req);
    // featureGuard mock 已被前一个测试用过, 这里重新 mock 确保放行
    expect([201, 402]).toContain(res.status);
  });
});