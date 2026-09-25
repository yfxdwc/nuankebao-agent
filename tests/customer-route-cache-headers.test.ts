// ============================================
// 客户相关 route Cache-Control 响应头测试 (R-10 L3 兜底, 2026-09-26)
// 文档: docs/r9-r10-optimization.md §5.2 + §6.3
//
// 覆盖:
//   - GET /api/customers → Cache-Control: no-store
//   - GET /api/customers/[id] → no-store
//   - GET /api/customers/stats → no-store
//   - POST /api/customers → no-store (写操作也强制, 防 304 复提交)
//   - PATCH /api/customers/[id] → no-store
//   - DELETE /api/customers/[id] → no-store
//   - POST /api/customers/[id]/share → no-store
//   - DELETE /api/customers/[id]/share/[userId] → no-store
//   - GET /api/customers/[id]/share/candidates → no-store
//   - GET /api/customers/[id]/shares → no-store
//   - GET /api/customers/shares/received → no-store
//
// 不覆盖 (out of scope, 主文档 §6.5 后扩):
//   - /api/customers/[id]/ownership / bind-account / transfer / merge
//   - /api/customers/[id]/insight / charts / follow-up-analysis / audit
//
// 用 vitest mock + NextRequest 触发 route handler, 断言 response.headers
// ============================================

import { describe, it, expect, vi, beforeEach } from "vitest";

// ===== Mock: auth + billing + audit + rbac (保证 route 跑通) =====
vi.mock("@/lib/auth", () => ({
  auth: vi.fn(),
}));
vi.mock("@/lib/auth/skip-auth", () => ({
  isAuthSkipped: () => true, // dev skip-auth 模式, 让测试绕过 auth 检查
}));
vi.mock("@/lib/auth/rbac", () => ({
  getRbacContextForSession: vi.fn(async () => null),
  customerRbacFilter: vi.fn(() => undefined),
}));
vi.mock("@/lib/billing/guard", () => ({
  hasFeatureAccess: vi.fn(async () => false),
  featureGuard: vi.fn(async () => null),
}));
vi.mock("@/lib/audit/context", () => ({
  getAuditContextFromRequest: vi.fn(() => ({})),
  // softDeleteCustomer 需要 withAuditContext, 走原 DB
  withAuditContext: vi.fn(async (_ctx: unknown, fn: any) => {
    const { db } = await import("@/lib/db");
    return fn(db);
  }),
}));
// listCustomers 真正去查 DB (no mock) 也不影响, 因为没登录 → 401 早于 DB 路径
// 但 stats route 会查 DB, 用 mock 顶替让它跑通

import { NextRequest } from "next/server";

function makeRequest(url: string, init?: { method?: string; body?: unknown }): NextRequest {
  const req = new NextRequest(url, {
    method: init?.method ?? "GET",
    body: init?.body !== undefined ? JSON.stringify(init.body) : undefined,
    headers: { "content-type": "application/json" },
  });
  return req;
}

/** 断言响应头包含 Cache-Control: no-store */
function expectNoStore(headers: Headers) {
  expect(headers.get("cache-control")).toBe("no-store");
}

describe("R-10 L3: 客户相关 route Cache-Control 响应头", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("GET /api/customers → no-store (无登录 → 401 路径也要 no-store)", async () => {
    const { GET } = await import("@/app/api/customers/route");
    const res = await GET(makeRequest("http://localhost/api/customers"));
    expectNoStore(res.headers);
  });

  it("POST /api/customers → no-store (写操作强制)", async () => {
    const { POST } = await import("@/app/api/customers/route");
    const res = await POST(makeRequest("http://localhost/api/customers", { method: "POST", body: {} }));
    expectNoStore(res.headers);
  });

  it("GET /api/customers/[id] → no-store", async () => {
    const { GET } = await import("@/app/api/customers/[id]/route");
    const res = await GET(
      makeRequest("http://localhost/api/customers/1"),
      { params: Promise.resolve({ id: "1" }) },
    );
    expectNoStore(res.headers);
  });

  it("PATCH /api/customers/[id] → no-store", async () => {
    const { PATCH } = await import("@/app/api/customers/[id]/route");
    const res = await PATCH(
      makeRequest("http://localhost/api/customers/1", { method: "PATCH", body: {} }),
      { params: Promise.resolve({ id: "1" }) },
    );
    expectNoStore(res.headers);
  });

  it("DELETE /api/customers/[id] → no-store", async () => {
    const { DELETE } = await import("@/app/api/customers/[id]/route");
    const res = await DELETE(
      makeRequest("http://localhost/api/customers/1", { method: "DELETE" }),
      { params: Promise.resolve({ id: "1" }) },
    );
    expectNoStore(res.headers);
  });

  it("GET /api/customers/stats → no-store", async () => {
    const { GET } = await import("@/app/api/customers/stats/route");
    const res = await GET(makeRequest("http://localhost/api/customers/stats"));
    expectNoStore(res.headers);
  });

  it("POST /api/customers/[id]/share → no-store", async () => {
    const { POST } = await import("@/app/api/customers/[id]/share/route");
    const res = await POST(
      makeRequest("http://localhost/api/customers/1/share", { method: "POST", body: {} }),
      { params: Promise.resolve({ id: "1" }) },
    );
    expectNoStore(res.headers);
  });

  it("DELETE /api/customers/[id]/share/[userId] → no-store", async () => {
    const { DELETE } = await import("@/app/api/customers/[id]/share/[userId]/route");
    const res = await DELETE(
      makeRequest("http://localhost/api/customers/1/share/2", { method: "DELETE", body: {} }),
      { params: Promise.resolve({ id: "1", userId: "2" }) },
    );
    expectNoStore(res.headers);
  });

  it("GET /api/customers/[id]/share/candidates → no-store", async () => {
    const { GET } = await import("@/app/api/customers/[id]/share/candidates/route");
    const res = await GET(
      makeRequest("http://localhost/api/customers/1/share/candidates"),
      { params: Promise.resolve({ id: "1" }) },
    );
    expectNoStore(res.headers);
  });

  it("GET /api/customers/[id]/shares → no-store", async () => {
    const { GET } = await import("@/app/api/customers/[id]/shares/route");
    const res = await GET(
      makeRequest("http://localhost/api/customers/1/shares"),
      { params: Promise.resolve({ id: "1" }) },
    );
    expectNoStore(res.headers);
  });

  it("GET /api/customers/shares/received → no-store", async () => {
    const { GET } = await import("@/app/api/customers/shares/received/route");
    const res = await GET(makeRequest("http://localhost/api/customers/shares/received"));
    expectNoStore(res.headers);
  });
});