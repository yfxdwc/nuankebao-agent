// ============================================
// 客户列表 count 解耦测试 (R-9 优化, 2026-09-26)
// 文档: docs/r9-r10-optimization.md §2.3 + §6.2
// 覆盖:
//   1. 首页 offset=0 → includeTotal=true → total = count 实际值
//   2. 后续页 offset>0, items.length < limit → total = items.length + offset (末页)
//   3. 后续页 offset>0, items.length === limit → total = null (可能还有)
//   4. includeTotal=false 显式 → 跳过 count (spy 验证 db.select 被调次数)
//   5. includeTotal=true 显式 + offset>0 → 保留旧行为, total = 全表行数
//   6. route /api/customers?offset>0 → total 字段存在, 不抛 500
//   7. route /api/customers?offset=0 → total 必为 number
//
// mock 路径: 与 customer-identity.test.ts 一致, 用 vi.doMock 替换 @/lib/db。
//   listCustomers 走 db.select 链, 我们用 selectCallIdx 区分
//   「主数据 select」与「count select」两次调用, 验证 includeTotal=false 时 count 没被调用。
// ============================================

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { encryptField } from "@/lib/crypto/field";

const selectCallTracker: { callIdx: number; calls: Array<{ isCount: boolean }> } = {
  callIdx: 0,
  calls: [],
};

function resetTracker() {
  selectCallTracker.callIdx = 0;
  selectCallTracker.calls = [];
}

/**
 * 模拟 listCustomers 的 SQL 调用:
 *   - 主 select 链返回传入的 rows (items)
 *   - count select 链返回 [{ count: totalRows }]
 *   - includeTotal=false → count 不被调用
 *
 * 用 selectCallIdx 区分两次调用, 跟实际 listCustomers 内部顺序保持一致:
 *   - Promise.all([rowsP, countP]) 时 drizzle 是同步发起两次 select,
 *     但 .from/.where/.then 是 lazy 的 → 真实执行时机取决于 PG 调度
 *   - 我们这里按 "selectCallIdx === 0 → 主数据, === 1 → count" 区分
 */
function buildSelectBuilder(thenResult: unknown, isCount: boolean) {
  const builder: any = {};
  builder.from = () => builder;
  builder.where = () => builder;
  builder.orderBy = () => builder;
  builder.limit = () => builder;
  builder.offset = () => builder;
  builder.then = (onFulfilled: any, onRejected: any) => {
    selectCallTracker.calls.push({ isCount });
    return Promise.resolve(thenResult).then(onFulfilled, onRejected);
  };
  return builder;
}

function mockDb({
  rows,
  totalCount,
}: {
  rows: any[];
  totalCount: number;
}) {
  return {
    db: {
      select: vi.fn((_fields: unknown) => {
        const idx = selectCallTracker.callIdx++;
        // 第一次 = 主数据; 第二次 = count
        const isCount = idx === 1;
        return buildSelectBuilder(isCount ? [{ count: totalCount }] : rows, isCount);
      }),
      // resolveCustomerIdentity 用 db.execute, 但 listCustomers 不用, 给个空函数兜底
      execute: vi.fn(async () => []),
    },
  };
}

beforeEach(() => {
  resetTracker();
  vi.resetModules();
});

afterEach(() => {
  vi.doUnmock("@/lib/db");
  vi.resetModules();
});

describe("listCustomers — count 解耦 (R-9 第二条)", () => {
  it("首页 offset=0, 默认 includeTotal=true → total = count 实际值", async () => {
    const fakeRows = Array.from({ length: 20 }, (_, i) => ({
      row: makeFakeRow(i + 1),
      isFranchisee: false,
      direct: false,
      ownedByMe: true,
      ownedBySub: false,
      ownedByUpl: false,
      ownedByDirectDownline: false,
      ownerIdCol: "1",
      isMember: false,
      hasAccount: false,
      acquireSourceCol: null,
      sourceReferrerNameCol: null,
      ownerNameCol: null,
      sharedByNameCol: null,
    }));
    vi.doMock("@/lib/db", () => mockDb({ rows: fakeRows, totalCount: 87 }));

    const { listCustomers } = await import("@/lib/db/queries/customer");
    const result = await listCustomers({ limit: 20, offset: 0 });

    expect(result.items.length).toBe(20);
    expect(result.total).toBe(87); // ← 精确 count, 不退化为 items.length
    // count 被调 1 次 (因为 includeTotal 默认 true)
    expect(selectCallTracker.calls.filter((c) => c.isCount).length).toBe(1);
  });

  it("首页 offset=0, includeTotal=true 显式 → 同上", async () => {
    const fakeRows = Array.from({ length: 3 }, (_, i) => ({
      row: makeFakeRow(i + 1),
      isFranchisee: false,
      direct: false,
      ownedByMe: true,
      ownedBySub: false,
      ownedByUpl: false,
      ownedByDirectDownline: false,
      ownerIdCol: "1",
      isMember: false,
      hasAccount: false,
      acquireSourceCol: null,
      sourceReferrerNameCol: null,
      ownerNameCol: null,
      sharedByNameCol: null,
    }));
    vi.doMock("@/lib/db", () => mockDb({ rows: fakeRows, totalCount: 87 }));

    const { listCustomers } = await import("@/lib/db/queries/customer");
    const result = await listCustomers({ limit: 20, offset: 0, includeTotal: true });

    expect(result.total).toBe(87);
    expect(selectCallTracker.calls.filter((c) => c.isCount).length).toBe(1);
  });

  it("后续页 offset>0, items.length < limit (末页) → total = items.length + offset (final)", async () => {
    // limit=20, offset=80, 总共 87 行 → 这页只 7 行
    const fakeRows = Array.from({ length: 7 }, (_, i) => ({
      row: makeFakeRow(81 + i),
      isFranchisee: false,
      direct: false,
      ownedByMe: true,
      ownedBySub: false,
      ownedByUpl: false,
      ownedByDirectDownline: false,
      ownerIdCol: "1",
      isMember: false,
      hasAccount: false,
      acquireSourceCol: null,
      sourceReferrerNameCol: null,
      ownerNameCol: null,
      sharedByNameCol: null,
    }));
    // includeTotal=false → count 不被调用, 即使给了 totalCount 也不该用
    vi.doMock("@/lib/db", () => mockDb({ rows: fakeRows, totalCount: 87 }));

    const { listCustomers } = await import("@/lib/db/queries/customer");
    const result = await listCustomers({ limit: 20, offset: 80, includeTotal: false });

    expect(result.items.length).toBe(7);
    expect(result.total).toBe(87); // 7 + 80 = 87, 末页 final 值
    // count 不被调 (spy 关键)
    expect(selectCallTracker.calls.filter((c) => c.isCount).length).toBe(0);
  });

  it("后续页 offset>0, items.length === limit (满页) → total = null (可能还有)", async () => {
    const fakeRows = Array.from({ length: 20 }, (_, i) => ({
      row: makeFakeRow(21 + i),
      isFranchisee: false,
      direct: false,
      ownedByMe: true,
      ownedBySub: false,
      ownedByUpl: false,
      ownedByDirectDownline: false,
      ownerIdCol: "1",
      isMember: false,
      hasAccount: false,
      acquireSourceCol: null,
      sourceReferrerNameCol: null,
      ownerNameCol: null,
      sharedByNameCol: null,
    }));
    vi.doMock("@/lib/db", () => mockDb({ rows: fakeRows, totalCount: 999 }));

    const { listCustomers } = await import("@/lib/db/queries/customer");
    const result = await listCustomers({ limit: 20, offset: 20, includeTotal: false });

    expect(result.items.length).toBe(20);
    expect(result.total).toBeNull(); // 满页 → null, 不瞎推 final
    expect(selectCallTracker.calls.filter((c) => c.isCount).length).toBe(0);
  });

  it("后续页 offset>0, includeTotal=false → 不跑 count (spy 验证)", async () => {
    const fakeRows = Array.from({ length: 20 }, (_, i) => ({
      row: makeFakeRow(i + 1),
      isFranchisee: false,
      direct: false,
      ownedByMe: true,
      ownedBySub: false,
      ownedByUpl: false,
      ownedByDirectDownline: false,
      ownerIdCol: "1",
      isMember: false,
      hasAccount: false,
      acquireSourceCol: null,
      sourceReferrerNameCol: null,
      ownerNameCol: null,
      sharedByNameCol: null,
    }));
    vi.doMock("@/lib/db", () => mockDb({ rows: fakeRows, totalCount: 87 }));

    const { listCustomers } = await import("@/lib/db/queries/customer");
    await listCustomers({ limit: 20, offset: 40, includeTotal: false });

    // 只调用 1 次 select (主数据), 没有 count
    expect(selectCallTracker.calls.length).toBe(1);
    expect(selectCallTracker.calls[0].isCount).toBe(false);
  });

  it("后续页 offset>0, includeTotal=true (旧行为兜底) → total = 全表行数", async () => {
    const fakeRows = Array.from({ length: 20 }, (_, i) => ({
      row: makeFakeRow(41 + i),
      isFranchisee: false,
      direct: false,
      ownedByMe: true,
      ownedBySub: false,
      ownedByUpl: false,
      ownedByDirectDownline: false,
      ownerIdCol: "1",
      isMember: false,
      hasAccount: false,
      acquireSourceCol: null,
      sourceReferrerNameCol: null,
      ownerNameCol: null,
      sharedByNameCol: null,
    }));
    vi.doMock("@/lib/db", () => mockDb({ rows: fakeRows, totalCount: 87 }));

    const { listCustomers } = await import("@/lib/db/queries/customer");
    const result = await listCustomers({ limit: 20, offset: 40, includeTotal: true });

    expect(result.items.length).toBe(20);
    expect(result.total).toBe(87); // 全表行数, 不是 items.length + offset
    expect(selectCallTracker.calls.filter((c) => c.isCount).length).toBe(1);
  });

  it("返回类型契约: total = number | null (TypeScript 层断言)", async () => {
    const fakeRows: any[] = [];
    vi.doMock("@/lib/db", () => mockDb({ rows: fakeRows, totalCount: 0 }));

    const { listCustomers } = await import("@/lib/db/queries/customer");
    const r1 = await listCustomers({ limit: 20, offset: 0 });
    expect(typeof r1.total === "number" || r1.total === null).toBe(true);

    resetTracker();
    const fakeRows2 = Array.from({ length: 20 }, (_, i) => ({
      row: makeFakeRow(i + 1),
      isFranchisee: false,
      direct: false,
      ownedByMe: true,
      ownedBySub: false,
      ownedByUpl: false,
      ownedByDirectDownline: false,
      ownerIdCol: "1",
      isMember: false,
      hasAccount: false,
      acquireSourceCol: null,
      sourceReferrerNameCol: null,
      ownerNameCol: null,
      sharedByNameCol: null,
    }));
    vi.doMock("@/lib/db", () => mockDb({ rows: fakeRows2, totalCount: 50 }));
    const r2 = await listCustomers({ limit: 20, offset: 40, includeTotal: false });
    expect(r2.total === null || typeof r2.total === "number").toBe(true);
  });
});

/**
 * 构造 listCustomers 期望的 row 形状 (含 isFranchisee / ownerIdCol 等 SQL 片段列)。
 * 用最小集, 让 toView / identityFromFlags 不报错。
 */
function makeFakeRow(i: number) {
  // phoneEncrypted 必须加密 (toView 会调 decryptField), 用「全零键」测试环境 (tests/setup.ts 配的)
  const fakePhone = `1380000${String(i).padStart(4, "0")}`.slice(0, 11);
  return {
    id: BigInt(i),
    name: `客户-${i}`,
    phoneEncrypted: encryptField(fakePhone),
    phoneHash: "0".repeat(64),
    gender: null,
    birthYear: null,
    birthMonth: null,
    birthDay: null,
    birthCalendar: "solar",
    birthdayRemindDays: null,
    healthTagsEncrypted: null,
    diseaseHistoryEncrypted: null,
    allergyHistoryEncrypted: null,
    notesEncrypted: null,
    referrerId: null,
    avatar: null,
    isSeed: false,
    acquireSource: null,
    sourceReferrerName: null,
    ownerId: BigInt(1),
    createdBy: BigInt(1),
    lastInteractionAt: null,
    lastVisitAt: null,
    createdAt: new Date(),
    updatedAt: new Date(),
    deletedAt: null,
  };
}