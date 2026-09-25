// ============================================
// IDOR 回归测试: /api/follow-ups + /api/follow-ups/[id]
// ============================================
// R-12 同源 (2026-09-25, 见 docs/customer-idor-audit.md §5):
//   修前 GET / PATCH 全部只校验登录, 任何销售都能拉 / 改全库跟进任务 (含加密
//   aiSuggestion / completed_notes 解密内容 → 信息泄漏 + 可被人改状态)。
//   修法 = 跟 interactions/[id] 同口径 — 闸门装在 route 层 (单一真相源 =
//   customerRbacFilter(rbacCtx), Phase D 升级 viewerCustomerScopeSql 时只换 rbac.ts)。
//
// 覆盖 (任务书 7 例):
//   ① 他人客户的任务出现在列表中 → **不**出现
//   ② ?customerId= 别人客户 → 返回空 items (不 404, 避免泄漏存在性)
//   ③ PATCH 别人任务 → 404
//   ④ PATCH 自己任务 → 200
//   ⑤ 指派给我但客户不可见 → 可见 (规则 1 的第二段)
//   ⑥ admin 全可见 (跨范围 GET, PATCH)
//   ⑦ 未登录 → 401
//
// 防御口径 (与 bind-account / R-12 P0 一致):
//   「命中可见范围 → 2xx; 命中不到 → 404 (不外推到 403, 不泄漏存在性)」
//   GET ?customerId= 命中不到 → **空列表** (不 404, 不泄漏存在性; 与 wellness-records
//   的 404 不同口径, 任务书显式要求)
// ============================================

import { describe, it, expect, beforeAll, afterAll, vi } from "vitest";
import { NextRequest } from "next/server";
import { inArray, sql, eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { customer, followUpTask, user } from "@/lib/db/schema";
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
import { GET as GETList, POST as POSTCreate } from "@/app/api/follow-ups/route";
import { PATCH as PATCHOne } from "@/app/api/follow-ups/[id]/route";

// ===== 测试数据 =====
// 用 139000050xx 段, 错开 idor-customer-routes (139000040xx) / idor-follow-up-analysis
// (139000032xx) / member-flag (139000021xx) / 其他既有测试
const TAG = `idor-followups-${Date.now()}`;
const PHONE_A = "13900005001"; // 销售 A
const PHONE_B = "13900005002"; // 销售 B
const PHONE_ADMIN = "13900005003"; // 管理员

let uidA: bigint;
let uidB: bigint;
let uidAdmin: bigint;
let cidA: bigint; // 归 A 的客户
let cidB: bigint; // 归 B 的客户
let taskA1: bigint; // 客户 A 的任务 1 (指派 A)
let taskA2: bigint; // 客户 A 的任务 2 (指派 B — 跨指派场景)
let taskAssignedToA: bigint; // 客户 B 的任务 (指派 A, 但客户归 B → 规则 1 第二段验证)
let taskB1: bigint; // 客户 B 的任务 1 (指派 B)

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

async function mkTask(
  customerId: bigint,
  assignedTo: bigint | null,
  reason: string
): Promise<bigint> {
  // 跟 createFollowUpTask 的字段对齐 (dueAt / reason / status='pending' / assignedTo)
  const [row] = await db
    .insert(followUpTask)
    .values({
      customerId,
      dueAt: new Date("2026-12-01T10:00:00Z"),
      reason,
      status: "pending",
      assignedTo,
    })
    .returning({ id: followUpTask.id });
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

function mkPost(url: string, body: unknown) {
  return new NextRequest(url, {
    method: "POST",
    body: JSON.stringify(body),
    headers: { "content-type": "application/json" },
  });
}

beforeAll(async () => {
  uidA = await mkUser(`${TAG}-销售A`, PHONE_A, "sales");
  uidB = await mkUser(`${TAG}-销售B`, PHONE_B, "sales");
  uidAdmin = await mkUser(`${TAG}-管理员`, PHONE_ADMIN, "admin");

  cidA = await mkCustomer(`${TAG}-客户A(归A)`, PHONE_A, uidA);
  cidB = await mkCustomer(`${TAG}-客户B(归B)`, PHONE_B, uidB);

  // 任务 1: A 的客户, 指派给 A (基线 — 卖家可见 + 自己持有)
  taskA1 = await mkTask(cidA, uidA, "A 客户任务 (指派 A)");
  // 任务 2: A 的客户, 指派给 B (跨指派 — A 仍可看见, 因为客户在范围内)
  taskA2 = await mkTask(cidA, uidB, "A 客户任务 (指派 B)");
  // 任务 3: B 的客户, 指派给 A (规则 1 第二段: 客户不在 A 范围, 但指派给我 → 可见)
  taskAssignedToA = await mkTask(cidB, uidA, "B 客户任务 (指派 A)");
  // 任务 4: B 的客户, 指派给 B (基线 — A 不可见, B 可见)
  taskB1 = await mkTask(cidB, uidB, "B 客户任务 (指派 B)");
});

afterAll(async () => {
  const taskIds = [taskA1, taskA2, taskAssignedToA, taskB1].filter(
    (v) => typeof v === "bigint"
  );
  const custIds = [cidA, cidB].filter((v) => typeof v === "bigint");
  const userIds = [uidA, uidB, uidAdmin].filter((v) => typeof v === "bigint");

  if (taskIds.length) {
    await db.delete(followUpTask).where(inArray(followUpTask.id, taskIds));
  }
  if (custIds.length) {
    await db.delete(customer).where(inArray(customer.id, custIds));
  }
  if (userIds.length) {
    await db.delete(user).where(inArray(user.id, userIds));
  }
  // audit trigger 写的行清掉 (避免噪音; 不阻塞测试)
  const allIds = [...taskIds, ...custIds, ...userIds];
  if (allIds.length) {
    await db.execute(
      sql`DELETE FROM audit_log WHERE record_id IN (${sql.join(allIds, sql`, `)})`
    );
  }
});

// ============================================================
// 1. GET /api/follow-ups — 列表可见性
// ============================================================
describe("GET /api/follow-ups — IDOR 修复 (列表可见性)", () => {
  it("① 不传 customerId — 他人客户 (cidB) 的任务出现在 A 的列表中 → **不**出现", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETList(mkGet("http://localhost/api/follow-ups"));
    expect(res.status).toBe(200);
    const body = await res.json();
    // A 可见范围: taskA1 (客户在范围内 + 指派 A) + taskA2 (客户在范围内 + 指派 B)
    //            + taskAssignedToA (客户**不**在范围内 + 指派 A → 规则 1 第二段仍可见)
    // A **不**可见: taskB1 (客户**不**在范围内 + 指派 B)
    const ids = body.items.map((i: { id: string }) => i.id);
    expect(ids).toContain(String(taskA1));
    expect(ids).toContain(String(taskA2));
    expect(ids).toContain(String(taskAssignedToA));
    expect(ids).not.toContain(String(taskB1));
  });

  it("② ?customerId= 别人客户 (cidB, A 没有) → 返回仅指派给 A 的任务 (不 404, 不返回 B 专属任务)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETList(
      mkGet(`http://localhost/api/follow-ups?customerId=${cidB}`)
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    const ids = body.items.map((i: { id: string }) => i.id);
    // 规则 1 第二段: taskAssignedToA 在 cidB 上且指派给 A → 仍可见
    expect(ids).toContain(String(taskAssignedToA));
    // 规则 1 另半: taskB1 在 cidB 上且指派给 B → 不可见 (cidB 不在 A 范围, 也不指派 A)
    expect(ids).not.toContain(String(taskB1));
    expect(body.error).toBeUndefined();
  });

  it("②b ?customerId= 完全不可见的客户 (B 的客户但 B 也没任务 + 不指派 A 的人) → 空列表", async () => {
    // 临时再建一个客户归 B + 一个指派给 B 的任务, 跟 taskB1 / taskAssignedToA 完全无重叠
    // 不需重建: 直接用 admin 创一条客户 C 归 B, 任务 taskC 指派 B; A 查询 ?customerId= C → 空
    const cidC = await mkCustomer(`${TAG}-客户C(归B)`, "13900005004", uidB);
    const taskC = await mkTask(cidC, uidB, "C 客户任务");
    try {
      (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
        user: { id: String(uidA), role: "sales" },
      });
      const res = await GETList(
        mkGet(`http://localhost/api/follow-ups?customerId=${cidC}`)
      );
      expect(res.status).toBe(200);
      const body = await res.json();
      expect(body.items).toEqual([]);
      expect(body.total).toBe(0);
      expect(body.error).toBeUndefined();
    } finally {
      await db.delete(followUpTask).where(eq(followUpTask.id, taskC));
      await db.delete(customer).where(eq(customer.id, cidC));
    }
  });

  it("③ ?customerId= 别人客户 (cidB), viewer 是 B → 200, 含自己任务", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidB), role: "sales" },
    });
    const res = await GETList(
      mkGet(`http://localhost/api/follow-ups?customerId=${cidB}`)
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    const ids = body.items.map((i: { id: string }) => i.id);
    expect(ids).toContain(String(taskB1));
    expect(ids).toContain(String(taskAssignedToA)); // 也指派给 A 的, A = B 自己
  });

  it("④ 未登录 → 401", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce(null);
    const res = await GETList(mkGet("http://localhost/api/follow-ups"));
    expect(res.status).toBe(401);
  });

  it("⑤ ?assignedTo= 别人 (uidB) + 客户在范围 (cidA) → 仍可见 (assign 是 filter, 不是 visibility)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await GETList(
      mkGet(`http://localhost/api/follow-ups?assignedTo=${uidB}&customerId=${cidA}`)
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    const ids = body.items.map((i: { id: string }) => i.id);
    expect(ids).toContain(String(taskA2)); // 客户在 A 范围内 + 指派给 B
    expect(ids).not.toContain(String(taskA1)); // 指派给 A, 被 assignedTo=B 过滤掉
  });
});

// ============================================================
// 2. GET /api/follow-ups — admin 全可见
// ============================================================
describe("GET /api/follow-ups — admin 全可见", () => {
  it("⑥ admin 不传 customerId → 看到所有任务 (跨范围)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidAdmin), role: "admin" },
    });
    const res = await GETList(mkGet("http://localhost/api/follow-ups"));
    expect(res.status).toBe(200);
    const body = await res.json();
    const ids = body.items.map((i: { id: string }) => i.id);
    expect(ids).toContain(String(taskA1));
    expect(ids).toContain(String(taskA2));
    expect(ids).toContain(String(taskAssignedToA));
    expect(ids).toContain(String(taskB1));
  });

  it("⑥b admin ?customerId= 别人客户 → 200, 含对应任务", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidAdmin), role: "admin" },
    });
    const res = await GETList(
      mkGet(`http://localhost/api/follow-ups?customerId=${cidB}`)
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    const ids = body.items.map((i: { id: string }) => i.id);
    expect(ids).toContain(String(taskB1));
  });
});

// ============================================================
// 3. PATCH /api/follow-ups/[id] — 写可见性
// ============================================================
describe("PATCH /api/follow-ups/[id] — IDOR 修复 (写可见性)", () => {
  it("① PATCH 别人的任务 (taskB1 — 客户归 B + 指派 B) → 404", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await PATCHOne(
      mkPatch(`http://localhost/api/follow-ups/${taskB1}`, { action: "complete" }),
      { params: Promise.resolve({ id: String(taskB1) }) }
    );
    expect(res.status).toBe(404);
    // 校验不泄漏 reason (不返回 task 字段)
    const body = await res.json();
    expect(body.reason).toBeUndefined();
    expect(body.status).toBeUndefined();
  });

  it("①b PATCH 别人的任务, UPDATE **实际不发** (DB 验证)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    await PATCHOne(
      mkPatch(`http://localhost/api/follow-ups/${taskB1}`, { action: "complete" }),
      { params: Promise.resolve({ id: String(taskB1) }) }
    );
    // 通过 B 自己 GET 列表验证 taskB1 仍是 pending
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidB), role: "sales" },
    });
    const listRes = await GETList(
      mkGet(`http://localhost/api/follow-ups?customerId=${cidB}`)
    );
    const listBody = await listRes.json();
    const stillPending = listBody.items.find(
      (i: { id: string; status: string }) => i.id === String(taskB1)
    );
    expect(stillPending).toBeDefined();
    expect(stillPending.status).toBe("pending");
  });

  it("② PATCH 自己的任务 (taskA1 — 客户归 A + 指派 A) → 200", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await PATCHOne(
      mkPatch(`http://localhost/api/follow-ups/${taskA1}`, {
        action: "complete",
        notes: "A 自己完成",
      }),
      { params: Promise.resolve({ id: String(taskA1) }) }
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("done");
    expect(body.completedNotes).toBe("A 自己完成");
  });

  it("⑤ PATCH 指派给我但客户不在我范围 (taskAssignedToA — 客户归 B + 指派 A) → 200 (规则 1 第二段)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await PATCHOne(
      mkPatch(`http://localhost/api/follow-ups/${taskAssignedToA}`, {
        action: "complete",
        notes: "A 跨客户完成",
      }),
      { params: Promise.resolve({ id: String(taskAssignedToA) }) }
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("done");
    expect(body.assignedTo).toBe(String(uidA));
  });

  it("⑥ PATCH 跨范围任务, viewer 是 admin → 200 (admin 豁免 scope)", async () => {
    // 先取一个 pending 任务 (前面 taskA2 仍 pending, 用它)
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidAdmin), role: "admin" },
    });
    const res = await PATCHOne(
      mkPatch(`http://localhost/api/follow-ups/${taskA2}`, { action: "complete" }),
      { params: Promise.resolve({ id: String(taskA2) }) }
    );
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("done");
  });

  it("⑦ 未登录 PATCH → 401", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce(null);
    // 用一个存在的 id (避免「任务不存在」的 404 与「未登录」的 401 混淆)
    const res = await PATCHOne(
      mkPatch(`http://localhost/api/follow-ups/${taskB1}`, { action: "complete" }),
      { params: Promise.resolve({ id: String(taskB1) }) }
    );
    expect(res.status).toBe(401);
  });

  it("非法 id (非数字) → 400", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await PATCHOne(
      mkPatch(`http://localhost/api/follow-ups/abc`, { action: "complete" }),
      { params: Promise.resolve({ id: "abc" }) }
    );
    expect(res.status).toBe(400);
  });

  it("不存在的 id → 404 (不泄漏存在性)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await PATCHOne(
      mkPatch(`http://localhost/api/follow-ups/999999999999`, { action: "complete" }),
      { params: Promise.resolve({ id: "999999999999" }) }
    );
    expect(res.status).toBe(404);
  });
});

// ============================================================
// 4. POST /api/follow-ups — 写侧 customerId 范围校验
// ============================================================
describe("POST /api/follow-ups — IDOR 写侧 (customerId 不在范围 → 400)", () => {
  it("POST 给别人客户 (cidB, A 没有) → 400, 不创建任务", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await POSTCreate(
      mkPost("http://localhost/api/follow-ups", {
        customerId: String(cidB),
        dueAt: "2026-12-15T10:00:00Z",
        reason: "越权给 B 的客户建任务",
      })
    );
    expect(res.status).toBe(400);
    const body = await res.json();
    expect(body.error).toMatch(/scope/i);

    // DB 验证: 真的没建
    const rows = await db
      .select({ id: followUpTask.id })
      .from(followUpTask)
      .where(sql`${followUpTask.reason} = '越权给 B 的客户建任务'`);
    expect(rows.length).toBe(0);
  });

  it("POST 给自己客户 (cidA) → 201, 创建成功", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await POSTCreate(
      mkPost("http://localhost/api/follow-ups", {
        customerId: String(cidA),
        dueAt: "2026-12-15T10:00:00Z",
        reason: "A 给自己建任务",
      })
    );
    expect(res.status).toBe(201);
    const body = await res.json();
    expect(body.reason).toBe("A 给自己建任务");
    expect(body.customerId).toBe(String(cidA));

    // 清理这条临时任务, 不影响其他测试
    await db.delete(followUpTask).where(eq(followUpTask.id, BigInt(body.id)));
  });

  it("POST admin → 跨范围 201 (admin 豁免)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidAdmin), role: "admin" },
    });
    const res = await POSTCreate(
      mkPost("http://localhost/api/follow-ups", {
        customerId: String(cidB),
        dueAt: "2026-12-15T10:00:00Z",
        reason: "admin 跨范围建任务",
      })
    );
    expect(res.status).toBe(201);

    // 清理
    const body = await res.json();
    await db.delete(followUpTask).where(eq(followUpTask.id, BigInt(body.id)));
  });

  it("POST 未登录 → 401", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce(null);
    const res = await POSTCreate(
      mkPost("http://localhost/api/follow-ups", {
        customerId: String(cidA),
        dueAt: "2026-12-15T10:00:00Z",
        reason: "未登录建任务",
      })
    );
    expect(res.status).toBe(401);
  });

  it("POST 非法 customerId (非数字) → 400 (zod 校验, 不到 route 范围检查)", async () => {
    (auth as unknown as ReturnType<typeof vi.fn>).mockResolvedValueOnce({
      user: { id: String(uidA), role: "sales" },
    });
    const res = await POSTCreate(
      mkPost("http://localhost/api/follow-ups", {
        customerId: "abc",
        dueAt: "2026-12-15T10:00:00Z",
        reason: "非法 customerId",
      })
    );
    expect(res.status).toBe(400);
  });
});

