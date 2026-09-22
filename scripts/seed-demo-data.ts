// ============================================
// 演示数据 (dev): 一整套"以人为本"的完整样本
// ============================================
// 主人 2026-09-22: 「开发环境中为系统管理员创建完整的客户、图谱、加盟节点,
//                  创建足够多的测试用户和客户」
//
// 造什么 (全部走**唯一入口**, 不绕不变量):
//   ① 36 个测试账号 (createAccountWithProfile: 账号 + 客户档案 + 自己的邀请码)
//      · 主树 A 19 个 (depth 0-4, 满二叉 + 第 5 层部分)
//      · 小树 B 3 个 / 小树 C 1 个  → 系统视角可见**多棵树** (ADR-0014)
//      · 未接入 13 个 (只注册不加盟) → 管理员图谱里的"未加盟 N"
//   ② 加盟节点 23 个 (createFranchisee: 节点必须对应账号 + 落位算法 + 自动建档)
//   ③ 客户 ~80 个:
//      · 每个树内用户 3-4 个手工客户 (owner = 她, 普通/种子 混合)
//      · 10 个「直营客户」归**系统管理员** (她的客户列表不再是空的)
//      · 认领 10 个"已注册但未接入"的用户 → 展示「已注册」标 + 归属先到先得
//   ④ 会员 15 个 (grantDays 30 天) → 充值用户 / 免费用户两种都能看到
//   ⑤ 互动 ~120 条 + 养生记录 ~30 条 → 列表排序/紧急度/详情页不再是空壳
//
// 用法:
//   npx tsx scripts/seed-demo-data.ts            # 幂等创建 (已存在的跳过)
//   npx tsx scripts/seed-demo-data.ts --dry-run  # 只打印计划
//   npx tsx scripts/seed-demo-data.ts --reset    # 删掉本脚本创建的全部数据
//
// 边界: 只动**本脚本手机号段** (1382220xxxx) 与「演示-」人名, 不碰别人的数据。
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { eq, inArray, sql } from "drizzle-orm";

import { db } from "@/lib/db";
import {
  customer,
  followUpTask,
  franchisee,
  interaction,
  membership,
  referralCode,
  referralReward,
  user,
  wellnessRecord,
  wellnessRecordBodyPart,
  wellnessRecordProduct,
  entitlementGrant,
} from "@/lib/db/schema";
import { hashForLookup } from "@/lib/crypto/field";
import { createAccountWithProfile } from "@/lib/auth/registration";
import { createFranchisee } from "@/lib/db/queries/franchisee";
import { claimCustomerOwnership, createCustomer } from "@/lib/db/queries/customer";
import { createInteraction } from "@/lib/db/queries/interaction";
import { createWellnessRecord } from "@/lib/db/queries/wellness-record";
import { grantDays } from "@/lib/billing/entitlements";

const DRY_RUN = process.argv.includes("--dry-run");
const RESET = process.argv.includes("--reset");

const NAME_TAG = "演示-";
const PHONE_BASE = 13822200000; // 演示号段: 138 2220 0001 ...
const PASSWORD = "Test12345";

let seq = 0;
const nextPhone = () => String(PHONE_BASE + ++seq);

const log = (s: string) => console.log(s);
const ok = (s: string) => console.log(`  ✅ ${s}`);
const warn = (s: string) => console.log(`  ⚠️  ${s}`);

// ── 名字池 (中年女性为主, 贴近真实用户群) ──
const TREE_A_NAMES = [
  "王秀兰", "李桂芳", "张淑珍", "刘玉梅", "陈凤英", "杨春华", "赵丽娟",
  "黄美玲", "周雅琴", "吴晓燕", "徐静怡", "孙巧云", "马文娟", "朱建平",
  "胡海燕", "郭秀英", "林小梅", "何丽华", "高翠萍",
];
const TREE_B_NAMES = ["罗金凤", "郑秋香", "梁玉珍"];
const TREE_C_NAMES = ["谢兰英"];
const STANDALONE_NAMES = [
  "宋佳琪", "唐月华", "韩冬梅", "冯桂香", "曹丽萍", "邓秀珍", "彭玉华",
  "曾美凤", "肖春兰", "田桂英", "董雅静", "潘淑华", "袁秀荣",
];
const CUSTOMER_NAMES = [
  "蒋金娣", "蔡玉兰", "余美华", "杜春燕", "苏小凤", "卢桂珍", "沈玉梅",
  "严淑英", "金兰香", "贾秀云", "丁美娟", "庄亚萍", "崔凤兰", "范丽珍",
  "石桂香", "姚美华", "方兰英", "汤玉珍", "廖春梅", "邹桂英", "熊秀兰",
  "孟丽华", "秦玉静", "邱兰英", "侯美凤", "江秀珍", "尹桂芳", "薛春华",
  "闫玉萍", "段美玲", "付秀琴", "龙金花", "葛雅琴", "章丽娟", "阮秀英",
  "倪桂华", "施玉兰", "岳美珍", "覃丽红", "武秀华", "翁金凤", "苟玉梅",
  "毕兰芳", "路秀云", "焦美华", "郝桂英", "霍玉珍", "汤桂兰", "杨丽萍",
  "邢秀荣", "裴玉华", "陆金娣", "荣美玲", "翁丽华", "荀桂香", "封玉兰",
  "芮秀英", "靳美华", "汲兰英", "邴玉珍", "糜秀兰", "松桂华", "井美凤",
  "段玉兰", "富秀珍", "巫桂英", "乌美华", "隗玉兰", "隆秀英", "师桂珍",
  "巩美华", "厍玉英", "聂兰香", "晁秀梅", "勾玉华", "敖桂兰", "融美珍",
  "冷秀英", "訾玉梅", "辛兰英", "阚美华", "简桂珍", "空秀兰", "曾玉华",
];

const TAG_PREFIX = "演示-";
const fullName = (n: string) => `${TAG_PREFIX}${n}`;

interface SeedUser {
  id: bigint;
  fid: bigint | null;
  name: string;
  phone: string;
}

const auditCtx = (adminId: bigint) => ({ userId: adminId, ipAddress: null });

async function findAdmin(): Promise<bigint> {
  const [preferred] = await db
    .select({ id: user.id })
    .from(user)
    .where(eq(user.username, "admin"))
    .limit(1);
  if (preferred) return preferred.id;
  const [anyAdmin] = await db
    .select({ id: user.id })
    .from(user)
    .where(eq(user.role, "admin"))
    .limit(1);
  if (!anyAdmin) throw new Error("库里没有 admin —— 先跑 pnpm db:ensure-admin");
  return anyAdmin.id;
}

// ============================================
// --reset
// ============================================
async function reset(adminId: bigint): Promise<void> {
  log("\n=== 清理演示数据 ===");
  const users = await db
    .select({ id: user.id, fid: user.franchiseeId, customerId: user.customerId })
    .from(user)
    .where(sql`${user.name} LIKE ${NAME_TAG + "%"}`);
  const userIds = users.map((u) => u.id);
  if (userIds.length === 0) {
    log("  (没有演示账号, 无需清理)");
    return;
  }

  // 这些账号名下的客户档案 (手工建档的)
  const customers = await db
    .select({ id: customer.id })
    .from(customer)
    .where(sql`${customer.name} LIKE ${NAME_TAG + "%"} OR ${customer.ownerId} IN ${sql.raw(`(${userIds.join(",")})`)}`);
  const customerIds = customers.map((c) => c.id);

  if (customerIds.length > 0) {
    const idList = sql.raw(`(${customerIds.join(",")})`);
    const wrecs = await db
      .select({ id: wellnessRecord.id })
      .from(wellnessRecord)
      .where(sql`${wellnessRecord.customerId} IN ${idList}`);
    const wIds = wrecs.map((w) => w.id);
    if (wIds.length > 0) {
      const wList = sql.raw(`(${wIds.join(",")})`);
      await db.execute(sql.raw(`DELETE FROM wellness_record_body_part WHERE wellness_record_id IN ${wList}`));
      await db.execute(sql.raw(`DELETE FROM wellness_record_product WHERE wellness_record_id IN ${wList}`));
      await db.execute(sql.raw(`DELETE FROM wellness_record WHERE id IN ${wList}`));
    }
    await db.execute(sql.raw(`DELETE FROM interaction WHERE customer_id IN ${idList}`));
    await db.execute(sql.raw(`DELETE FROM follow_up_task WHERE customer_id IN ${idList}`));
    await db.execute(sql.raw(`DELETE FROM customer WHERE id IN ${idList}`));
  }

  const uList = sql.raw(`(${userIds.join(",")})`);
  const fids = users.map((u) => u.fid).filter((v): v is bigint => v != null);
  if (fids.length > 0) {
    await db.execute(sql.raw(`DELETE FROM franchise_placement_confirm WHERE request_id IN (SELECT id FROM franchise_placement_request WHERE initiator_fid IN (${fids.join(",")}) OR target_parent_fid IN (${fids.join(",")}))`));
    await db.execute(sql.raw(`DELETE FROM franchise_placement_request WHERE initiator_fid IN (${fids.join(",")}) OR target_parent_fid IN (${fids.join(",")})`));
    await db.execute(sql.raw(`UPDATE franchisee SET placement_parent_id = NULL WHERE placement_parent_id IN (${fids.join(",")})`));
    await db.execute(sql.raw(`DELETE FROM franchise_placement_confirm WHERE confirmer_fid IN (${fids.join(",")})`));
    await db.execute(sql.raw(`DELETE FROM franchisee WHERE id IN (${fids.join(",")})`));
  }
  await db.execute(sql.raw(`DELETE FROM referral_reward WHERE referrer_user_id IN ${uList} OR referee_user_id IN ${uList}`));
  await db.execute(sql.raw(`DELETE FROM referral_code WHERE user_id IN ${uList}`));
  await db.execute(sql.raw(`DELETE FROM entitlement_grant WHERE user_id IN ${uList}`));
  await db.execute(sql.raw(`DELETE FROM membership WHERE user_id IN ${uList}`));
  await db.execute(sql.raw(`DELETE FROM "user" WHERE id IN ${uList}`));

  ok(`已清理: ${userIds.length} 账号 / ${customerIds.length} 客户 / ${fids.length} 节点`);
}

// ============================================
// 建号 (幂等: 同手机号已有 → 复用)
// ============================================
async function ensureAccount(
  name: string,
  phone: string,
  adminId: bigint
): Promise<SeedUser> {
  const h = hashForLookup(phone);
  const [existing] = await db
    .select({ id: user.id, fid: user.franchiseeId })
    .from(user)
    .where(eq(user.phoneHash, h))
    .limit(1);
  if (existing) {
    return { id: existing.id, fid: existing.fid, name, phone };
  }
  const res = await createAccountWithProfile({
    name,
    phone,
    password: PASSWORD,
    role: "sales",
    allowNoReferral: true, // 演示账号: 不强制推荐码 (它们本身就是被造出来的)
    actorUserId: adminId,
    ipAddress: undefined,
  });
  return { id: res.userId, fid: null, name, phone };
}

// ============================================
// main
// ============================================
async function main(): Promise<void> {
  const adminId = await findAdmin();
  log(`\n=== 演示数据 ${DRY_RUN ? "(dry-run)" : RESET ? "(reset)" : ""} ===`);
  log(`admin = user#${adminId}`);

  if (RESET) {
    if (DRY_RUN) {
      log("(dry-run: 不实际清理)");
      return;
    }
    await reset(adminId);
    return;
  }

  if (DRY_RUN) {
    log(`计划: ${TREE_A_NAMES.length + TREE_B_NAMES.length + TREE_C_NAMES.length + STANDALONE_NAMES.length} 个测试账号`);
    log(`计划: ${TREE_A_NAMES.length + TREE_B_NAMES.length + TREE_C_NAMES.length} 个加盟节点`);
    log(`计划: ${CUSTOMER_NAMES.length} 个手工客户 + 10 个认领 + 10 个管理员直营客户`);
    return;
  }

  const ctx = auditCtx(adminId);

  // ── ① 账号 ──
  log("\n① 测试账号");
  const mk = async (n: string) => {
    const phone = nextPhone();
    const u = await ensureAccount(fullName(n), phone, adminId);
    return u;
  };

  const treeA: SeedUser[] = [];
  for (const n of TREE_A_NAMES) treeA.push(await mk(n));
  const treeB: SeedUser[] = [];
  for (const n of TREE_B_NAMES) treeB.push(await mk(n));
  const treeC: SeedUser[] = [];
  for (const n of TREE_C_NAMES) treeC.push(await mk(n));
  const standalone: SeedUser[] = [];
  for (const n of STANDALONE_NAMES) standalone.push(await mk(n));
  ok(`${treeA.length + treeB.length + treeC.length + standalone.length} 个账号就绪 (密码 ${PASSWORD})`);

  // ── ② 加盟节点 (走 createFranchisee: 落位算法 + 绑账号 + 建档) ──
  log("\n② 加盟节点 (多棵树)");
  const buildTree = async (members: SeedUser[], label: string) => {
    // 第 1 个建根, 其余 BFS 挂在已有节点下 (referrerId = 树内某个节点)
    for (let i = 0; i < members.length; i++) {
      const m = members[i];
      const [already] = await db
        .select({ fid: user.franchiseeId })
        .from(user)
        .where(eq(user.id, m.id))
        .limit(1);
      if (already?.fid) {
        m.fid = already.fid;
        continue;
      }
      const parentIdx = i === 0 ? null : Math.floor((i - 1) / 2); // 二叉树 BFS
      const parent = parentIdx == null ? null : members[parentIdx];
      const f = await createFranchisee(
        {
          name: m.name,
          referralCode: undefined,
          phone: m.phone,
          referrerId: parent?.fid ?? undefined,
        },
        ctx,
        adminId
      );
      m.fid = BigInt(f.id);
    }
    ok(`${label}: ${members.length} 节点 (根 = ${members[0]?.name})`);
  };
  await buildTree(treeA, "树 A (主树, depth 0-4)");
  await buildTree(treeB, "树 B (小树)");
  await buildTree(treeC, "树 C (单节点树)");

  // ── ③ 客户 ──
  log("\n③ 客户");
  const ownerPool = [...treeA, ...treeB, ...treeC];
  let created = 0;
  let nameIdx = 0;
  const nextCustomerName = () =>
    fullName(CUSTOMER_NAMES[nameIdx++ % CUSTOMER_NAMES.length]);

  const makeCustomer = async (
    owner: SeedUser | null,
    opts: { seed?: boolean; gender?: "M" | "F" | "U" } = {}
  ) => {
    const name = nextCustomerName();
    const phone = nextPhone();
    const h = hashForLookup(phone);
    const [dup] = await db
      .select({ id: customer.id })
      .from(customer)
      .where(eq(customer.phoneHash, h))
      .limit(1);
    if (dup) return { id: dup.id };
    const view = await createCustomer(
      {
        name,
        phone,
        gender: opts.gender ?? (nameIdx % 5 === 0 ? "M" : "F"),
        birthYear: 1955 + (nameIdx % 30),
        isSeed: opts.seed,
        healthTags: [["肩颈", "睡眠差"], ["腰椎", "湿气重"], ["膝关节", "气血不足"]][nameIdx % 3],
      },
      ctx,
      owner?.id ?? adminId
    );
    created++;
    return { id: BigInt(view.id) };
  };

  // 3.1 每个树内用户 3 个手工客户 (普通/种子混合)
  const ownedCustomers: Array<{ id: bigint; ownerId: bigint }> = [];
  for (const owner of ownerPool) {
    for (let k = 0; k < 3; k++) {
      const seed = k === 2; // 第 3 个当种子客户
      const c = await makeCustomer(owner, { seed });
      ownedCustomers.push({ id: c.id, ownerId: owner.id });
    }
  }
  ok(`树内用户手工客户: ${ownerPool.length * 3} 个`);

  // 3.2 管理员直营客户 (她的客户列表不再是空的)
  const adminOwned: bigint[] = [];
  for (let k = 0; k < 10; k++) {
    const c = await makeCustomer(null, { seed: k % 4 === 0 });
    adminOwned.push(c.id);
  }
  ok(`管理员直营客户: 10 个`);

  // 3.3 认领"已注册但未接入"的用户 → 「已注册」标 + 先到先得
  let claimed = 0;
  for (let i = 0; i < Math.min(10, standalone.length); i++) {
    const target = standalone[i];
    const owner = ownerPool[i % ownerPool.length];
    const [prof] = await db
      .select({ id: customer.id })
      .from(customer)
      .where(eq(customer.phoneHash, hashForLookup(target.phone)))
      .limit(1);
    if (!prof) continue;
    const res = await claimCustomerOwnership(prof.id, owner.id, ctx, owner.fid);
    if (res.ok) claimed++;
  }
  ok(`认领已注册用户: ${claimed} 个 (展示「已注册」标)`);

  // ── ④ 会员 (充值用户) ──
  log("\n④ 会员");
  let members = 0;
  for (let i = 0; i < ownerPool.length; i++) {
    if (i % 2 !== 0) continue; // 一半用户是会员
    try {
      await grantDays({
        userId: ownerPool[i].id,
        days: 30,
        reason: "manual",
        idempotencyKey: `demo-seed-${ownerPool[i].id}`,
        note: "演示数据 (dev)",
      });
      members++;
    } catch {
      /* 幂等: 已发过就跳过 */
    }
  }
  ok(`会员: ${members} 个 (grantDays 30 天)`);

  // ── ⑤ 互动 + 养生记录 ──
  log("\n⑤ 互动 / 养生记录");
  const interTypes = ["phone", "wechat", "visit", "holiday_greeting"] as const;
  const summaries = [
    "电话回访: 反馈肩颈舒服多了, 提醒下周再来",
    "微信沟通: 询问艾灸后反应, 已解答",
    "到店: 体验肩颈经络理疗, 当场办了次卡",
    "节日问候: 发了养生小贴士, 回复很积极",
  ];
  let interCount = 0;
  for (let i = 0; i < ownedCustomers.length; i++) {
    const c = ownedCustomers[i];
    if (i % 3 === 0) continue; // 2/3 的客户有互动 (剩下的让列表有"久未联系")
    const n = 1 + (i % 2);
    for (let k = 0; k < n; k++) {
      await createInteraction(
        {
          customerId: c.id.toString(),
          type: interTypes[(i + k) % interTypes.length],
          summary: summaries[(i + k) % summaries.length],
        },
        ctx,
        c.ownerId
      );
      interCount++;
    }
  }
  ok(`互动记录: ${interCount} 条 (顺带更新 lastInteractionAt → 紧急度排序有意义)`);

  let wellnessCount = 0;
  for (let i = 0; i < ownedCustomers.length; i++) {
    if (i % 4 !== 0) continue; // 1/4 的客户做过养生服务
    const c = ownedCustomers[i];
    const owner = ownerPool.find((o) => o.id === c.ownerId);
    try {
      await createWellnessRecord(
        {
          customerId: c.id.toString(),
          serviceDate: new Date(Date.now() - (i % 30) * 86400_000)
            .toISOString()
            .slice(0, 10),
          serviceItemId: String((i % 6) + 1),
          bodyPartIds: [String((i % 9) + 1), String(((i + 3) % 9) + 1)],
          preCondition: { 主诉: "肩颈僵硬, 睡眠浅" },
          postCondition: { 反馈: "轻松一些, 温热感明显" },
          processNote: "手法 + 艾灸 30 分钟",
          customerFeedback: "挺舒服的, 下次还来",
        },
        ctx,
        owner?.id ?? adminId
      );
      wellnessCount++;
    } catch {
      /* 字典不齐时跳过 */
    }
  }
  ok(`养生记录: ${wellnessCount} 条`);

  // ── 汇总 ──
  const [cnt] = await db.execute<{ u: number; c: number; f: number }>(sql`
    SELECT
      (SELECT count(*)::int FROM "user") AS u,
      (SELECT count(*)::int FROM customer WHERE deleted_at IS NULL) AS c,
      (SELECT count(*)::int FROM franchisee WHERE deleted_at IS NULL) AS f
  `);
  log("\n=== 完成 ===");
  log(`  库现状: 账号 ${cnt?.u} / 客户 ${cnt?.c} / 节点 ${cnt?.f}`);
  log(`  登录: 任意演示手机号 (${PHONE_BASE + 1}...) + 密码 ${PASSWORD}`);
  log(`  卸载: npx tsx scripts/seed-demo-data.ts --reset`);
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error("❌ 失败:", e instanceof Error ? e.message : String(e));
    process.exit(1);
  });
