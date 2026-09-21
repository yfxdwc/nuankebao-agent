#!/usr/bin/env -S npx tsx
// ============================================
// 暖客宝 测试数据 seed (主人 2026-09-16 ask)
// 任务: seed-test-data-30plus-franchisees
//
// 数据组成:
//   A. 加盟商 (franchisee): 31 节点满二叉树 (depth 0-4, ADR-0010 override)
//   B. 种子客户 (customer): 5 位 (没加盟 + 没养生记录 + 已加连接方式/基础信息)
//   C. 普通客户 (customer): 6 位 (有养生记录, 模拟活跃客户)
//   D. 老带新 referral chain: 5 个分支, 体现客户间推荐关系 (customer.referrerId)
//
// 边界:
//   - 走 Next.js HTTP API (audit log 自动写, 符合 AGENTS §3 红线)
//   - 创建前先检查现有数据, 避免重复 (idempotent)
//   - createdBy = 0 (DEV_SKIP_AUTH=1 dev 模式)
//
// 用法:
//   pnpm tsx scripts/seed-test-data.ts             # 跑 (默认 http://127.0.0.1:3003)
//   API_BASE=http://x.x.x.x:3003 pnpm tsx scripts/seed-test-data.ts
//   pnpm tsx scripts/seed-test-data.ts --dry-run   # 仅打印, 不真创建
//
// ⚠ 节点 ⇒ 账号 (主人 2026-09-21 拍): 「要成为节点首先必需有账号」
//   所以本脚本给每个加盟节点**先建账号再建节点** (账号手机号 = 节点手机号)。
//   历史版本先建节点、后不管账号 → 2026-09-21 巡检出 29 个"无账号节点"
//   (那批脏数据用 scripts/audit-orphan-nodes.ts --bind 补齐)。
//
// 关联:
//   - ADR-0010 (≤4 层 override, 本任务前提)
//   - ADR-0014 §3.7 (节点 ⇒ 账号 不变量)
//   - CHANGELOG [Unreleased] / 主人 ask d234bdd4 (2026-09-16)
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
//   历史写法 (手动 `loadEnv` + `if (NODE_ENV !== "production")` 守卫) 在 NODE_ENV=production
//   的 shell 里**静默不加载** → DATABASE_URL 缺失 → postgres 退化成 OS 用户登录直接认证失败
//   (2026-09-21 给节点建账号时踩到, 现统一走 _env.ts)
import "./_env";

const API_BASE = process.env.API_BASE ?? "http://127.0.0.1:3003";
const DRY_RUN = process.argv.includes("--dry-run");
const PREFIX = "SeedTest-";

// ============================================
// Util
// ============================================

function ok(msg: string) {
  console.log(`\x1b[32m✓\x1b[0m ${msg}`);
}
function info(msg: string) {
  console.log(`\x1b[34m·\x1b[0m ${msg}`);
}
function warn(msg: string) {
  console.log(`\x1b[33m⚠\x1b[0m ${msg}`);
}
function err(msg: string) {
  console.error(`\x1b[31m✗\x1b[0m ${msg}`);
}

async function apiPost<T>(path: string, body: unknown): Promise<T | null> {
  const url = `${API_BASE}${path}`;
  if (DRY_RUN) {
    info(`[dry-run] POST ${url} ${JSON.stringify(body).slice(0, 80)}...`);
    return null;
  }
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`POST ${path} -> ${res.status}: ${text}`);
  }
  return (await res.json()) as T;
}

async function apiGet<T>(path: string): Promise<T> {
  const url = `${API_BASE}${path}`;
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`GET ${path} -> ${res.status}: ${await res.text()}`);
  }
  return (await res.json()) as T;
}

// 手机号去重 (idx_franchisee_phone_hash unique + idx_customer_phone_hash unique)
//   策略: phone = 13900000000 + max(id) (含 deleted, 抩开 id 间隔)
//   本 script 创建 31 franchisees + 10 customers. 现存 id 最高 ~37 (含 cleaned-up),
//   起始手机号 = 13900000099 (走 padding 避开之前手动测试的 13900000001-13900000031).
let _phoneCounter = 13900000000;
async function initPhoneCounter() {
  try {
    const postgres = (await import("postgres")).default;
    const { drizzle } = await import("drizzle-orm/postgres-js");
    const { franchisee, customer } = await import("../src/lib/db/schema");
    const { sql } = await import("drizzle-orm");

    const conn = postgres(process.env.DATABASE_URL!);
    const db = drizzle(conn);

    const maxIds = await db
      .select({
        fMax: sql<number>`COALESCE(MAX(${franchisee.id}), 0)::int`,
        cMax: sql<number>`COALESCE(MAX(${customer.id}), 0)::int`,
      })
      .from(franchisee)
      .leftJoin(customer, sql`true`);
    const fMax = maxIds?.[0]?.fMax ?? 0;
    const cMax = maxIds?.[0]?.cMax ?? 0;
    const maxId = Math.max(fMax, cMax);
    // 起步 = 13900000000 + max(id) + 100 (padding, 避开后续手动测试重复)
    _phoneCounter = 13900000000 + maxId + 100;
    info(`phone counter 从 ${_phoneCounter} 开始 (max id=${maxId}, padding=100, 含 deleted)`);
    await conn.end();
  } catch (e) {
    warn(`initPhoneCounter 失败 (用默认 ${_phoneCounter}): ${e}`);
  }
}

function nextPhone(): string {
  _phoneCounter++;
  return _phoneCounter.toString();
}

// ============================================
// Part A 前置: 给每个加盟节点建账号 (主人 2026-09-21 拍: 节点必须对应账号)
//   为什么要先建号: POST /api/franchisees 现在有硬门槛 —— 目标手机号没有可登录账号
//   直接拒 (requireAccountForNode, 见 src/lib/db/queries/franchisee-account.ts)。
//   密码统一为 SEED_PASSWORD, 方便真机 / 截图脚本用任意种子账号切号验证。
// ============================================

const SEED_PASSWORD = "dev123456";

/** 库里必须有一个 admin 账号当建号 actor (没有就建一个 dev 管理员) */
async function ensureSeedAdmin(): Promise<bigint> {
  const postgres = (await import("postgres")).default;
  const { drizzle } = await import("drizzle-orm/postgres-js");
  const { user } = await import("../src/lib/db/schema");
  const { eq } = await import("drizzle-orm");

  const conn = postgres(process.env.DATABASE_URL!);
  const db = drizzle(conn);
  try {
    const [admin] = await db
      .select({ id: user.id })
      .from(user)
      .where(eq(user.role, "admin"))
      .limit(1);
    if (!admin) {
      throw new Error("库里没有 admin 账号 —— 先跑 pnpm db:ensure-admin");
    }
    return admin.id;
  } finally {
    await conn.end();
  }
}

async function ensureSeedAccount(
  name: string,
  phone: string,
  adminId: bigint
): Promise<"created" | "existed" | "skipped"> {
  if (DRY_RUN) return "skipped";
  const { createAccountWithProfile } = await import("../src/lib/auth/registration");
  const postgres = (await import("postgres")).default;
  const { drizzle } = await import("drizzle-orm/postgres-js");
  const { user } = await import("../src/lib/db/schema");
  const { hashForLookup } = await import("../src/lib/crypto/field");
  const { eq } = await import("drizzle-orm");

  const conn = postgres(process.env.DATABASE_URL!);
  const db = drizzle(conn);
  try {
    const [existed] = await db
      .select({ id: user.id })
      .from(user)
      .where(eq(user.phoneHash, hashForLookup(phone)))
      .limit(1);
    if (existed) return "existed";
    await createAccountWithProfile({
      name,
      phone,
      password: SEED_PASSWORD,
      // 种子节点不是"被谁拉进来的" → 没有推荐码可填 (admin 建号豁免)
      allowNoReferral: true,
      actorUserId: adminId,
    });
    return "created";
  } finally {
    await conn.end();
  }
}

// ============================================
// 数据: 加盟商 (31 节点满二叉树, depth 0-4)
// 命名: 中国风 + 中老年养生行业气质 (符合 §1 项目 vibe)
// ============================================

interface FranchiseeSpec {
  name: string;
  referrerIndex?: number; // index into CREATED_FRANCHISEES
  sideHint?: "left" | "right";
  notes?: string;
}

// 31 节点, 5 层 (1+2+4+8+16)
const FRANCHISEE_SPECS: FranchiseeSpec[] = [
  // L0: 根 (depth 0)
  { name: "宋一鸣", notes: "测试数据 root / 公司创始人" },

  // L1: 2 节点 (depth 1)
  { name: "李建国", referrerIndex: 0, sideHint: "left", notes: "左线总经理" },
  { name: "王秀英", referrerIndex: 0, sideHint: "right", notes: "右线总经理" },

  // L2: 4 节点 (depth 2) — 李建国 + 王秀英 各 2 子
  { name: "陈大壮", referrerIndex: 1, sideHint: "left", notes: "李建国左线" },
  { name: "赵婉清", referrerIndex: 1, sideHint: "right", notes: "李建国右线" },
  { name: "周永福", referrerIndex: 2, sideHint: "left", notes: "王秀英左线" },
  { name: "郑美玲", referrerIndex: 2, sideHint: "right", notes: "王秀英右线" },

  // L3: 8 节点 (depth 3)
  { name: "孙志强", referrerIndex: 3, sideHint: "left" },
  { name: "冯晓燕", referrerIndex: 3, sideHint: "right" },
  { name: "韩德胜", referrerIndex: 4, sideHint: "left" },
  { name: "杨翠萍", referrerIndex: 4, sideHint: "right" },
  { name: "高建军", referrerIndex: 5, sideHint: "left" },
  { name: "林秀梅", referrerIndex: 5, sideHint: "right" },
  { name: "何志远", referrerIndex: 6, sideHint: "left" },
  { name: "吴丽华", referrerIndex: 6, sideHint: "right" },

  // L4: 16 节点 (depth 4)
  { name: "徐长山", referrerIndex: 7, sideHint: "left" },
  { name: "马春兰", referrerIndex: 7, sideHint: "right" },
  { name: "罗子轩", referrerIndex: 8, sideHint: "left" },
  { name: "梁彩凤", referrerIndex: 8, sideHint: "right" },
  { name: "宋海燕", referrerIndex: 9, sideHint: "left" },
  { name: "唐玉珍", referrerIndex: 9, sideHint: "right" },
  { name: "韩建军", referrerIndex: 10, sideHint: "left" },
  { name: "曹秀芳", referrerIndex: 10, sideHint: "right" },
  { name: "邓国华", referrerIndex: 11, sideHint: "left" },
  { name: "彭桂英", referrerIndex: 11, sideHint: "right" },
  { name: "蒋金凤", referrerIndex: 12, sideHint: "left" },
  { name: "沈万山", referrerIndex: 12, sideHint: "right" },
  { name: "蔡明远", referrerIndex: 13, sideHint: "left" },
  { name: "袁瑞华", referrerIndex: 13, sideHint: "right" },
  { name: "潘福临", referrerIndex: 14, sideHint: "left" },
  { name: "魏素珍", referrerIndex: 14, sideHint: "right" },
];

// ============================================
// 数据: 客户 (10 位, 5 种子 + 5 普通)
// 老带新 referral chain (customer.referrerId)
// 命名: 中老年常见名
// ============================================

interface CustomerSpec {
  name: string;
  gender?: "F" | "M";
  birthYear?: number;
  referrerIndex?: number;
  isSeed: boolean; // true = 种子 (无 wellness records), false = 普通 (有 wellness records)
  wellnessSpec?: {
    bodyPartIds: string[]; // 部位 id (e.g. "1"=肩颈, "2"=腰部)
    serviceItemId: string; // 服务 id (e.g. "1"=肩颈经络理疗)
    feedback?: string;
  };
}

const CUSTOMER_SPECS: CustomerSpec[] = [
  // ===== 5 种子 (无 wellness records, 潜在客户) =====
  {
    name: "苏亚芬",
    gender: "F",
    birthYear: 1962,
    isSeed: true,
  },
  {
    name: "柳桂香",
    gender: "F",
    birthYear: 1958,
    isSeed: true,
  },
  {
    name: "段福生",
    gender: "M",
    birthYear: 1955,
    isSeed: true,
  },
  {
    name: "雷金凤",
    gender: "F",
    birthYear: 1965,
    isSeed: true,
  },
  {
    name: "钱伯安",
    gender: "M",
    birthYear: 1970,
    isSeed: true,
  },

  // ===== 5 普通 (有 wellness records, 活跃客户) =====
  // 老带新链 1: 苏亚芬 → 倪秋月 → 龚秀珍
  {
    name: "倪秋月",
    gender: "F",
    birthYear: 1960,
    referrerIndex: 0, // 苏亚芬
    isSeed: false,
    wellnessSpec: {
      bodyPartIds: ["1"], // 肩颈
      serviceItemId: "1", // 肩颈经络理疗
      feedback: "做完肩膀舒服多了",
    },
  },
  {
    name: "龚秀珍",
    gender: "F",
    birthYear: 1956,
    referrerIndex: 5, // 倪秋月
    isSeed: false,
    wellnessSpec: {
      bodyPartIds: ["2"], // 腰部
      serviceItemId: "2", // 腰部推拿
      feedback: "腰疼缓解",
    },
  },

  // 老带新链 2: 柳桂香 → 章文彬
  {
    name: "章文彬",
    gender: "M",
    birthYear: 1968,
    referrerIndex: 1, // 柳桂香
    isSeed: false,
    wellnessSpec: {
      bodyPartIds: ["3"], // 膝盖
      serviceItemId: "3", // 艾灸调理
      feedback: "膝盖暖了",
    },
  },

  // 老带新链 3: 段福生 → 范雨桐 → 任金凤
  {
    name: "范雨桐",
    gender: "F",
    birthYear: 1963,
    referrerIndex: 2, // 段福生
    isSeed: false,
    wellnessSpec: {
      bodyPartIds: ["5"], // 背部
      serviceItemId: "4", // 拔罐
      feedback: "后背轻松",
    },
  },
  {
    name: "任金凤",
    gender: "F",
    birthYear: 1959,
    referrerIndex: 8, // 范雨桐
    isSeed: false,
    wellnessSpec: {
      bodyPartIds: ["4", "1"], // 头部 + 肩颈
      serviceItemId: "1", // 肩颈经络理疗
      feedback: "头不晕了",
    },
  },
];

// ============================================
// Part E: 创建 dev 用户 (13800138000) 绑 root franchisee
//   目的: dev login 后 /api/franchisees/me/tree 能看到完整 31 节点树
//   边界: user 表无 API endpoint (待补), 用 drizzle 直接 insert (绕过 audit log,
//         主人 ok — dev user 不是生产数据)
// ============================================

async function seedDevUser(rootFranchiseeId: string) {
  info("\n=== Part E: 创建 dev 用户绑 root franchisee ===");
  try {
    const postgres = (await import("postgres")).default;
    const { drizzle } = await import("drizzle-orm/postgres-js");
    const { user } = await import("../src/lib/db/schema");
    const { sql } = await import("drizzle-orm");
    const { encryptField, hashForLookup } = await import("../src/lib/crypto/field");

    const conn = postgres(process.env.DATABASE_URL!);
    const db = drizzle(conn);

    const devPhone = "13800138000";
    const phoneEncrypted = encryptField(devPhone);
    const phoneHash = hashForLookup(devPhone);

    // 只在用户不存在时插入 (idempotent)
    const existing = await db
      .select({ id: user.id })
      .from(user)
      .where(sql`${user.phoneHash} = ${phoneHash}`)
      .limit(1);

    if (existing.length > 0) {
      // update franchisee_id 绑 root
      await db
        .update(user)
        .set({ franchiseeId: BigInt(rootFranchiseeId), updatedAt: new Date() })
        .where(sql`${user.id} = ${existing[0].id}`);
      ok(`dev 用户已存在 (id=${existing[0].id}), 绑 franchiseeId=${rootFranchiseeId}`);
    } else {
      await db.insert(user).values({
        name: "SeedTest-dev用户",
        phoneEncrypted,
        phoneHash,
        role: "sales",
        isActive: true,
        franchiseeId: BigInt(rootFranchiseeId),
      });
      ok(`dev 用户已创建 + 绑 franchiseeId=${rootFranchiseeId}`);
    }

    await conn.end();
  } catch (e) {
    warn(`seedDevUser 跳过 (可能 env 未加载或表不存在): ${e}`);
  }
}

async function main() {
  info(`API_BASE: ${API_BASE}`);
  info(`DRY_RUN: ${DRY_RUN}`);
  info(`Total to create: ${FRANCHISEE_SPECS.length} franchisees + ${CUSTOMER_SPECS.length} customers`);

  // 健康检查
  try {
    await apiGet("/api/health");
    ok("API 健康检查通过");
  } catch (e) {
    err(`API 健康检查失败: ${e}`);
    if (!DRY_RUN) {
      process.exit(1);
    }
  }

  await initPhoneCounter();

  // 取一个管理员账号 (建号要 actorUserId; 库里没有就先建)
  const adminId = await ensureSeedAdmin();

  // ===== Part A: 加盟商 31 节点 =====
  info("\n=== Part A: 创建加盟商 (31 节点满二叉, depth 0-4) ===");
  info("  节点 ⇒ 账号: 每个节点先建账号, 再建节点 (主人 2026-09-21 拍)");
  const createdFranchisees: { id: string; name: string }[] = [];

  for (let i = 0; i < FRANCHISEE_SPECS.length; i++) {
    const spec = FRANCHISEE_SPECS[i];
    const phone = nextPhone();
    const payload: Record<string, unknown> = {
      name: `${PREFIX}${spec.name}`,
      phone,
      notes: spec.notes,
    };
    // 先建账号 (否则 POST /api/franchisees 会被"节点必须对应账号"门槛拒掉)
    try {
      const acc = await ensureSeedAccount(`${PREFIX}${spec.name}`, phone, adminId);
      if (acc === "created") info(`  · 账号已建 ${phone}`);
    } catch (e) {
      err(`账号创建失败 (${spec.name}): ${e}`);
      if (!DRY_RUN) process.exit(1);
    }
    if (spec.referrerIndex !== undefined && createdFranchisees[spec.referrerIndex]) {
      payload.referrerId = createdFranchisees[spec.referrerIndex].id;
      payload.sideHint = spec.sideHint;
    }
    try {
      const f = await apiPost<{ id: string; name: string }>("/api/franchisees", payload);
      if (f) {
        createdFranchisees.push({ id: f.id, name: f.name });
        ok(`[${i + 1}/${FRANCHISEE_SPECS.length}] ${spec.name} (id=${f.id}, depth=${computedDepth(i)})`);
      } else {
        createdFranchisees.push({ id: `dry-${i}`, name: spec.name });
      }
    } catch (e) {
      err(`加盟商 ${spec.name} 创建失败: ${e}`);
      if (!DRY_RUN) {
        process.exit(1);
      }
    }
  }

  // ===== Part B+C: 客户 10 位 =====
  info("\n=== Part B+C: 创建客户 (5 种子 + 5 普通, 含老带新 referral) ===");
  const createdCustomers: { id: string; name: string; isSeed: boolean }[] = [];

  for (let i = 0; i < CUSTOMER_SPECS.length; i++) {
    const spec = CUSTOMER_SPECS[i];
    const phone = nextPhone();
    const payload: Record<string, unknown> = {
      name: `${PREFIX}${spec.name}`,
      phone,
      gender: spec.gender,
      birthYear: spec.birthYear,
      // 种子客户 = 显式开关 (customer.is_seed, 主人 2026-09-18 拍)
      //   改了这里 /api/customers?type=seed 才筛得出来 (旧数据都是 normal)
      isSeed: spec.isSeed,
    };
    if (spec.referrerIndex !== undefined && createdCustomers[spec.referrerIndex]) {
      payload.referrerId = createdCustomers[spec.referrerIndex].id;
    }
    try {
      const c = await apiPost<{ id: string; name: string }>("/api/customers", payload);
      if (c) {
        createdCustomers.push({ id: c.id, name: c.name, isSeed: spec.isSeed });
        ok(`[${i + 1}/${CUSTOMER_SPECS.length}] ${spec.name} (${spec.isSeed ? "种子" : "普通"}, id=${c.id})`);
      } else {
        createdCustomers.push({ id: `dry-${i}`, name: spec.name, isSeed: spec.isSeed });
      }
    } catch (e) {
      err(`客户 ${spec.name} 创建失败: ${e}`);
      if (!DRY_RUN) {
        process.exit(1);
      }
    }
  }

  // ===== Part D: 给"普通"客户加 wellness records =====
  // 种子 = 没养生记录, 普通 = 有养生记录 (用户 2026-09-16 定义)
  info("\n=== Part D: 为「普通」客户添加养生记录 (区分种子) ===");
  for (let i = 0; i < createdCustomers.length; i++) {
    const c = createdCustomers[i];
    const spec = CUSTOMER_SPECS[i];
    if (c.isSeed || !spec.wellnessSpec) continue;

    const wsPayload = {
      customerId: c.id,
      serviceDate: new Date().toISOString().slice(0, 10),
      customerFeedback: spec.wellnessSpec.feedback,
      serviceItemId: spec.wellnessSpec.serviceItemId,
      bodyPartIds: spec.wellnessSpec.bodyPartIds,
      preCondition: {},
      postCondition: {},
    };
    try {
      await apiPost("/api/wellness-records", wsPayload);
      ok(`[普通] ${spec.name} 加养生记录 (bodyPartIds=${wsPayload.bodyPartIds.join(",")})`);
    } catch (e) {
      warn(`普通客户 ${spec.name} 加养生记录失败 (可能 endpoint 不存在): ${e}`);
    }
  }

  // ===== Part E: dev 用户绑 root (上面所有数据创建完了再能拿 root id) =====
  const rootFranchisee = createdFranchisees[0];
  if (rootFranchisee) {
    await seedDevUser(rootFranchisee.id);
  }

  // ===== 总结 =====
  info("\n=== 总结 ===");
  ok(`加盟商: ${createdFranchisees.length} 个 (期望 31, depth 0-4 满二叉)`);
  ok(`种子客户: ${createdCustomers.filter((c) => c.isSeed).length} 个 (期望 5)`);
  ok(`普通客户: ${createdCustomers.filter((c) => !c.isSeed).length} 个 (期望 5, 含老带新链)`);
  ok("老带新 referral chains:");
  info("  Chain 1: 苏亚芬 (种子) → 倪秋月 (普通) → 龚秀珍 (普通)");
  info("  Chain 2: 柳桂香 (种子) → 章文彬 (普通)");
  info("  Chain 3: 段福生 (种子) → 范雨桐 (普通) → 任金凤 (普通)");
  info("  Standalone: 雷金凤 (种子), 钱伯安 (种子)");
}

function computedDepth(i: number): number {
  // 0 -> 0; 1-2 -> 1; 3-6 -> 2; 7-14 -> 3; 15-30 -> 4
  if (i === 0) return 0;
  if (i <= 2) return 1;
  if (i <= 6) return 2;
  if (i <= 14) return 3;
  return 4;
}

main().catch((e) => {
  err(`Fatal: ${e}`);
  process.exit(1);
});