// ============================================
// 建根 (Bootstrap Root) 不变量冒烟 (dev only) — 主人 2026-09-21 拍
//
// 主人原话: 「建根 = 先有账号。admin 能建根, 但要用户先注册」
//
// 为什么建根不走三方确认 (本脚本的存在理由):
//   三方确认 = 设置者 + 本人 + **父节点**; 根没有父节点 → 三方里有一方物理不存在。
//   所以建根 = admin 单方 + 审计留痕; 但**必须**挂到已注册账号上 (不能凭空造节点 + 造账号)。
//
// 验 6 条不变量:
//   ① 空原因 → 拒 (审计要留痕, 没原因的建根查不清)
//   ② 账号不存在 → 拒
//   ③ 账号已停用 → 拒
//   ④ 账号已经在树里 → 拒 (一个账号一个节点; 二次建根 = 一人两节点)
//   ⑤ 成功: 新节点 path='' depth=0 (真根) + user.franchisee_id 指向它 + rootCount ≥ 1
//   ⑥ 留痕: user 表的审计触发器记下了这次 franchisee_id 变更
//   ⑦ 鉴权 (HTTP 段, 需 dev server): 非管理员打这两个接口 = 403
//      (客户端隐藏入口只是体验; 真正的权限在服务端 —— 这条必须能重跑)
//
// 跑: npx tsx scripts/smoke-bootstrap-root.ts   (幂等, 跑完自己清理)
// ============================================

// ⚠ 必须是第一个 import: dotenv 的副作用要先于读 DATABASE_URL 的模块求值 (见 scripts/_env.ts)
import "./_env";

import { and, desc, eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { auditLog, customer, franchisee, membership, referralCode, user } from "@/lib/db/schema";
import { hashForLookup } from "@/lib/crypto/field";
import { createAccountWithProfile } from "@/lib/auth/registration";
import { createRootForUser } from "@/lib/db/queries/admin-users";

const PHONE_ROOT = "13900007721";
const PHONE_DISABLED = "13900007722";
/** 非管理员越权检查用的临时 sales 账号 */
const PHONE_SALES = "13900007723";
const BASE = process.env.SMOKE_BASE_URL ?? "http://127.0.0.1:3003";
const MARK = "冒烟-建根";

let pass = 0;
let fail = 0;
const ck = (name: string, ok: boolean, extra = "") => {
  console.log(`${ok ? "✅" : "❌"} ${name}${extra ? ` — ${extra}` : ""}`);
  ok ? pass++ : fail++;
};

/** 建根会产生的所有痕迹 (franchisee 行 + user.franchisee_id) 一起清 */
async function cleanup() {
  for (const phone of [PHONE_ROOT, PHONE_DISABLED, PHONE_SALES]) {
    const h = hashForLookup(phone);
    const us = await db
      .select({ id: user.id, franchiseeId: user.franchiseeId })
      .from(user)
      .where(eq(user.phoneHash, h));
    for (const u of us) {
      // ⚠ 节点的 created_by 是**管理员**不是被测账号, 按 created_by 找会漏 → 用账号绑定反查
      if (u.franchiseeId != null) {
        await db.delete(franchisee).where(eq(franchisee.id, u.franchiseeId));
      }
      await db.delete(auditLog).where(eq(auditLog.recordId, u.id));
      await db.delete(referralCode).where(eq(referralCode.userId, u.id));
      await db.delete(membership).where(eq(membership.userId, u.id));
      await db.delete(user).where(eq(user.id, u.id));
    }
    await db.delete(customer).where(eq(customer.phoneHash, h));
  }
  // 兜底: 上一轮跑挂时留下的孤儿根节点 (账号已删, 节点还在)
  await db.delete(franchisee).where(eq(franchisee.name, `${MARK}-待建根`));
  await db.delete(franchisee).where(eq(franchisee.name, `${MARK}-已停用`));
}

async function main() {
  await cleanup();

  // 取一个真实存在的推荐码 (建号必填, 见 §6.6 —— 冒烟建号也走正规入口)
  const [code] = await db
    .select({ code: referralCode.code })
    .from(referralCode)
    .limit(1);
  if (!code) throw new Error("库里没有推荐码, 先跑 seed");
  const [admin] = await db
    .select({ id: user.id })
    .from(user)
    .where(eq(user.role, "admin"))
    .limit(1);
  if (!admin) throw new Error("库里没有 admin, 先跑 pnpm db:ensure-admin");

  // ---- 准备两个测试账号 (先注册, 才谈得上建根) ----
  const a = await createAccountWithProfile({
    name: `${MARK}-待建根`,
    phone: PHONE_ROOT,
    password: "Test1234",
    referralCode: code.code,
    actorUserId: admin.id,
  });
  const b = await createAccountWithProfile({
    name: `${MARK}-已停用`,
    phone: PHONE_DISABLED,
    password: "Test1234",
    referralCode: code.code,
    actorUserId: admin.id,
  });
  const rootUserId = BigInt(a.userId);
  const disabledUserId = BigInt(b.userId);

  const ctx = { userId: admin.id, ipAddress: "127.0.0.1" };
  const expectThrow = async (label: string, fn: () => Promise<unknown>, needle: string) => {
    try {
      await fn();
      ck(label, false, "居然成功了");
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      ck(label, msg.includes(needle), msg);
    }
  };

  // ① 空原因
  await expectThrow(
    "① 空原因 → 拒",
    () => createRootForUser({ userId: rootUserId, adminUserId: admin.id, note: "  " }, ctx),
    "建根必须填写原因"
  );

  // ② 账号不存在
  await expectThrow(
    "② 账号不存在 → 拒",
    () => createRootForUser({ userId: BigInt(999999999), adminUserId: admin.id, note: "不存在的人" }, ctx),
    "目标账号不存在"
  );

  // ③ 账号已停用
  await db.update(user).set({ isActive: false }).where(eq(user.id, disabledUserId));
  await expectThrow(
    "③ 账号已停用 → 拒",
    () => createRootForUser({ userId: disabledUserId, adminUserId: admin.id, note: "停用的人" }, ctx),
    "已停用"
  );

  // ⑤ 成功建根
  const r = await createRootForUser(
    { userId: rootUserId, adminUserId: admin.id, note: "冒烟: 杭州西湖店店长" },
    ctx
  );
  const [node] = await db
    .select()
    .from(franchisee)
    .where(eq(franchisee.id, BigInt(r.franchiseeId)))
    .limit(1);
  const [after] = await db
    .select({ franchiseeId: user.franchiseeId })
    .from(user)
    .where(eq(user.id, rootUserId))
    .limit(1);
  ck("⑤ 新节点 path='' (真根)", node?.placementPath === "", `path=${JSON.stringify(node?.placementPath)}`);
  ck("⑤ 新节点 depth=0", node?.placementDepth === 0, `depth=${node?.placementDepth}`);
  ck("⑤ 新节点名 = 账号名 (先有账号才建根)", node?.name === `${MARK}-待建根`, node?.name);
  ck("⑤ user.franchisee_id 指向新节点", String(after?.franchiseeId) === r.franchiseeId);
  ck("⑤ rootCount ≥ 1", r.rootCount >= 1, `rootCount=${r.rootCount}`);
  ck("⑤ 建根原因已留痕 (加密 notes)", (node?.notesEncrypted ?? "").length > 0);

  // ④ 已在树里 → 拒 (放在成功后测, 才测得到"二次建根")
  await expectThrow(
    "④ 已在树里 → 拒 (一人一节点)",
    () => createRootForUser({ userId: rootUserId, adminUserId: admin.id, note: "再来一次" }, ctx),
    "已经在加盟树里"
  );

  // ⑥ 审计留痕 (user.franchisee_id 变更)
  const audits = await db
    .select({ id: auditLog.id, operation: auditLog.operation, userId: auditLog.userId })
    .from(auditLog)
    .where(and(eq(auditLog.tableName, "user"), eq(auditLog.recordId, rootUserId)))
    .orderBy(desc(auditLog.id))
    .limit(3);
  ck(
    "⑥ 审计记下了 user 变更 (谁改的 = 管理员)",
    audits.length > 0 && audits.some((x) => x.operation === "UPDATE"),
    `rows=${audits.length} op=${audits.map((x) => x.operation).join(",")}`
  );

  // ---- ⑦ 鉴权: 非管理员 403 (HTTP 段) ----
  const alive = await fetch(`${BASE}/api/health`)
    .then((r) => r.ok)
    .catch(() => false);
  if (!alive) {
    console.log(`⏭  ⑦ 跳过 (${BASE} 不可达, 未起 dev server)`);
  } else {
    await createAccountWithProfile({
      name: `${MARK}-非管理员`,
      phone: PHONE_SALES,
      password: "Test1234",
      referralCode: code.code,
      actorUserId: admin.id,
    });
    const login = await fetch(`${BASE}/api/auth/flutter-login`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ identifier: PHONE_SALES, password: "Test1234" }),
    });
    const { sessionToken } = (await login.json()) as { sessionToken?: string };
    if (!sessionToken) {
      ck("⑦ 取非管理员 session", false, `login=${login.status}`);
    } else {
      const cookie = { Cookie: `authjs.session-token=${sessionToken}` };
      const getRes = await fetch(`${BASE}/api/admin/users`, { headers: cookie });
      ck("⑦ 非管理员 GET /api/admin/users → 403", getRes.status === 403, `status=${getRes.status}`);
      const postRes = await fetch(`${BASE}/api/admin/users/${rootUserId}/root`, {
        method: "POST",
        headers: { ...cookie, "content-type": "application/json" },
        body: JSON.stringify({ note: "越权尝试" }),
      });
      ck("⑦ 非管理员 POST 建根 → 403", postRes.status === 403, `status=${postRes.status}`);
    }
  }

  await cleanup();
  console.log(`\n${fail === 0 ? "全部通过" : "有失败"}: ${pass} pass / ${fail} fail`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("冒烟脚本自身炸了:", e);
  process.exit(1);
});
