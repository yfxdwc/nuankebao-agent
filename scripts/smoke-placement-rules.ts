// ============================================
// 加盟设置「谁可以设置」规则冒烟 (dev only) — 主人 2026-09-19 拍
//
// 规则: ① 只有「已加盟用户」或「系统管理员」能设置加盟
//       ② 系统管理员设置加盟**不需要多方确认** (直接落位)
//       ③ 用户不能给自己设置成加盟用户
//       ④ **节点 ⇒ 账号** (主人 2026-09-21 拍: 「要成为节点首先必需有账号」)
//          → 给一个没注册过的人落位 = 拒 (事务回滚, 不留下无账号节点)
//
// 跑: npx tsx scripts/smoke-placement-rules.ts
// 幂等: 用手机号 13900006666, 跑完自己清理
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { and, eq, or, isNull as isNullF } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  franchisee,
  customer,
  franchisePlacementRequest,
  franchisePlacementConfirm,
  referralCode,
  user,
} from "@/lib/db/schema";
import { hashForLookup } from "@/lib/crypto/field";
import { createPlacementRequest } from "@/lib/db/queries/franchisee-placement";
import { createAccountWithProfile } from "@/lib/auth/registration";

const ROOT_FID = BigInt(process.env.ROOT_FID ?? "75");
const NEW_PHONE = "13900006666";
const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };
let pass = 0;
let fail = 0;
const check = (name: string, ok: boolean, extra = "") => {
  console.log(`${ok ? "✅" : "❌"} ${name}${extra ? ` — ${extra}` : ""}`);
  ok ? pass++ : fail++;
};

/** 找一个「左位空闲」的浅层节点当目标父节点 (path 格式: L.L.R.) */
async function pickParent(): Promise<{ id: bigint; side: "left" | "right"; path: string }> {
  const rows = await db
    .select({ id: franchisee.id, path: franchisee.placementPath })
    .from(franchisee)
    .where(isNullF(franchisee.deletedAt));
  const paths = new Map(rows.map((r) => [r.path ?? "", r.id]));
  const byDepth = [...rows].sort(
    (a, b) => (a.path ?? "").length - (b.path ?? "").length
  );
  for (const node of byDepth) {
    const p = node.path ?? "";
    const hasLeft = paths.has(`${p}L.`);
    const hasRight = paths.has(`${p}R.`);
    if (!hasLeft) return { id: node.id, side: "left", path: p };
    if (!hasRight) return { id: node.id, side: "right", path: p };
  }
  throw new Error("没有空闲点位可选");
}

async function cleanup() {
  const hash = hashForLookup(NEW_PHONE);
  const created = await db
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(eq(franchisee.phoneHash, hash));
  // 先删「申请单 + 确认记录」再软删加盟商 (确认记录只挂在单子上)
  const reqs = await db
    .select({ id: franchisePlacementRequest.id })
    .from(franchisePlacementRequest)
    .where(
      or(
        eq(franchisePlacementRequest.newPhoneHash, hash),
        eq(franchisePlacementRequest.newName, "规则冒烟-测试")
      )
    );
  for (const r of reqs) {
    await db
      .delete(franchisePlacementConfirm)
      .where(eq(franchisePlacementConfirm.requestId, r.id));
  }
  await db
    .delete(franchisePlacementRequest)
    .where(
      or(
        eq(franchisePlacementRequest.newPhoneHash, hash),
        eq(franchisePlacementRequest.newName, "规则冒烟-测试")
      )
    );
  // 客户档案与加盟商靠 phone_hash 关联 (无 FK) → 按 hash 清
  await db.delete(customer).where(eq(customer.phoneHash, hash));
  for (const f of created) {
    await db.delete(franchisee).where(eq(franchisee.id, f.id));
  }
  // ④ 之后会真建一个账号 → 一并清干净 (否则下一轮撞"该手机号已有账号")
  const users = await db
    .select({ id: user.id })
    .from(user)
    .where(eq(user.phoneHash, hash));
  for (const u of users) {
    await db.delete(referralCode).where(eq(referralCode.userId, u.id));
    await db.delete(user).where(eq(user.id, u.id));
  }
}

(async () => {
  await cleanup();
  const target = await pickParent();
  console.log(`目标父节点: id=${target.id} path="${target.path}" side=${target.side}`);
  const base = {
    kind: "create" as const,
    initiatorUserId: BigInt(1),
    targetParentFid: target.id,
    targetSide: target.side,
    newName: "规则冒烟-测试",
    newPhone: NEW_PHONE,
  };

  // ③ 自我加盟: 发起人自己的手机号 == 新加盟商手机号 → 拒绝
  try {
    await createPlacementRequest(
      {
        ...base,
        initiatorFid: ROOT_FID,
        initiatorPhoneHash: hashForLookup("13800138000"),
        newPhone: "13800138000", // ← 就是发起人自己的号
      },
      ctx
    );
    check("③ 自己给自己设置加盟 → 应该被拒", false, "居然成功了");
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    check("③ 自己给自己设置加盟 → 被拒", msg.includes("不能给自己设置加盟"), msg);
  }

  // ① 非加盟商且非管理员 → 拒绝
  try {
    await createPlacementRequest(
      { ...base, initiatorFid: null, initiatorIsAdmin: false },
      ctx
    );
    check("① 非加盟/非管理员发起 → 应该被拒", false, "居然成功了");
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    check(
      "① 非加盟/非管理员发起 → 被拒",
      msg.includes("只有已加盟用户或系统管理员"),
      msg
    );
  }

  // ④ 节点 ⇒ 账号: 这位还没注册 → 管理员也不能凭空给她造节点 (事务回滚)
  try {
    await createPlacementRequest(
      {
        ...base,
        initiatorFid: ROOT_FID,
        initiatorIsAdmin: true,
        initiatorPhoneHash: hashForLookup("13800138000"),
      },
      ctx
    );
    check("④ 给未注册的人落位 → 应该被拒", false, "居然成功了");
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    check(
      "④ 给未注册的人落位 → 被拒 (节点必须对应账号)",
      msg.includes("节点必须对应一个账号"),
      msg
    );
  }
  // ④ 之后: 建号 (走正规建号入口) → 再落位就通了
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
  await createAccountWithProfile({
    name: "规则冒烟-测试",
    phone: NEW_PHONE,
    password: "Test1234",
    referralCode: code.code,
    actorUserId: admin.id,
  });
  // 落位残留兜底: ④ 被拒后应该什么都没留下
  const [leftover] = await db
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(eq(franchisee.phoneHash, hashForLookup(NEW_PHONE)))
    .limit(1);
  check("④ 被拒后没留下无账号节点 (事务回滚)", leftover == null, `残留 fid=${leftover?.id}`);

  // ② 管理员发起 → 免多方确认, 直接 executed
  const view = await createPlacementRequest(
    {
      ...base,
      initiatorFid: ROOT_FID,
      initiatorIsAdmin: true,
      initiatorPhoneHash: hashForLookup("13800138000"),
    },
    ctx
  );
  check("② 管理员设置 → 单子直接 executed", view.status === "executed", `status=${view.status}`);
  check(
    "② 管理员确认记录 → verifiedBy=admin",
    (view.confirms ?? []).some((c: { verifiedBy: string }) => c.verifiedBy === "admin"),
    JSON.stringify((view.confirms ?? []).map((c: { verifiedBy: string }) => c.verifiedBy))
  );
  // 落位结果: 新加盟商记录已建 + path 正确
  const [placed] = await db
    .select({
      name: franchisee.name,
      side: franchisee.placementSide,
      path: franchisee.placementPath,
      depth: franchisee.placementDepth,
    })
    .from(franchisee)
    .where(eq(franchisee.phoneHash, hashForLookup(NEW_PHONE)))
    .limit(1);
  const wantPath = `${target.path}${target.side === "left" ? "L." : "R."}`;
  check(
    "② 管理员设置 → 加盟商已建, path = 目标父 + 侧",
    placed?.path === wantPath,
    `path=${placed?.path} 期望=${wantPath}`
  );
  check(
    "② 管理员设置 → side 正确",
    placed?.side === target.side,
    `side=${placed?.side}`
  );

  await cleanup();
  console.log(`\n${fail === 0 ? "🎉 全过" : "⚠️ 有失败"} — pass=${pass} fail=${fail}`);
  process.exit(fail === 0 ? 0 : 1);
})().catch((e) => {
  console.log("💥 未捕获:", (e as Error).message);
  console.log("异常 SQL:", (e as { query?: string }).query ?? "(无)");
  process.exit(1);
});
