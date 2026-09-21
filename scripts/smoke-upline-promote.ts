// ============================================
// 向上认领上级 (kind=promote) + 多根 (root_id) 冒烟 (dev only)
// 主人 2026-09-21 拍 B1/B2 + 同日补充三条
//
// 主人原话 (背景):
//   「在使用暖客宝 app 之前, 用户 (比如碧波庭公司的加盟系统) 公司系统已经存在固有的加盟体系
//     (节点树) 了 …… app 只是把现公司的加盟树同步到 app 中。当一个新的团队的初始用户
//     (admin 指定为加盟节点) 大概率只是公司加盟系统中的中间层 …… 原来的三方确认往上生长的
//     方案不变, 需要增加往根部发展用户的方案。」
// 主人原话 (补充拍板):
//   ①「『上层』= 点位父, 不一定是推荐码提供人」
//   ②「上层一旦有人不能撤换, 除非联系系统管理员协商处理」
//   ③「一个人已经在别的树里是节点, 可以被认领为我的上级, 前提是这个人的一层 2 个点位必需有空位」
//   ④「认领时『我在上级的 A线/B线』不在我的考虑范围, 由我的上级自己决定」
//
// 验这些不变量:
//   ① 只有**树根**能发起认领 (非根 → 拒)
//   ② 不能把自己认领成自己的上级
//   ③ 认领的上级若**已在同一棵树里** → 拒 (会成环)
//   ④ 认领的上级若是**没有账号**的历史节点 → 拒 (他本人点不了同意)
//   ⑤ 认领**别的树里**的节点 → **允许** (主人补充拍板 ③): 存 upline_fid, 不新建副本
//   ⑥ 双方确认: required = [initiator, new_franchisee] (app 里没有"上上层"那个人当老三方)
//   ⑦ **我在上级的哪条线由上级本人挑** (拍板 ④): 两条都空时不传 side → 拒; 传了才执行
//   ⑧ 执行 = **我这棵树挂到上级的空位**: 整树 path 加基路径 + depth 下移 + 改宗 root_id
//      (上级是新人 → 他成为新根; 上级已有 → 两棵树合并, 以他所在那棵为宗)
//   ⑨ 无账号上级 / 新建上级 两条路径都要走通
//   ⑩ 无关的第三棵树**没被动过**; 图谱查询不跨树; 管理员图谱无重复节点行
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

const PH_A = "13900008831"; // 主树根 A (会去认领)
const PH_B = "13900008832"; // 另一棵树的根 B (被认领 → 两棵树合并)
const PH_NEW = "13900008833"; // 不在 app 里的上级 (走"新建"路径)
const PH_O = "13900008834"; // 完全无关的第三棵树
const PH_FIX = "13900008835"; // A 的"假下线"节点 (无账号)
const PH_OCHILD = "13900008836"; // 第三棵树的子节点
const PH_NOACC = "13900008837"; // "无账号节点"用手机号 (挂在 A 自己的树里, 验 ⑧ 整树迁移)
const PH_NOACC2 = "13900008838"; // "无账号但已在 app 里有节点" (孤立根; 验 ④ 认领被拒)
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
  const fids = await db
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(inArray(franchisee.phoneHash, hashes));
  const fids2 = await db
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(eq(franchisee.name, `${MARK}-假下线`));
  const allFids = [...fids, ...fids2].map((f) => f.id);
  if (allFids.length > 0) {
    // 申请单/确认记录也要清 (否则残留单指向已删节点)
    const reqs = await db
      .select({ id: franchisePlacementRequest.id })
      .from(franchisePlacementRequest)
      .where(
        or(
          inArray(franchisePlacementRequest.initiatorFid, allFids),
          inArray(franchisePlacementRequest.targetParentFid, allFids),
          inArray(franchisePlacementRequest.uplineFid, allFids)
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
    await db.delete(franchisee).where(inArray(franchisee.id, allFids));
    await db
      .update(user)
      .set({ franchiseeId: null })
      .where(inArray(user.franchiseeId, allFids));
  }
  if (uids.length > 0) {
    await db.delete(auditLog).where(inArray(auditLog.userId, uids));
    await db.delete(user).where(inArray(user.id, uids));
  }
  await db.delete(customer).where(inArray(customer.phoneHash, hashes));
}

/** 造一个"没有账号"的加盟节点 (历史/脚本节点的样子) */
async function makeNoAccountNode(
  parentFid: bigint,
  rootFid: bigint,
  side: "left" | "right",
  basePath: string,
  baseDepth: number,
  adminId: bigint,
  phone = PH_NOACC
): Promise<bigint> {
  const [row] = await db
    .insert(franchisee)
    .values({
      name: `${MARK}-无账号节点`,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      referrerId: parentFid,
      placementSide: side,
      placementPath: basePath + (side === "left" ? "L." : "R."),
      placementDepth: baseDepth + 1,
      rootId: rootFid,
      isActive: true,
      createdBy: adminId,
    })
    .returning({ id: franchisee.id });
  return row.id;
}

/**
 * 造一个"没有账号的**孤立根**"节点 —— 模拟主人说的真实情形:
 *   公司加盟系统里早就存在这位上级, 但**他从没在暖客宝注册过** → app 里没账号。
 * (挂在 A 自己树里会先命中「同树 → 会成环」, 验不到 ④ 那条分支)
 */
async function makeNoAccountRoot(
  phone: string,
  adminId: bigint
): Promise<bigint> {
  const [row] = await db
    .insert(franchisee)
    .values({
      name: `${MARK}-无账号孤立根`,
      phoneEncrypted: encryptField(phone),
      phoneHash: hashForLookup(phone),
      referrerId: null,
      placementSide: null,
      placementPath: "",
      placementDepth: 0,
      rootId: null,
      isActive: true,
      createdBy: adminId,
    })
    .returning({ id: franchisee.id });
  await db.update(franchisee).set({ rootId: row.id }).where(eq(franchisee.id, row.id));
  return row.id;
}

const countNodes = (n: unknown): number =>
  n == null
    ? 0
    : 1 +
      ((n as { children: unknown[] }).children ?? []).reduce<number>(
        (acc, c) => acc + countNodes(c),
        0
      );

async function main() {
  await delByPhones([PH_A, PH_B, PH_NEW, PH_O, PH_FIX, PH_OCHILD]);
  await db.delete(franchisee).where(inArray(franchisee.phoneHash, [PH_NOACC, PH_NOACC2].map(hashForLookup)));

  const [code] = await db.select({ code: referralCode.code }).from(referralCode).limit(1);
  if (!code) throw new Error("库里没有推荐码, 先跑 seed");
  const [admin] = await db.select({ id: user.id }).from(user).where(eq(user.role, "admin")).limit(1);
  if (!admin) throw new Error("库里没有 admin, 先跑 pnpm db:ensure-admin");
  ctx.userId = admin.id;

  const mk = (name: string, phone: string) =>
    createAccountWithProfile({
      name, phone, password: "Test1234", referralCode: code.code, actorUserId: admin.id,
    });

  // ---- 准备 4 个账号 + 3 个根 ----
  const a = await mk(`${MARK}-A主树根`, PH_A);
  const b = await mk(`${MARK}-B另一棵树根`, PH_B);
  const o = await mk(`${MARK}-O无关第三棵`, PH_O);
  const aUid = BigInt(a.userId);
  const bUid = BigInt(b.userId);
  const oUid = BigInt(o.userId);

  const rootA = await createRootForUser({ userId: aUid, adminUserId: admin.id, note: "冒烟: A 在现实中是第 10 层" }, ctx);
  const rootB = await createRootForUser({ userId: bUid, adminUserId: admin.id, note: "冒烟: B 是另一棵树" }, ctx);
  const rootO = await createRootForUser({ userId: oUid, adminUserId: admin.id, note: "冒烟: O 无关" }, ctx);
  const fidA = BigInt(rootA.franchiseeId);
  const fidB = BigInt(rootB.franchiseeId);
  const fidO = BigInt(rootO.franchiseeId);

  // A 的假下线 (无账号) + A 的"无账号上级候选"
  const [fakeChild] = await db
    .insert(franchisee)
    .values({
      name: `${MARK}-假下线`,
      phoneEncrypted: encryptField(PH_FIX),
      phoneHash: hashForLookup(PH_FIX),
      referrerId: fidA, placementSide: "left", placementPath: "L.", placementDepth: 1,
      rootId: fidA, isActive: true, createdBy: admin.id,
    })
    .returning({ id: franchisee.id });
  const noAccId = await makeNoAccountNode(fidA, fidA, "right", "", 0, admin.id);
  // ④ 用: 没有账号的**孤立根** (在 A 的树之外, 所以不会先命中"同树 → 成环")
  const noAccRootId = await makeNoAccountRoot(PH_NOACC2, admin.id);

  // O 的无关子节点
  const [oChild] = await db
    .insert(franchisee)
    .values({
      name: `${MARK}-O子节点`,
      phoneEncrypted: encryptField(PH_OCHILD),
      phoneHash: hashForLookup(PH_OCHILD),
      referrerId: fidO, placementSide: "right", placementPath: "R.", placementDepth: 1,
      rootId: fidO, isActive: true, createdBy: admin.id,
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

  const claim = (over: Partial<Parameters<typeof createPlacementRequest>[0]> = {}) =>
    createPlacementRequest(
      {
        kind: "promote",
        initiatorFid: fidA,
        initiatorUserId: aUid,
        initiatorPhoneHash: hashForLookup(PH_A),
        targetParentFid: BigInt(0),
        targetSide: "left",
        ...over,
      } as Parameters<typeof createPlacementRequest>[0],
      ctx
    );

  const [aNode] = await db.select().from(franchisee).where(eq(franchisee.id, fidA)).limit(1);
  ck("前置: 建根后 root_id 自指", String(aNode?.rootId) === rootA.franchiseeId, `root_id=${aNode?.rootId}`);

  // ① 非根不能发起
  await expectThrow(
    "① 非根发起 → 拒",
    () => claim({ initiatorFid: fakeChild.id, initiatorUserId: aUid, newName: "谁的上级", newPhone: "13900007701" }),
    "只有树根才能向上认领"
  );
  // ② 不能认领自己
  await expectThrow(
    "② 认领自己 → 拒",
    () => claim({ newName: "自己", newPhone: PH_A }),
    "不能把自己认领为自己的上级"
  );
  // ③ 认领同一棵树里的节点 → 成环, 拒
  await expectThrow(
    "③ 认领同一棵树里的节点 → 拒 (会成环)",
    () => claim({ newName: "假下线", newPhone: PH_FIX }),
    "已经在您的加盟树里"
  );
  // ④ 认领「已在 app 里有节点, 但没有登录账号」的人 → 他本人点不了同意, 拒
  await expectThrow(
    "④ 认领无账号节点 (别棵树里) → 拒 (本人无法确认)",
    () => claim({ newName: "无账号孤立根", newPhone: PH_NOACC2 }),
    "还没有可登录的账号"
  );
  ck("④ 被拒后那个孤立根没被动过 (还是自己的根)",
    (await db.select().from(franchisee).where(eq(franchisee.id, noAccRootId)).limit(1))[0]?.rootId?.toString() === String(noAccRootId));

  // ⑤ 认领**别的树**的 B (主人补充拍板 ③) → 允许, 复用 B 的节点
  //    B 当前没有下线 → 两个点位都空
  const mergeReq = await claim({ newName: `${MARK}-B另一棵树根`, newPhone: PH_B, newNotes: "现实中她是我上级" });
  ck("⑤ 认领别的树的节点 → 成功发起", mergeReq.status === "pending", mergeReq.status);
  ck("⑤ 记下复用节点 (不新建副本)", mergeReq.uplineFid === rootB.franchiseeId, `uplineFid=${mergeReq.uplineFid}`);
  ck("⑤ 上级节点名字透出", mergeReq.uplineName === `${MARK}-B另一棵树根`, String(mergeReq.uplineName));
  ck(
    "⑤ 上级两个点位都空 → availableSides 两条",
    JSON.stringify(mergeReq.availableSides) === JSON.stringify(["left", "right"]),
    JSON.stringify(mergeReq.availableSides)
  );
  ck(
    "⑥ 必需确认方 = 双方 (发起人 + 上级本人)",
    JSON.stringify(mergeReq.required) === JSON.stringify(["initiator", "new_franchisee"]),
    JSON.stringify(mergeReq.required)
  );
  ck("⑥ requiredRoles 口径 = 父==发起人 → 双方",
    JSON.stringify(requiredRoles(fidA, fidA)) === JSON.stringify(["initiator", "new_franchisee"]));

  // ⑤b 同一个上级同时只能有 1 张 pending (发起人 A 换个上级试 → 走另一条, 这里用"重复认领"验)
  await expectThrow(
    "⑤b 同一个根重复认领 → 拒",
    () => claim({ newName: "另一个上级", newPhone: PH_NEW }),
    "已有一张待确认"
  );

  const A_ACTOR = { userId: aUid, fid: fidA, phoneHash: hashForLookup(PH_A) };
  const B_ACTOR = { userId: bUid, fid: fidB, phoneHash: hashForLookup(PH_B) };
  const reqId = BigInt(mergeReq.id);

  // ⑥ 发起人自己拍 → 还差上级
  const v1 = await decidePlacementRequest(reqId, A_ACTOR, "approve", ctx);
  ck("⑥ 发起人单独拍板 → 仍 pending", v1.status === "pending", v1.status);

  // ⑦ 上级两条线都空却没选线 → 拒 (「由上级自己决定」→ 必须他给)
  await expectThrow(
    "⑦ 上级不选线 → 拒 (要他自己决定)",
    () => decidePlacementRequest(reqId, B_ACTOR, "approve", ctx),
    "请选择这位下线放在您的"
  );

  // ⑦b 上级选 A线 → 执行 (两棵树合并)
  const v2 = await decidePlacementRequest(reqId, B_ACTOR, "approve", ctx, "left");
  ck("⑦b 上级选了 A线 → executed", v2.status === "executed", v2.status);
  ck("⑦b 单子记下上级选的线", v2.targetSide === "left", v2.targetSide);

  const [bAfter] = await db.select().from(franchisee).where(eq(franchisee.id, fidB)).limit(1);
  const [aAfter] = await db.select().from(franchisee).where(eq(franchisee.id, fidA)).limit(1);
  const [cAfter] = await db.select().from(franchisee).where(eq(franchisee.id, fakeChild.id)).limit(1);
  const [naAfter] = await db.select().from(franchisee).where(eq(franchisee.id, noAccId)).limit(1);

  ck("⑧ B 仍是根 (被复用的节点没被改)", bAfter?.placementPath === "" && String(bAfter?.rootId) === rootB.franchiseeId,
    `path=${JSON.stringify(bAfter?.placementPath)} root=${bAfter?.rootId}`);
  ck("⑧ A 挂到 B 的 A线: path='L.' depth=1", aAfter?.placementPath === "L." && aAfter?.placementDepth === 1,
    `p=${aAfter?.placementPath} d=${aAfter?.placementDepth}`);
  ck("⑧ A 的树改宗到 B 那棵 (root_id=B)", String(aAfter?.rootId) === rootB.franchiseeId, `root_id=${aAfter?.rootId}`);
  ck("⑧ A 的子孙跟着走: 'L.L.' depth=2", cAfter?.placementPath === "L.L." && cAfter?.placementDepth === 2,
    `p=${cAfter?.placementPath} d=${cAfter?.placementDepth}`);
  ck("⑧ A 的另一个子节点也在同一棵里", String(naAfter?.rootId) === rootB.franchiseeId && naAfter?.placementPath === "L.R.",
    `p=${naAfter?.placementPath} root=${naAfter?.rootId}`);
  ck("⑧ A 已经不再是树根 (不能再往上认领)", aAfter?.placementPath !== "", String(aAfter?.placementPath));

  // ⑩ 无关的第三棵树没被动过
  const [oAfter] = await db.select().from(franchisee).where(eq(franchisee.id, fidO)).limit(1);
  const [ocAfter] = await db.select().from(franchisee).where(eq(franchisee.id, oChild.id)).limit(1);
  ck("⑩ 无关的第三棵树没被动过",
    oAfter?.placementPath === "" && String(oAfter?.rootId) === String(fidO) &&
      ocAfter?.placementPath === "R." && String(ocAfter?.rootId) === String(fidO),
    `O.root=${oAfter?.rootId} OC.root=${ocAfter?.rootId}`);

  // ⑩ 图谱查询不跨树: B 那棵 = B + A + 假下线 + 无账号节点 = 4; O 那棵 = 2
  const treeB = await getPlacementTree(fidB, 9);
  const treeO = await getPlacementTree(fidO, 9);
  ck("⑩ 合并后 B 那棵树 = 4 节点 (两棵树真的并成一棵)", countNodes(treeB) === 4, `n=${countNodes(treeB)}`);
  ck("⑩ 无关的 O 那棵 = 2 节点 (没被吞并)", countNodes(treeO) === 2, `n=${countNodes(treeO)}`);

  // ⑩ 管理员图谱: 无重复 + 父子按同树 path 推导
  const nodes = await listAdminNodes();
  const fids = nodes.map((n) => n.fid);
  ck("⑩ 管理员图谱无重复节点行", new Set(fids).size === fids.length, `${fids.length} 行 / ${new Set(fids).size} 唯一`);
  ck("⑩ 图谱: A 的父 = B", nodes.find((n) => n.fid === String(fidA))?.parentFid === String(fidB));
  ck("⑩ 图谱: 无账号节点父 = A", nodes.find((n) => n.fid === String(noAccId))?.parentFid === String(fidA));
  ck("⑩ 图谱: B 无父 (是一棵树的根)", nodes.find((n) => n.fid === String(fidB))?.parentFid == null);

  // ⑨ 走一遍「上级不在 app 里」的新建路径 (换个新账号当被认领人):
  //    先把 A 复位成根 (直接改库, 这是冒烟脚本的造数自由)
  await db.execute(
    `UPDATE franchisee SET placement_path = substring(placement_path from 3),
       placement_depth = placement_depth - 1, root_id = ${fidA}, updated_at = NOW()
     WHERE root_id = ${fidB} AND id <> ${fidB}` as never
  );
  await db.update(franchisee).set({ rootId: fidA, placementSide: null }).where(eq(franchisee.id, fidA));

  const newReq = await claim({ newName: `${MARK}-新人上级`, newPhone: PH_NEW, newNotes: "app 里还没有她" });
  ck("⑨ 认领 app 里没有的人 → uplineFid 为空 (走新建)", newReq.uplineFid == null, String(newReq.uplineFid));
  ck("⑨ 新人上级两条线都空", JSON.stringify(newReq.availableSides) === JSON.stringify(["left", "right"]),
    JSON.stringify(newReq.availableSides));

  const newUid = (await mk(`${MARK}-新人上级`, PH_NEW)).userId;
  const NEW_ACTOR = { userId: BigInt(newUid), fid: null, phoneHash: hashForLookup(PH_NEW) };
  await decidePlacementRequest(BigInt(newReq.id), A_ACTOR, "approve", ctx);
  const vNew = await decidePlacementRequest(BigInt(newReq.id), NEW_ACTOR, "approve", ctx, "right");
  ck("⑨ 新建路径 executed", vNew.status === "executed", vNew.status);
  const newRootId = BigInt(vNew.resultFid ?? "0");
  const [nr] = await db.select().from(franchisee).where(eq(franchisee.id, newRootId)).limit(1);
  const [ar] = await db.select().from(franchisee).where(eq(franchisee.id, fidA)).limit(1);
  ck("⑨ 新人成为新根 (path='' depth=0 root_id 自指)",
    nr?.placementPath === "" && nr?.placementDepth === 0 && String(nr?.rootId) === String(newRootId),
    `p=${JSON.stringify(nr?.placementPath)} d=${nr?.placementDepth} root=${nr?.rootId}`);
  ck("⑨ A 降到 B线 (上级自己挑的): path='R.' depth=1", ar?.placementPath === "R." && ar?.placementDepth === 1,
    `p=${ar?.placementPath} d=${ar?.placementDepth}`);

  await delByPhones([PH_A, PH_B, PH_NEW, PH_O, PH_FIX, PH_OCHILD]);
  await db.delete(franchisee).where(inArray(franchisee.phoneHash, [PH_NOACC, PH_NOACC2].map(hashForLookup)));
  await db.delete(customer).where(inArray(customer.phoneHash, [PH_OCHILD, PH_NOACC, PH_NOACC2].map(hashForLookup)));

  console.log(`\n${fail === 0 ? "✅ 全部通过" : "❌ 有失败"}: ${pass} 通过 / ${fail} 失败`);
  process.exit(fail === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error("💥", e);
  process.exit(1);
});
