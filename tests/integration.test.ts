// 集成测试: 用真实 nuankebao_test 数据库
// 跑: pnpm test:run

import { describe, it, expect, beforeAll, afterAll, beforeEach } from "vitest";
import { db } from "@/lib/db";
import { customer, wellnessRecord } from "@/lib/db/schema";
import { sql } from "drizzle-orm";
import { encryptField, decryptField } from "@/lib/crypto/field";
import { hashForLookup } from "@/lib/crypto/field";

// 自动清理
beforeAll(async () => {
  await db.execute(sql`TRUNCATE customer, follow_up_task, interaction, wellness_record CASCADE`);
});

describe("crypto/field integration", () => {
  it("encrypted fields roundtrip through DB", async () => {
    const phone = "13800138000";
    const phoneEnc = encryptField(phone);
    const phoneHash = hashForLookup(phone);

    // 插入
    const [row] = await db
      .insert(customer)
      .values({
        name: "测试客户-A",
        phoneEncrypted: phoneEnc,
        phoneHash,
        createdBy: 1,
        healthTagsEncrypted: encryptField(JSON.stringify(["肩颈", "睡眠差"])),
        diseaseHistoryEncrypted: encryptField("高血压"),
      })
      .returning();

    expect(row.id).toBeDefined();
    expect(row.phoneEncrypted).not.toBe(phone); // 加密
    expect(row.phoneEncrypted).toBe(phoneEnc);

    // 查询 + 解密
    const [fetched] = await db.select().from(customer).where(sql`id = ${row.id}`);
    expect(decryptField(fetched.phoneEncrypted)).toBe(phone);

    const tags = JSON.parse(decryptField(fetched.healthTagsEncrypted!));
    expect(tags).toEqual(["肩颈", "睡眠差"]);

    expect(decryptField(fetched.diseaseHistoryEncrypted!)).toBe("高血压");

    // 清理
    await db.delete(customer).where(sql`id = ${row.id}`);
  });

  it("phone_hash unique constraint works", async () => {
    const phone = "13800139999";
    const phoneEnc = encryptField(phone);
    const phoneHash = hashForLookup(phone);

    // 第一次插入成功
    const [first] = await db
      .insert(customer)
      .values({
        name: "测试-A",
        phoneEncrypted: phoneEnc,
        phoneHash,
        createdBy: 1,
      })
      .returning();

    // 第二次相同 phoneHash 应失败
    await expect(
      db.insert(customer).values({
        name: "测试-B",
        phoneEncrypted: phoneEnc,
        phoneHash,
        createdBy: 1,
      })
    ).rejects.toThrow();

    // 清理
    await db.delete(customer).where(sql`id = ${first.id}`);
  });

  it("audit trigger writes to audit_log", async () => {
    const phone = "13800138888";
    const [row] = await db
      .insert(customer)
      .values({
        name: "审计测试",
        phoneEncrypted: encryptField(phone),
        createdBy: 1,
        phoneHash: hashForLookup(phone),
      })
      .returning();

    // 设置 session 变量 (用 SET LOCAL)
    await db.execute(sql.raw(`SET app.current_user_id = '${row.createdBy}'`));
    await db.execute(sql`SET app.client_ip = '192.168.1.1'`);

    // UPDATE 操作
    await db
      .update(customer)
      .set({ name: "改名后" })
      .where(sql`id = ${row.id}`);

    // 检查 audit_log (验证至少有一条该 id 的记录)
    // ⚠ 必须带 table_name —— audit_log.record_id **跨表不唯一** (user.id=5 与
    //   customer.id=5 都有审计行), 只按 record_id 查会把别的表的记录捞出来
    //   (本用例曾因此拿到 table_name='user' 而失败)。schema 的
    //   idx_audit_table_record(table_name, record_id) 也正是为两列一起查建的。
    const audit = await db.execute(sql`
      SELECT table_name, operation FROM audit_log
      WHERE table_name = 'customer' AND record_id = ${row.id}::bigint
      ORDER BY id
    `);
    const auditRows = (audit as unknown as Array<{ table_name: string; operation: string }>);
    expect(auditRows.length).toBeGreaterThan(0);
    expect(auditRows[0].table_name).toBe("customer");
    // 至少有 INSERT (来自 .insert().values() 调用)

    // 清理
    await db.delete(customer).where(sql`id = ${row.id}`);
  });
});

describe("queries/customer", () => {
  it("create + getById + update + softDelete", async () => {
    const { createCustomer, getCustomerById, updateCustomer, softDeleteCustomer } = await import(
      "@/lib/db/queries/customer"
    );

    // CREATE
    const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };
    const testPhone = `1391111${Date.now().toString().slice(-4)}`;
    const created = await createCustomer(
      {
        name: "集成测试客户",
        phone: testPhone,
        gender: "F",
        birthYear: 1990,
        healthTags: ["肩颈", "体寒"],
        diseaseHistory: "无",
      },
      ctx,
      BigInt(1)
    );

    expect(created.id).toBeDefined();
    expect(created.name).toBe("集成测试客户");
    expect(created.phone).toBe(testPhone);
    expect(created.healthTags).toEqual(["肩颈", "体寒"]);
    expect(created.birthYear).toBe(1990);

    // GET BY ID
    const fetched = await getCustomerById(BigInt(created.id));
    expect(fetched).not.toBeNull();
    expect(fetched!.name).toBe("集成测试客户");
    expect(fetched!.phone).toBe(testPhone);

    // UPDATE
    const updated = await updateCustomer(
      BigInt(created.id),
      { name: "改名后", healthTags: ["肩颈", "湿气重"] },
      ctx
    );
    expect(updated!.name).toBe("改名后");
    expect(updated!.healthTags).toEqual(["肩颈", "湿气重"]);

    // SOFT DELETE
    const deleted = await softDeleteCustomer(BigInt(created.id), ctx);
    expect(deleted).toBe(true);

    // 查询应返回 null
    const afterDelete = await getCustomerById(BigInt(created.id));
    expect(afterDelete).toBeNull();
  });

  it("list respects search filter", async () => {
    const { createCustomer, listCustomers } = await import(
      "@/lib/db/queries/customer"
    );
    const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };

    // 创建 2 个客户
    await createCustomer(
      { name: "张三-测试", phone: `1370000${Date.now().toString().slice(-2)}01` },
      ctx,
      BigInt(1)
    );
    await createCustomer(
      { name: "李四-测试", phone: `1370000${Date.now().toString().slice(-2)}02` },
      ctx,
      BigInt(1)
    );

    // 搜索 "张三"
    const result = await listCustomers({ search: "张三-测试" });
    expect(result.items.length).toBeGreaterThanOrEqual(1);
    const found = result.items.find((c) => c.name === "张三-测试");
    expect(found).toBeDefined();

    // 清理 (用 SQL 直接删, 绕过 soft delete)
    await db.execute(sql`DELETE FROM customer WHERE phone_hash IN (${hashForLookup("13700000001")}, ${hashForLookup("13700000002")})`);
  });
});

describe("queries/wellness-record", () => {
  it("create with photos + JSONB conditions", async () => {
    const { createWellnessRecord, getWellnessRecordById } = await import(
      "@/lib/db/queries/wellness-record"
    );

    // 先创建一个客户
    const { createCustomer } = await import("@/lib/db/queries/customer");
    const customer_ = await createCustomer(
      { name: "养生-测试", phone: `1380000${Date.now().toString().slice(-4)}` },
      { userId: BigInt(1), ipAddress: "127.0.0.1" },
      BigInt(1)
    );

    // 创建记录
    const record = await createWellnessRecord(
      {
        customerId: customer_.id,
        serviceDate: "2026-09-04",
        serviceItemId: "1",
        bodyPartIds: ["1", "2"],
        productUsages: [{ productId: "1", quantity: 5 }],
        preCondition: { pain_level: 8, sleep_quality: 5 },
        postCondition: { pain_level: 4, sleep_quality: 7 },
        processNote: "理疗过程测试",
        customerFeedback: "好多了",
        photos: ["/uploads/test1.jpg"],
        nextAdviceDate: "2026-09-18",
      },
      { userId: BigInt(1), ipAddress: "127.0.0.1" },
      BigInt(1)
    );

    expect(record.id).toBeDefined();
    expect(record.preCondition).toEqual({ pain_level: 8, sleep_quality: 5 });
    expect(record.postCondition).toEqual({ pain_level: 4, sleep_quality: 7 });
    expect(record.photos).toEqual(["/uploads/test1.jpg"]);
    expect(record.bodyPartIds).toEqual(["1", "2"]);

    // 详情查询
    const fetched = await getWellnessRecordById(BigInt(record.id));
    expect(fetched).not.toBeNull();
    expect(fetched!.customerFeedback).toBe("好多了");

    // 清理
    await db.execute(sql`DELETE FROM customer WHERE id = ${BigInt(customer_.id)}`);
  });
});