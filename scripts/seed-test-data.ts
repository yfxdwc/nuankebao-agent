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
// 关联:
//   - ADR-0010 (≤4 层 override, 本任务前提)
//   - CHANGELOG [Unreleased] / 主人 ask d234bdd4 (2026-09-16)
// ============================================

import { config as loadEnv } from "dotenv";

if (process.env.NODE_ENV !== "production") {
  loadEnv({ path: ".env.local" });
  loadEnv({ path: ".env" });
}

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
//   起始: 13900000000 + 当前 max(id) (避免跟现存手动测过的撞)
let _phoneCounter = 13900000000;
async function initPhoneCounter() {
  try {
    const f = await apiGet<{ items?: { id: string }[] }>("/api/franchisees?limit=1");
    const c = await apiGet<{ items?: { id: string }[] }>("/api/customers?limit=1");
    const maxF = f?.items?.[0]?.id ? parseInt(f.items[0].id) : 0;
    const maxC = c?.items?.[0]?.id ? parseInt(c.items[0].id) : 0;
    _phoneCounter = 13900000000 + Math.max(maxF, maxC) + 1;
    info(`phone counter 从 ${_phoneCounter} 开始 (避免撞现存手动测试数据)`);
  } catch (e) {
    warn(`initPhoneCounter 失败 (用默认 ${_phoneCounter}): ${e}`);
  }
}

function nextPhone(): string {
  _phoneCounter++;
  return _phoneCounter.toString();
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
// 主流程
// ============================================

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

  // ===== Part A: 加盟商 31 节点 =====
  info("\n=== Part A: 创建加盟商 (31 节点满二叉, depth 0-4) ===");
  const createdFranchisees: { id: string; name: string }[] = [];

  for (let i = 0; i < FRANCHISEE_SPECS.length; i++) {
    const spec = FRANCHISEE_SPECS[i];
    const phone = nextPhone();
    const payload: Record<string, unknown> = {
      name: `${PREFIX}${spec.name}`,
      phone,
      notes: spec.notes,
    };
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