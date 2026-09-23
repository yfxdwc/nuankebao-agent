// 业务层 queries 扩展测试
// 跑: DATABASE_URL=postgres://nuankebao:test@localhost:5432/nuankebao_test pnpm test:run

import { describe, it, expect, beforeAll } from "vitest";
import { db } from "@/lib/db";
import { customer, followUpTask, interaction, wellnessRecord, serviceItem } from "@/lib/db/schema";
import { sql, inArray } from "drizzle-orm";
import { encryptField, hashForLookup } from "@/lib/crypto/field";

// 每个测试文件跑前自动清理 (避免重复 phone_hash 冲突)
beforeAll(async () => {
  await db.execute(sql`TRUNCATE customer, follow_up_task, interaction, wellness_record CASCADE`);
});

// 准备: 创建测试客户 + 一些服务项目
async function setupTestCustomer() {
  const phone = `138${Date.now().toString().slice(-8)}`;
  const phoneEnc = encryptField(phone);
  const phoneHash = hashForLookup(phone);
  const [row] = await db
    .insert(customer)
    .values({
      name: "扩展测试客户",
      phoneEncrypted: phoneEnc,
      phoneHash,
      createdBy: 1,
    })
    .returning();
  return { id: row.id.toString(), phone };
}

async function cleanup(customerId: string) {
  await db.execute(sql`DELETE FROM customer WHERE id = ${BigInt(customerId)}`);
}

// ============================================
// follow-up-task queries
// ============================================
describe("queries/follow-up-task", () => {
  it("create + list + complete + cancel", async () => {
    const c = await setupTestCustomer();
    const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };
    const { createFollowUpTask, listFollowUpTasks, completeFollowUpTask, cancelFollowUpTask } = await import(
      "@/lib/db/queries/follow-up-task"
    );

    // CREATE
    const task = await createFollowUpTask(
      {
        customerId: c.id,
        dueAt: "2026-12-01T10:00:00Z",
        reason: "扩展测试创建",
        aiSuggestion: "建议回访",
      },
      ctx,
      BigInt(1)
    );
    expect(task.customerId).toBe(c.id);
    expect(task.reason).toBe("扩展测试创建");
    expect(task.status).toBe("pending");

    // LIST pending
    const pending = await listFollowUpTasks({ status: "pending", limit: 5 });
    expect(pending.items.length).toBeGreaterThanOrEqual(1);

    // COMPLETE
    const completed = await completeFollowUpTask(BigInt(task.id), "已联系", ctx);
    expect(completed!.status).toBe("done");
    expect(completed!.completedNotes).toBe("已联系");

    // 验证 LIST done 包含
    const done = await listFollowUpTasks({ status: "done", limit: 5 });
    expect(done.items.find((t) => t.id === task.id)).toBeDefined();

    // CANCEL (尝试取消已完成的应失败)
    const cancelResult = await cancelFollowUpTask(BigInt(task.id), ctx);
    expect(cancelResult).toBeNull();

    await cleanup(c.id);
  });
});

// ============================================
// interaction queries
// ============================================
describe("queries/interaction", () => {
  it("create + listByCustomer", async () => {
    const c = await setupTestCustomer();
    const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };
    const { createInteraction, listInteractionsByCustomer } = await import(
      "@/lib/db/queries/interaction"
    );

    // CREATE phone
    const i1 = await createInteraction(
      {
        customerId: c.id,
        type: "phone",
        summary: "电话联系,客户已读",
        followUpAt: "2026-12-15T10:00:00Z",
      },
      ctx,
      BigInt(1)
    );
    expect(i1.type).toBe("phone");
    expect(i1.summary).toBe("电话联系,客户已读");

    // CREATE wechat
    const i2 = await createInteraction(
      {
        customerId: c.id,
        type: "wechat",
        summary: "微信发送话术",
      },
      ctx,
      BigInt(1)
    );
    expect(i2.type).toBe("wechat");

    // LIST
    const list = await listInteractionsByCustomer(c.id);
    expect(list.length).toBe(2);
    expect(list[0].customerId).toBe(c.id);

    await cleanup(c.id);
  });
});

// ============================================
// dashboard queries
// ============================================
describe("queries/dashboard", () => {
  it("getDashboardStats returns valid structure", async () => {
    const { getDashboardStats, getServiceDistribution } = await import(
      "@/lib/db/queries/dashboard"
    );
    const stats = await getDashboardStats();
    expect(typeof stats.customerCount).toBe("number");
    expect(typeof stats.thisMonthVisits).toBe("number");
    expect(typeof stats.pendingFollowUps).toBe("number");
    expect(typeof stats.totalInteractions).toBe("number");
    expect(stats.customerCount).toBeGreaterThanOrEqual(0);

    const dist = await getServiceDistribution();
    expect(Array.isArray(dist)).toBe(true);
  });

  it("getMonthlyVisits returns 6 months continuous", async () => {
    const { getMonthlyVisits } = await import("@/lib/db/queries/reports");
    const months = await getMonthlyVisits();
    expect(months.length).toBe(6);

    // 连续 6 个月
    const now = new Date();
    for (let i = 0; i < 6; i++) {
      const d = new Date(now.getFullYear(), now.getMonth() - (5 - i), 1);
      const expected = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
      expect(months[i].month).toBe(expected);
    }
  });
});

// ============================================
// reports queries
// ============================================
describe("queries/reports", () => {
  it("getOverviewReport combines multiple data sources", async () => {
    const { getOverviewReport } = await import("@/lib/db/queries/reports");
    const report = await getOverviewReport();

    expect(Array.isArray(report.monthlyVisits)).toBe(true);
    expect(report.monthlyVisits.length).toBe(6);

    expect(Array.isArray(report.repurchaseIntervals)).toBe(true);
    expect(report.repurchaseIntervals.length).toBe(5); // 5 个分桶
    expect(report.repurchaseIntervals[0].range).toBe("0-30天");

    expect(typeof report.customerActivity.newCustomersThis).toBe("number");
    expect(typeof report.customerActivity.totalActiveCustomers).toBe("number");
  });
});

// ============================================
// audit log 验证
// ============================================
describe("audit log (自动写)", () => {
  it("INSERT customer writes audit_log", async () => {
    const c = await setupTestCustomer();

    const logs = await db.execute<{ table_name: string; operation: string; record_id: string }>(sql`
      SELECT table_name, operation, record_id::text
      FROM audit_log
      WHERE table_name = 'customer' AND record_id = ${c.id}::bigint
      ORDER BY id DESC
    `);

    const rows = logs as unknown as Array<{ table_name: string; operation: string; record_id: string }>;
    expect(rows.length).toBeGreaterThan(0);
    expect(rows[0].table_name).toBe("customer");
    expect(rows[0].operation).toBe("INSERT");

    await cleanup(c.id);
  });
});

// ============================================
// 字典数据完整性
// ============================================
describe("dictionary integrity", () => {
  it("all 3 dictionaries are seeded", async () => {
    const { listBodyParts, listServiceItems, listProducts } = await import(
      "@/lib/db/queries/dictionary"
    );
    const [bp, si, pr] = await Promise.all([
      listBodyParts(),
      listServiceItems(),
      listProducts(),
    ]);
    expect(bp.length).toBeGreaterThanOrEqual(8);
    expect(si.length).toBeGreaterThanOrEqual(5);
    expect(pr.length).toBeGreaterThanOrEqual(5);
  });
});