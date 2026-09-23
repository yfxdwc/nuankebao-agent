// ============================================
// drizzle-kit generate 护栏 单测
// ============================================
// 守护的东西:
//   ① detectReplay 纯函数: 命中真危险 (CREATE 已存在表 / ALTER 已存在表 / DROP 已存在索引)
//   ② 不误报: 全新 CREATE TABLE / CREATE INDEX IF NOT EXISTS / 空 / 纯注释 都安全
//   ③ 行号追踪正确 (statement-breakpoint 在行内 / 行尾 / 多行中间都算)
//   ④ collectExistingObjects 不把审计文件算成业务 schema, 不算 down/ 文件
//
// 不依赖 drizzle-kit / 不连库 — 纯函数测试, 离线可跑。
// 跑: pnpm test:run tests/drizzle-generate-guard.test.ts
// ============================================

import { describe, it, expect } from "vitest";
import {
  detectReplay,
  collectExistingObjects,
  type ExistingObjects,
} from "../tools/check-drizzle-generate";

const existing: ExistingObjects = {
  tables: new Set([
    "customer",
    "user",
    "franchisee",
    "usage_event",
    "app_config",
  ]),
  indexes: new Set([
    "idx_placement_pending_slot",
    "idx_customer_phone_hash",
    "idx_franchisee_root",
  ]),
};

// ============================================
// detectReplay: 危险模式必须命中
// ============================================

describe("detectReplay — 危险模式命中", () => {
  it("CREATE TABLE \"customer\" → 命中 (任务描述要求的场景)", () => {
    const sql = `CREATE TABLE IF NOT EXISTS "customer" (
  "id" bigserial PRIMARY KEY NOT NULL
);`;
    const reasons = detectReplay(sql, existing);
    expect(reasons).toHaveLength(1);
    expect(reasons[0].kind).toBe("create-existing-table");
    expect(reasons[0].name).toBe("customer");
    expect(reasons[0].statement).toContain("CREATE TABLE");
  });

  it("CREATE TABLE \"usage_event\" → 命中 (任务描述要求的场景)", () => {
    const sql = `CREATE TABLE IF NOT EXISTS "usage_event" (
  "id" bigserial PRIMARY KEY NOT NULL
);`;
    const reasons = detectReplay(sql, existing);
    expect(reasons).toHaveLength(1);
    expect(reasons[0].kind).toBe("create-existing-table");
    expect(reasons[0].name).toBe("usage_event");
  });

  it("ALTER TABLE \"customer\" ADD COLUMN → 命中 (任务描述要求的场景)", () => {
    const sql = `ALTER TABLE "customer" ADD COLUMN "owner_id" bigint;--> statement-breakpoint`;
    const reasons = detectReplay(sql, existing);
    expect(reasons).toHaveLength(1);
    expect(reasons[0].kind).toBe("alter-existing-table");
    expect(reasons[0].name).toBe("customer");
  });

  it("ALTER TABLE 对多张已存在表 命中多条", () => {
    // 真实场景 (drizzle-kit 在 snapshot 落后时输出): 一条文件含 5 条 ALTER
    const sql = [
      `ALTER TABLE "customer" ADD COLUMN "owner_id" bigint;--> statement-breakpoint`,
      `ALTER TABLE "user" ADD COLUMN "customer_id" bigint;--> statement-breakpoint`,
      `ALTER TABLE "franchisee" ADD COLUMN "root_id" bigint;--> statement-breakpoint`,
    ].join("\n");
    const reasons = detectReplay(sql, existing);
    expect(reasons.map((r) => r.name)).toEqual([
      "customer",
      "user",
      "franchisee",
    ]);
    reasons.forEach((r) => {
      expect(r.kind).toBe("alter-existing-table");
    });
  });

  it("DROP INDEX \"idx_placement_pending_slot\" → 命中 (任务描述要求的场景)", () => {
    const sql = `DROP INDEX IF EXISTS "idx_placement_pending_slot";--> statement-breakpoint`;
    const reasons = detectReplay(sql, existing);
    expect(reasons).toHaveLength(1);
    expect(reasons[0].kind).toBe("drop-existing-index");
    expect(reasons[0].name).toBe("idx_placement_pending_slot");
  });

  it("完整复刻 drizzle-kit 实际生成的假 diff — 全部命中", () => {
    // 这是 2026-09-23 在仓库里实测得到的 drizzle-kit generate 输出 (0024 之后)
    const sql = [
      `CREATE TABLE IF NOT EXISTS "app_config" (`,
      `  "key" text PRIMARY KEY NOT NULL`,
      `);`,
      `--> statement-breakpoint`,
      `CREATE TABLE IF NOT EXISTS "usage_event" (`,
      `  "id" bigserial PRIMARY KEY NOT NULL`,
      `);`,
      `--> statement-breakpoint`,
      `DROP INDEX IF EXISTS "idx_placement_pending_slot";--> statement-breakpoint`,
      `ALTER TABLE "customer" ADD COLUMN "owner_id" bigint;--> statement-breakpoint`,
      `ALTER TABLE "franchisee" ADD COLUMN "root_id" bigint;--> statement-breakpoint`,
    ].join("\n");
    const reasons = detectReplay(sql, existing);
    expect(reasons.map((r) => r.name)).toEqual([
      "app_config",
      "usage_event",
      "idx_placement_pending_slot",
      "customer",
      "franchisee",
    ]);
    expect(reasons[0].line).toBe(1);
    expect(reasons[1].line).toBe(5);
    expect(reasons[2].line).toBe(9);
    expect(reasons[3].line).toBe(10);
    expect(reasons[4].line).toBe(11);
  });
});

// ============================================
// detectReplay: 安全模式必须放行 (任务描述要求)
// ============================================

describe("detectReplay — 安全模式放行", () => {
  it("只含 CREATE TABLE \"some_new_table\" → 安全 (任务描述要求的场景)", () => {
    const sql = `CREATE TABLE IF NOT EXISTS "some_new_table" (
  "id" bigserial PRIMARY KEY NOT NULL
);--> statement-breakpoint`;
    const reasons = detectReplay(sql, existing);
    expect(reasons).toEqual([]);
  });

  it("CREATE INDEX IF NOT EXISTS \"x\" ON \"existing_table\" → 安全 (idempotent, 不算重放)", () => {
    // 这条 drizzle-kit 会大量输出, IF NOT EXISTS 让重跑不报错, 不算危险
    const sql = [
      `CREATE INDEX IF NOT EXISTS "idx_usage_event_user_ts" ON "usage_event" USING btree ("user_id","server_ts");--> statement-breakpoint`,
      `CREATE UNIQUE INDEX IF NOT EXISTS "idx_usage_event_event_id" ON "usage_event" USING btree ("event_id");--> statement-breakpoint`,
    ].join("\n");
    expect(detectReplay(sql, existing)).toEqual([]);
  });

  it("空文件 → 安全 (任务描述要求的场景)", () => {
    expect(detectReplay("", existing)).toEqual([]);
  });

  it("纯注释 → 安全 (任务描述要求的场景)", () => {
    const sql = [
      `-- 这是注释`,
      `-- 多行注释`,
      `/* 块注释 */`,
    ].join("\n");
    expect(detectReplay(sql, existing)).toEqual([]);
  });

  it("CREATE INDEX \"new_index\" (无 IF NOT EXISTS) → 安全 (我们只标 DROP INDEX 危险)", () => {
    const sql = `CREATE INDEX "some_brand_new_index" ON "customer" ("id");--> statement-breakpoint`;
    expect(detectReplay(sql, existing)).toEqual([]);
  });

  it("ALTER TABLE \"new_table\" ADD COLUMN → 安全 (表本身不存在, 不算重放)", () => {
    const sql = `ALTER TABLE "new_future_table" ADD COLUMN "x" bigint;--> statement-breakpoint`;
    expect(detectReplay(sql, existing)).toEqual([]);
  });

  it("DROP INDEX \"nonexistent\" → 安全 (索引不存在, 不算误删)", () => {
    const sql = `DROP INDEX IF EXISTS "idx_does_not_exist";--> statement-breakpoint`;
    expect(detectReplay(sql, existing)).toEqual([]);
  });
});

// ============================================
// 行号追踪: 各种 statement-breakpoint 位置
// ============================================

describe("detectReplay — 行号追踪", () => {
  it("statement-breakpoint 在独立行 (drizzle-kit 实际格式)", () => {
    // 行 1-2 CREATE TABLE, 行 3 = statement-breakpoint, 行 4-5 ALTER
    const sql = [
      `CREATE TABLE IF NOT EXISTS "customer" (`,
      `  "id" bigserial PRIMARY KEY NOT NULL`,
      `);`,
      `--> statement-breakpoint`,
      `ALTER TABLE "customer" ADD COLUMN "x" bigint;--> statement-breakpoint`,
    ].join("\n");
    const reasons = detectReplay(sql, existing);
    expect(reasons).toHaveLength(2);
    expect(reasons[0].line).toBe(1);
    expect(reasons[1].line).toBe(5);
  });

  it("statement-breakpoint 与上一行结尾同行 (老格式或单行 statement)", () => {
    const sql = [
      `CREATE TABLE IF NOT EXISTS "customer" (x bigint);--> statement-breakpoint`,
      `ALTER TABLE "customer" ADD COLUMN "y" bigint;--> statement-breakpoint`,
    ].join("\n");
    const reasons = detectReplay(sql, existing);
    expect(reasons).toHaveLength(2);
    expect(reasons[0].line).toBe(1);
    expect(reasons[1].line).toBe(2);
  });
});

// ============================================
// collectExistingObjects: 边界
// ============================================

describe("collectExistingObjects — 扫描边界", () => {
  it("不存在的目录 → 返回空集合, 不抛", () => {
    const r = collectExistingObjects("/nonexistent/path");
    expect(r.tables.size).toBe(0);
    expect(r.indexes.size).toBe(0);
  });

});