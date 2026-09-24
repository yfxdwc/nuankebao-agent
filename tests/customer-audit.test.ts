// ============================================
// 客户档案改动记录 (审计查询) —— 2026-09-24 管理 Tab 建议 #2
//
// 守什么:
//   ① 建档 → INSERT / 改名 → UPDATE 且 `changedColumns` 含 `name`
//   ② **`table_name` 必须一起过滤** —— 只按 record_id 会串到别的表同 id 的记录
//      (AGENTS §5 已沉淀过这个坑; schema 的 idx_audit_table_record 就是这个用途)
//   ③ 只返回**列名**, 不返回列值 (隐私: 列值可能是密文/手机号/病史)
//
// 只操作自己造的数据 (不 TRUNCATE —— 同一测试库还有别的测试文件在用)
//
// 跑: npx vitest run tests/customer-audit.test.ts
// ============================================

import { describe, it, expect, afterAll } from "vitest";
import { sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { createCustomer, updateCustomer } from "@/lib/db/queries/customer";
import { listCustomerAuditTrail } from "@/lib/db/queries/audit";

const createdIds: bigint[] = [];

afterAll(async () => {
  for (const id of createdIds) {
    // 先删档案 (会再写一条 DELETE 审计), 再把该档案的审计行清干净
    await db.execute(sql`DELETE FROM customer WHERE id = ${id}`);
    await db.execute(
      sql`DELETE FROM audit_log WHERE table_name = 'customer' AND record_id = ${id}`
    );
  }
});

describe("listCustomerAuditTrail — 客户档案改动记录", () => {
  it("建档 → INSERT; 改名 → UPDATE 且列出变更列名 (不返回列值)", async () => {
    const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };
    const phone = `13966${Date.now().toString().slice(-7)}`;
    const created = await createCustomer(
      { name: "审计测试客户", phone },
      ctx,
      BigInt(1)
    );
    const id = BigInt(created.id);
    createdIds.push(id);

    await updateCustomer(id, { name: "审计测试客户-改名" }, ctx);

    const entries = await listCustomerAuditTrail(id, 10);
    expect(entries.length).toBeGreaterThanOrEqual(2);

    // 最新一条 = UPDATE, 变更列里有 name
    const latest = entries[0];
    expect(latest.operation).toBe("UPDATE");
    expect(latest.changedColumns).toContain("name");
    // 只给列名, 不给值 —— 任何条目的 changedColumns 都是字符串数组
    expect(Array.isArray(latest.changedColumns)).toBe(true);
    for (const c of latest.changedColumns) {
      expect(typeof c).toBe("string");
    }
    expect(latest.createdAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);

    // 最老一条 = INSERT (建档)
    const oldest = entries[entries.length - 1];
    expect(oldest.operation).toBe("INSERT");
  });

  it("table_name 过滤: 别的表同 record_id 的审计不会混进来", async () => {
    const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };
    const phone = `13977${Date.now().toString().slice(-7)}`;
    const created = await createCustomer(
      { name: "审计隔离测试", phone },
      ctx,
      BigInt(1)
    );
    const id = BigInt(created.id);
    createdIds.push(id);

    // 伪造一条「另一个表、同一个 record_id」的审计 (模拟 franchisee.id = 客户 id)
    await db.execute(sql`
      INSERT INTO audit_log (table_name, record_id, operation, changed_fields)
      VALUES ('franchisee', ${id}, 'UPDATE', ${JSON.stringify({ name: "不该出现" })}::jsonb)
    `);

    const entries = await listCustomerAuditTrail(id, 20);
    // 全部条目都来自 customer 表 (record_id 命中别的表不会漏进来)
    expect(entries.every((e) => e.operation === "INSERT")).toBe(true);

    await db.execute(
      sql`DELETE FROM audit_log WHERE table_name = 'franchisee' AND record_id = ${id}`
    );
  });

  it("limit 生效 (倒序只取最近 N 条)", async () => {
    const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };
    const phone = `13988${Date.now().toString().slice(-7)}`;
    const created = await createCustomer(
      { name: "审计 limit 测试", phone },
      ctx,
      BigInt(1)
    );
    const id = BigInt(created.id);
    createdIds.push(id);

    await updateCustomer(id, { name: "改 1" }, ctx);
    await updateCustomer(id, { name: "改 2" }, ctx);
    await updateCustomer(id, { name: "改 3" }, ctx);

    const entries = await listCustomerAuditTrail(id, 2);
    expect(entries).toHaveLength(2);
    // 倒序: 最新的在前 (两次 UPDATE, 不是 INSERT)
    expect(entries[0].operation).toBe("UPDATE");
  });
});
