// 业务层 queries 扩展测试
// 跑: DATABASE_URL=postgres://nuankebao:test@localhost:5432/nuankebao_test pnpm test:run

import { describe, it, expect, beforeAll } from "vitest";
import { db } from "@/lib/db";
import { customer, followUpTask, interaction, wellnessRecord, serviceItem } from "@/lib/db/schema";
import { eq, sql, inArray } from "drizzle-orm";
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

  it("getById: 命中 / 不存在 → null", async () => {
    const c = await setupTestCustomer();
    const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };
    const { createInteraction, getInteractionById } = await import(
      "@/lib/db/queries/interaction"
    );

    const i = await createInteraction(
      { customerId: c.id, type: "visit", summary: "上门拜访" },
      ctx,
      BigInt(1)
    );
    const got = await getInteractionById(BigInt(i.id));
    expect(got).not.toBeNull();
    expect(got!.id).toBe(i.id);
    expect(got!.type).toBe("visit");
    expect(got!.summary).toBe("上门拜访");

    // 不存在的 id → null
    const missing = await getInteractionById(BigInt("999999999999"));
    expect(missing).toBeNull();

    await cleanup(c.id);
  });

  it("update: 改 summary 往返加密 / 空串清空 / 改 type / 不存在 → null", async () => {
    const c = await setupTestCustomer();
    const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };
    const { createInteraction, updateInteraction, getInteractionById } =
      await import("@/lib/db/queries/interaction");

    const i = await createInteraction(
      { customerId: c.id, type: "phone", summary: "原文" },
      ctx,
      BigInt(1)
    );

    // 改 summary (往能反解密出来)
    const updated = await updateInteraction(
      BigInt(i.id),
      { summary: "修正后的备注" },
      ctx
    );
    expect(updated).not.toBeNull();
    expect(updated!.summary).toBe("修正后的备注");
    // 再读一次确认加密列被覆盖
    const reread = await getInteractionById(BigInt(i.id));
    expect(reread!.summary).toBe("修正后的备注");

    // 空串 → 清空
    const cleared = await updateInteraction(
      BigInt(i.id),
      { summary: "" },
      ctx
    );
    expect(cleared!.summary).toBeNull();

    // 改 type (其他字段不动)
    await updateInteraction(BigInt(i.id), { type: "wechat" }, ctx);
    const afterType = await getInteractionById(BigInt(i.id));
    expect(afterType!.type).toBe("wechat");
    expect(afterType!.summary).toBeNull();

    // 不存在 id → null
    const missing = await updateInteraction(
      BigInt("999999999999"),
      { type: "other" },
      ctx
    );
    expect(missing).toBeNull();

    // 审计断言: update() 触发了 interaction_audit 触发器
    // ⚠ AGENTS §5: audit_log.record_id 跨表不唯一, 必须带 table_name='interaction'
    const updateAudits = await db.execute<{ operation: string }>(sql`
      SELECT operation FROM audit_log
      WHERE table_name = 'interaction' AND record_id = ${BigInt(i.id)}::bigint
        AND operation = 'UPDATE'
    `);
    const updateRows = updateAudits as unknown as Array<{ operation: string }>;
    expect(updateRows.length).toBeGreaterThan(0);
    expect(updateRows[0].operation).toBe("UPDATE");

    await cleanup(c.id);
  });

  it("delete: 成功 true / 再删 false + lastInteractionAt 回退到剩余 MAX", async () => {
    const c = await setupTestCustomer();
    const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };
    const { createInteraction, deleteInteraction } = await import(
      "@/lib/db/queries/interaction"
    );

    // 造两条不同 createdAt (直接 db.insert 控住, 不走 createInteraction 的 GREATEST)
    const earlier = new Date("2026-09-01T08:00:00Z");
    const later = new Date("2026-09-20T08:00:00Z");
    const [iEarly] = await db
      .insert(interaction)
      .values({
        customerId: BigInt(c.id),
        type: "phone",
        summaryEncrypted: encryptField("较早一条"),
        createdBy: BigInt(1),
        createdAt: earlier,
      })
      .returning();
    const [iLate] = await db
      .insert(interaction)
      .values({
        customerId: BigInt(c.id),
        type: "wechat",
        summaryEncrypted: encryptField("较近一条"),
        createdBy: BigInt(1),
        createdAt: later,
      })
      .returning();

    // 手动把 customer.lastInteractionAt 推到较近的时间点 (模拟 createInteraction 状态)
    await db
      .update(customer)
      .set({ lastInteractionAt: later })
      .where(eq(customer.id, BigInt(c.id)));

    // 删较近的 → lastInteractionAt 应回到较早那条
    const ok = await deleteInteraction(BigInt(iLate.id), ctx);
    expect(ok).toBe(true);
    const [rowAfterFirstDelete] = await db
      .select({ lastInteractionAt: customer.lastInteractionAt })
      .from(customer)
      .where(eq(customer.id, BigInt(c.id)));
    expect(rowAfterFirstDelete.lastInteractionAt).not.toBeNull();
    expect(
      new Date(rowAfterFirstDelete.lastInteractionAt!).getTime()
    ).toBe(earlier.getTime());

    // 再删同一条 → false (幂等 delete 应不报 500)
    const again = await deleteInteraction(BigInt(iLate.id), ctx);
    expect(again).toBe(false);

    // 删较早那条 → lastInteractionAt 应变 NULL
    const ok2 = await deleteInteraction(BigInt(iEarly.id), ctx);
    expect(ok2).toBe(true);
    const [rowAfterAllDelete] = await db
      .select({ lastInteractionAt: customer.lastInteractionAt })
      .from(customer)
      .where(eq(customer.id, BigInt(c.id)));
    expect(rowAfterAllDelete.lastInteractionAt).toBeNull();

    // 审计断言: deleteInteraction() 两条都触发了 interaction_audit 触发器
    // ⚠ AGENTS §5: audit_log.record_id 跨表不唯一, 必须带 table_name='interaction'
    //   否则会静默拿到别的表同 id 的记录, 看似绿其实验错事
    const deleteAudits = await db.execute<{ operation: string; record_id: string }>(sql`
      SELECT operation, record_id::text
      FROM audit_log
      WHERE table_name = 'interaction'
        AND record_id IN (${BigInt(iEarly.id)}::bigint, ${BigInt(iLate.id)}::bigint)
        AND operation = 'DELETE'
      ORDER BY id
    `);
    const deleteRows = deleteAudits as unknown as Array<{
      operation: string;
      record_id: string;
    }>;
    // iLate 被删两次, 触发器只会写一次 DELETE (第二次 no-op), iEarly 一次 DELETE → 共 2 条
    expect(deleteRows.length).toBe(2);
    expect(deleteRows.every((r) => r.operation === "DELETE")).toBe(true);
    const deletedIds = new Set(deleteRows.map((r) => r.record_id));
    expect(deletedIds.has(iEarly.id.toString())).toBe(true);
    expect(deletedIds.has(iLate.id.toString())).toBe(true);

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