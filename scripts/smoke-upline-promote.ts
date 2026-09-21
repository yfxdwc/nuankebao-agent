// ============================================
// 向上认领上级 (kind=promote) + 多根 (root_id) 冒烟 (dev only)
// 主人 2026-09-21 拍 B1/B2
//
// 背景 (主人原话):
//   「在使用暖客宝 app 之前, 用户 (比如碧波庭公司的加盟系统) 公司系统已经存在固有的加盟体系
//     (节点树) 了 …… app 只是把现公司的加盟树同步到 app 中。当一个新的团队的初始用户
//     (admin 指定为加盟节点) 大概率只是公司加盟系统中的中间层 …… 原来的三方确认往上生长的
//     方案不变, 需要增加往根部发展用户的方案。」
//
// 验这些不变量:
//   ① 只有**树根**能发起认领 (非根 → 拒)
//   ② 不能把自己认领成自己的上级
//   ③ 上级手机号若已是加盟商 → 拒 (不能把树上已有的节点复制一份)
//   ④ 成功发起: required = [initiator, new_franchisee] —— **双方** (不是三方, 与"父==设置者"同构)
//   ⑤ 同一根不能有两张 pending 认领单
//   ⑥ 执行后: 新根 path='' depth=0 root_id=自己; 原根 path='L.'/'R.' depth=1 root_id=新根;
//      原根的子孙 path 整体加前缀 + depth+1 + root_id 迁到新根 (结构完整, 节点数 +1)
//   ⑦ 多根不串味: 另一棵树**没被动过** (root_id / path 不变), 且图谱查询不跨树
//
// 跑: npx tsx scripts/smoke-upline-promote.ts   (幂等, 跑完自己清理)
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { and, eq, inArray, or } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  auditLog,
  customer,
  franchisee,
  franchisePlacementConfirm,
  franchisePlacementRequest,
  referralCode,
  user,
} from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import { createAccountWithProfile } from "@/lib/auth/registration";
import { createRootForUser, listAdminNodes } from "@/lib/db/queries/admin-users";
import {
  createPlacementRequest,
  decidePlacementRequest,
  requiredRoles,
} from "@/lib/db/queries/franchisee-placement";
import { getPlacementTree } from "@/lib/db/queries/franchisee";

const PH_ROOT = "13900008831";
const PH_UP = "13900008832";
const PH_OTHER = "13900008833";
const PH_FIX = "13900008834"; // 假造的"无账号下线"节点用手机号
const PH_OCHILD = "13900008899"; // 另一棵树的子节点 (验证 promote 不越界)
const MARK = "冒烟-向上认领";

let pass = 0;
let fail = 0;
const ck = (name: string, ok: boolean, extra = "") => {
  console.log(`${ok ? "✅" : "❌"} ${name}${extra ? ` — ${extra}` : ""}`);
  ok ? pass++ : fail++;
};

const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };

async function delByPhones(phones: string[]) {
  const hashes = phones.map(hashForLookup);
  const rows = await db
    .select({ id: user.id, fid: user.franchiseeId })
    .from(user)
    .where(inArray(user.phoneHash, hashes));
  const uids = rows.map((r) => r.id);
  if (uids.length > 0) {
    await db.delete(auditLog).where(inArray(auditLog.userId, uids));
    await db.delete(user).where(inArray(user.id, uids));
  }
  const fids = await db
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(inArray(franchisee.phoneHash, hashes));
  // 申请单/确认记录也要清 (否则残留 pending/executed 单指向已删节点)
  if (fids.length > 0) {
    const ids = fids.map((f) => f.id);
    const reqs = await db
      .select({ id: franchisePlacementRequest.id })
      .from(franchisePlacementRequest)
      .where(
        or(
          inArray(franchisePlacementRequest.initiatorFid, ids),
          inArray(franchisePlacementRequest.targetParentFid, ids),
        )
      );
    if (reqs.length > 0) {
      const rids = reqs.map((r) => r.id);
      await db
        .delete(franchisePlacementConfirm)
        .where(inArray(franchisePlacementConfirm.requestId, rids));
      await db
        .delete(franchisePlacementRequest)
        .where(inArray(franchisePlacementRequest.id, rids));
    }
  }
  if (fids.length > 0) {
    await db.delete(franchisee).where(inArray(franchisee.id, fids.map((f) => f.id)));
    await db
      .update(user)
      .set({ franchiseeId: null })
      .where(inArray(user.franchiseeId, fids.map((f) => f.id)));
  }
  await db.delete(customer).where(inArray(customer.phoneHash, hashes));
  // 兜底: name 标记的残留 (上一轮跑挂)
  const leftovers = await db
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(eq(franchisee.name, `${MARK}-假下线`));
  if (leftovers.length > 0) {
    await db.delete(franchisee).where(inArray(franchisee.id, leftovers.map((l) => l.id)));
  }
}

async function main() {
  await delByPhones([PH_ROOT, PH_UP, PH_OTHER, PH_FIX, PH_OCHILD]);

  const [code] = await db.select({ code: referralCode.code }).from(referralCode).limit(1);
  if (!code) throw new Error("库里没有推荐码, 先跑 seed");
  const [admin] = await db.select({ id: user.id }).from(user).where(eq(user.role, "admin")).limit(1);
  if (!admin) throw new Error("库里没有 admin, 先跑 pnpm db:ensure-admin");
  ctx.userId = admin.id;

  const mk = (name: string, phone: string) =>
    createAccountWithProfile({
      name,
      phone,
      password: "Test1234",
      referralCode: code.code,
      actorUserId: admin.id,
    });

  // ---- 准备: 账号 A (将来当根), 账号 U (现实里的上级, 还没加盟), 账号 O (另一棵树) ----
  const a = await mk(`${MARK}-A根`, PH_ROOT);
  const up = await mk(`${MARK}-U上级`, PH_UP);
  const other = await mk(`${MARK}-O另一棵树`, PH_OTHER);
  const aUid = BigInt(a.userId);
  const upUid = BigInt(up.userId);
  const otherUid = BigInt(other.userId);

  const rootA = await createRootForUser({ userId: aUid, adminUserId: admin.id, note: "冒烟: A 在现实中是第 10 层" }, ctx);
  const fidA = BigInt(rootA.franchiseeId);
  const rootO = await createRootForUser({ userId: otherUid, adminUserId: admin.id, note: "冒烟: 另一棵独立的树" }, ctx);
  const fidO = BigInt(rootO.franchiseeId);

  // 给 A 造一个"假下线"节点 (无账号), 用来验证子树整体下降
  const [fakeChild] = await db
    .insert(franchisee)
    .values({
      name: `${MARK}-假下线`,
      phoneEncrypted: encryptField(PH_FIX),
      phoneHash: hashForLookup(PH_FIX),
      referrerId: fidA,
      placementSide: "left",
      placementPath: "L.",
      placementDepth: 1,
      rootId: fidA,
      isActive: true,
      createdBy: admin.id,
    })
    .returning({ id: franchisee.id });

  // 给 O 也造一个子节点 → 验证 promote 不碰别的树
  const [oChild] = await db
    .insert(franchisee)
    .values({
      name: `${MARK}-O树子节点`,
      phoneEncrypted: encryptField(PH_OCHILD),
      phoneHash: hashForLookup(PH_OCHILD),
      referrerId: fidO,
      placementSide: "right",
      placementPath: "R.",
      placementDepth: 1,
      rootId: fidO,
      isActive: true,
      createdBy: admin.id,
    })
    .returning({ id: franchisee.id });

  const expectThrow = async (label: string, fn: () => Promise<unknown>, needle: string) => {
    try {
      await fn();
      ck(label, false, "居然成功了");
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      ck(label, msg.includes(needle), msg);
    }
  };

  const [aNode] = await db.select().from(franchisee).where(eq(franchisee.id, fidA)).limit(1);
  ck("前置: 建根后 root_id 自指", String(aNode?.rootId) === rootA.franchiseeId, `root_id=${aNode?.rootId}`);
  ck("前置: root_user 指向 root_id = 自己", String(aNode?.rootId) === String(aNode?.id));

  // ① 非根不能发起
  await expectThrow(
    "① 非根发起 → 拒",
    () =>
      createPlacementRequest(
        {
          kind: "promote",
          initiatorFid: fakeChild.id,
          initiatorUserId: aUid,
          initiatorPhoneHash: hashForLookup(PH_FIX),
          targetParentFid: BigInt(0),
          targetSide: "left",
          newName: `${MARK}-谁的上级`,
          newPhone: "13900008888",
        },
        ctx
      ),
    "只有树根才能向上认领"
  );

  // ② 不能认领自己
  await expectThrow(
    "② 认领自己 → 拒",
    () =>
      createPlacementRequest(
        {
          kind: "promote",
          initiatorFid: fidA,
          initiatorUserId: aUid,
          initiatorPhoneHash: hashForLookup(PH_ROOT),
          targetParentFid: BigInt(0),
          targetSide: "left",
          newName: `${MARK}-A根`,
          newPhone: PH_ROOT,
        },
        ctx
      ),
    "不能把自己认领为自己的上级"
  );

  // ③ 已经是加盟商 → 拒
  await expectThrow(
    "③ 上级已在树里 → 拒",
    () =>
      createPlacementRequest(
        {
          kind: "promote",
          initiatorFid: fidA,
          initiatorUserId: aUid,
          initiatorPhoneHash: hashForLookup(PH_ROOT),
          targetParentFid: BigInt(0),
          targetSide: "left",
          newName: "另一个根",
          newPhone: PH_OTHER,
        },
        ctx
      ),
    "该手机号已经是加盟商了"
  );

  // ④ 成功发起 (双方确认)
  const req = await createPlacementRequest(
    {
      kind: "promote",
      initiatorFid: fidA,
      initiatorUserId: aUid,
      initiatorPhoneHash: hashForLookup(PH_ROOT),
      targetParentFid: BigInt(0),
      targetSide: "left",
      newName: `${MARK}-U上级`,
      newPhone: PH_UP,
      newNotes: "现实中她是我的直接上级 (第 9 层)",
    },
    ctx
  );
  ck(
    "④ 认领单必需确认方 = 双方 (发起人 + 上级本人)",
    JSON.stringify(req.required) === JSON.stringify(["initiator", "new_franchisee"]),
    JSON.stringify(req.required)
  );
  ck("④ 单子 status=pending", req.status === "pending", req.status);
  ck(
    "④ requiredRoles 口径 = 父==发起人 → 双方",
    JSON.stringify(requiredRoles(fidA, fidA)) === JSON.stringify(["initiator", "new_franchisee"])
  );

  // ⑤ 同一根不能有两张 pending
  await expectThrow(
    "⑤ 重复认领 → 拒",
    () =>
      createPlacementRequest(
        {
          kind: "promote",
          initiatorFid: fidA,
          initiatorUserId: aUid,
          initiatorPhoneHash: hashForLookup(PH_ROOT),
          targetParentFid: BigInt(0),
          targetSide: "right",
          newName: `${MARK}-另一个上级`,
          newPhone: "13900008877",
        },
        ctx
      ),
    "已有一张待确认"
  );

  // 发起人自己拍 → 还差 U
  const v1 = await decidePlacementRequest(
    BigInt(req.id),
    { userId: aUid, fid: fidA, phoneHash: hashForLookup(PH_ROOT) },
    "approve",
    ctx
  );
  ck("⑥ 发起人单独拍板 → 仍是 pending (还缺上级本人)", v1.status === "pending", v1.status);

  // U 拍板 → 执行
  const v2 = await decidePlacementRequest(
    BigInt(req.id),
    { userId: upUid, fid: null, phoneHash: hashForLookup(PH_UP) },
    "approve",
    ctx
  );
  ck("⑥ 上级本人拍板 → executed", v2.status === "executed", v2.status);

  const uplineId = BigInt(v2.resultFid ?? "0");
  const [uNode] = await db.select().from(franchisee).where(eq(franchisee.id, uplineId)).limit(1);
  const [a2] = await db.select().from(franchisee).where(eq(franchisee.id, fidA)).limit(1);
  const [c2] = await db.select().from(franchisee).where(eq(franchisee.id, fakeChild.id)).limit(1);
  const [upUser] = await db.select({ fid: user.franchiseeId }).from(user).where(eq(user.id, upUid)).limit(1);

  ck("⑥ 新根 path=''", uNode?.placementPath === "", JSON.stringify(uNode?.placementPath));
  ck("⑥ 新根 depth=0", uNode?.placementDepth === 0, String(uNode?.placementDepth));
  ck("⑥ 新根 root_id 自指", String(uNode?.rootId) === String(uplineId), `root_id=${uNode?.rootId}`);
  ck("⑥ 原根降到 depth=1 / path='L.'", a2?.placementDepth === 1 && a2?.placementPath === "L.", `d=${a2?.placementDepth} p=${a2?.placementPath}`);
  ck("⑥ 原根 root_id 迁到新根", String(a2?.rootId) === String(uplineId), `root_id=${a2?.rootId}`);
  ck("⑥ 子孙整体下降: path='L.L.' depth=2", c2?.placementPath === "L.L." && c2?.placementDepth === 2, `p=${c2?.placementPath} d=${c2?.placementDepth}`);
  ck("⑥ 子孙 root_id 也迁到新根", String(c2?.rootId) === String(uplineId), `root_id=${c2?.rootId}`);
  ck("⑥ 上级账号已绑定节点 (能登录自己那棵树)", String(upUser?.fid ?? "") === String(uplineId));

  // ⑦ 多根不串味: 另一棵树没被动过
  const [oAfter] = await db.select().from(franchisee).where(eq(franchisee.id, fidO)).limit(1);
  const [ocAfter] = await db.select().from(franchisee).where(eq(franchisee.id, oChild.id)).limit(1);
  ck(
    "⑦ 另一棵树没被动过",
    oAfter?.placementPath === "" &&
      String(oAfter?.rootId) === String(fidO) &&
      ocAfter?.placementPath === "R." &&
      String(ocAfter?.rootId) === String(fidO),
    `O.path=${JSON.stringify(oAfter?.placementPath)} O.root=${oAfter?.rootId} OC.path=${ocAfter?.placementPath}`
  );

  // ⑦ 图谱查询不跨树: U 那棵 = U + A + 假下线; O 那棵 = O + 子节点
  const treeU = await getPlacementTree(uplineId, 9);
  const treeO = await getPlacementTree(fidO, 9);
  const count = (n: { children: unknown[] } | null): number =>
    n == null ? 0 : 1 + (n.children as { children: unknown[] }[]).reduce((acc, c) => acc + count(c), 0);
  ck("⑦ 新根这棵树 = 3 个节点 (U + A + 假下线)", count(treeU as never) === 3, `n=${count(treeU as never)}`);
  ck("⑦ 另一棵树 = 2 个节点 (没被 promote 吞并)", count(treeO as never) === 2, `n=${count(treeO as never)}`);

  // ⑦ 管理员图谱: 节点不重复 + 父子按同树 path 推导
  const nodes = await listAdminNodes();
  const fids = nodes.map((n) => n.fid);
  ck("⑦ 管理员图谱无重复节点行", new Set(fids).size === fids.length, `${fids.length} 行 / ${new Set(fids).size} 唯一`);
  const aRow = nodes.find((n) => n.fid === String(fidA));
  const uRow = nodes.find((n) => n.fid === String(uplineId));
  const cRow = nodes.find((n) => n.fid === String(fakeChild.id));
  ck("⑦ 图谱: A 的父 = 新根 U", aRow?.parentFid === String(uplineId), `parent=${aRow?.parentFid}`);
  ck("⑦ 图谱: 新根 U 无父 (是一棵树的根)", uRow?.parentFid == null, `parent=${uRow?.parentFid}`);
  ck("⑦ 图谱: 假下线的父 = A", cRow?.parentFid === String(fidA), `parent=${cRow?.parentFid}`);

  await delByPhones([PH_ROOT, PH_UP, PH_OTHER, PH_FIX, PH_OCHILD]);

  console.log(`\n${fail === 0 ? "✅ 全部通过" : "❌ 有失败"}: ${pass} 通过 / ${fail} 失败`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("💥", e);
  process.exit(1);
});
