// ============================================
// 管理员「协商处理后强改上层」(reparent) 冒烟 (dev only) — 主人 2026-09-21 拍
//
// 主人原话:
//   ①「无账号节点为什么要存在? 不能禁止/消除无账号节点吗, 要成为节点首先必需有账号。」
//   ②「「上层」= 点位父, 不一定是推荐码提供人。上层一旦有人不能撤换, 除非联系系统管理员协商处理。」
//   ③「给管理员一个『协商处理后强改上层』的后台功能」
//
// 验这些不变量:
//   ① 原因不填 / 太短 → 拒 (这条通道是"协商处理", 没原因将来查不清)
//   ② 节点或新上层不存在 → 拒
//   ③ 新上层 = 她自己 → 拒
//   ④ 新上层在她自己的下线里 → 拒 (成环, 树会断)
//   ⑤ 新上层那条线已经有人 → 拒
//   ⑥ 本来就在那个位置 → 拒 (幂等, 不写假审计)
//   ⑦ 任一方**没有账号** → 拒 (节点 ⇒ 账号 不变量)
//   ⑫ **推荐人 (referrer_id) 与点位父 (placement_parent_id) 分家** (主人 2026-09-21 拍"拆"):
//      - 落位时推荐人那侧满了 → BFS 顺延到别人名下 → 两栏**本来就该不同**
//      - 管理员强改上层只动点位父, **绝不改写"谁推荐了她"** (referrerTouched=false)
//   ⑧ 成功 (非根换上层): 她 + 她的**整棵子树** path/depth/root_id 一起改;
//      原来的线**空出来**; placement_parent_id/placement_side 指向新上层, **referrer_id 不动**
//   ⑨ 成功 (树根挂到别的树): 两棵树合并 — 整棵树 path 加基路径 + depth 下移 + 改宗;
//      树数量 -1; **无关的第三棵树一点没动**; 图谱查询无重复节点行
//   ⑩ 留痕: 备注追加一行 (可读) + audit_log 里 recorded 这次 change
//   ⑪ 鉴权 (HTTP 段, 需 dev server): 非管理员打该接口 = 403
//
// 跑: npx tsx scripts/smoke-admin-reparent.ts   (幂等, 跑完自己清理)
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { and, eq, inArray } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  auditLog,
  customer,
  franchisee,
  referralCode,
  user,
} from "@/lib/db/schema";
import { decryptField, encryptField, hashForLookup } from "@/lib/crypto/field";
import { createAccountWithProfile } from "@/lib/auth/registration";
import { createRootForUser, listAdminNodes } from "@/lib/db/queries/admin-users";
import { adminReparentNode } from "@/lib/db/queries/franchisee-reparent";
import { createFranchisee, getPlacementTree } from "@/lib/db/queries/franchisee";

const BASE = process.env.SMOKE_BASE_URL ?? "http://127.0.0.1:3003";
const MARK = "冒烟-强改上层";

// 账号手机号 (1 个管理员 + 树 A 系 + 树 B 系 + 无关树 O + 越权用)
const P = {
  A: "13900009901",
  A1: "13900009902",
  A2: "13900009903",
  A1a: "13900009904",
  A1b: "13900009905",
  A1a1: "13900009906",
  A1b1: "13900009907",
  A2a: "13900009908",
  B: "13900009909",
  B1: "13900009910",
  O: "13900009911",
  O1: "13900009912",
  SALES: "13900009913",
  /** 无账号的孤儿节点 (挂在 A 树里, 验 ⑦) */
  ORPH: "13900009914",
  /** 无账号的孤儿节点 (树 B 的右子位, 验 ⑦ 新上层) */
  ORPH2: "13900009915",
  /** 拆栏验证用: 推荐人那侧满了 → BFS 顺延到别人名下 (验 ⑫) */
  FB: "13900009916",
} as const;
const ALL_PHONES = Object.values(P);

let pass = 0;
let fail = 0;
const ck = (name: string, ok: boolean, extra = "") => {
  console.log(`${ok ? "✅" : "❌"} ${name}${extra ? ` — ${extra}` : ""}`);
  ok ? pass++ : fail++;
};

async function cleanup() {
  const hashes = ALL_PHONES.map(hashForLookup);
  const rows = await db
    .select({ id: user.id })
    .from(user)
    .where(inArray(user.phoneHash, hashes));
  const fids = await db
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(inArray(franchisee.phoneHash, hashes));
  const fidIds = fids.map((f) => f.id);
  if (fidIds.length > 0) {
    await db
      .update(user)
      .set({ franchiseeId: null })
      .where(inArray(user.franchiseeId, fidIds));
    await db.delete(franchisee).where(inArray(franchisee.id, fidIds));
  }
  // 兜底: 上一轮跑挂留下的孤儿节点
  await db.delete(franchisee).where(eq(franchisee.name, `${MARK}-无账号节点`));
  if (rows.length > 0) {
    await db.delete(auditLog).where(inArray(auditLog.userId, rows.map((r) => r.id)));
  }
  await db.delete(user).where(inArray(user.phoneHash, hashes));
  await db.delete(customer).where(inArray(customer.phoneHash, hashes));
}

async function main() {
  await cleanup();

  const [code] = await db.select({ code: referralCode.code }).from(referralCode).limit(1);
  if (!code) throw new Error("库里没有推荐码, 先跑 seed");
  const [admin] = await db.select({ id: user.id }).from(user).where(eq(user.role, "admin")).limit(1);
  if (!admin) throw new Error("库里没有 admin, 先跑 pnpm db:ensure-admin");
  const ctx = { userId: admin.id, ipAddress: "127.0.0.1" };

  // ---- 造账号 ----
  const account = async (name: string, phone: string) =>
    BigInt(
      (
        await createAccountWithProfile({
          name: `${MARK}-${name}`,
          phone,
          password: "Test1234",
          referralCode: code.code,
          actorUserId: admin.id,
        })
      ).userId
    );

  const uidA = await account("A主树根", P.A);
  const uidB = await account("B另一棵树根", P.B);
  const uidO = await account("O无关第三棵", P.O);
  const uid = {
    A1: await account("A1", P.A1),
    A2: await account("A2", P.A2),
    A1a: await account("A1a", P.A1a),
    A1b: await account("A1b", P.A1b),
    A1a1: await account("A1a1", P.A1a1),
    A1b1: await account("A1b1", P.A1b1),
    A2a: await account("A2a", P.A2a),
    B1: await account("B1", P.B1),
    O1: await account("O1", P.O1),
  };

  const rootA = BigInt(
    (await createRootForUser({ userId: uidA, adminUserId: admin.id, note: "冒烟: 树A" }, ctx))
      .franchiseeId
  );
  const rootB = BigInt(
    (await createRootForUser({ userId: uidB, adminUserId: admin.id, note: "冒烟: 树B" }, ctx))
      .franchiseeId
  );
  const rootO = BigInt(
    (await createRootForUser({ userId: uidO, adminUserId: admin.id, note: "冒烟: 无关树O" }, ctx))
      .franchiseeId
  );

  /** 把已注册账号挂成一个节点 (树根下, 手动写 path/depth —— 建树走 DB 直插, 稳妥且快) */
  const mkNode = async (
    userId: bigint,
    parentFid: bigint,
    side: "left" | "right",
    rootFid: bigint,
    basePath: string,
    baseDepth: number
  ): Promise<bigint> => {
    const [u] = await db
      .select({ name: user.name, phoneEncrypted: user.phoneEncrypted, phoneHash: user.phoneHash })
      .from(user)
      .where(eq(user.id, userId))
      .limit(1);
    const [row] = await db
      .insert(franchisee)
      .values({
        name: u.name,
        phoneEncrypted: u.phoneEncrypted,
        phoneHash: u.phoneHash,
        // 夹具: 推荐人 = 点位父 = parentFid —— 直插时这是"张姐自己把人放在她名下的位子"
        referrerId: parentFid,
        placementParentId: parentFid,
        placementSide: side,
        placementPath: basePath + (side === "left" ? "L." : "R."),
        placementDepth: baseDepth + 1,
        rootId: rootFid,
        isActive: true,
        createdBy: admin.id,
      })
      .returning({ id: franchisee.id });
    await db.update(user).set({ franchiseeId: row.id }).where(eq(user.id, userId));
    return row.id;
  };

  // 树 A: A1(左) A2(右); A1 → A1a(左) A1b(右); A1a → A1a1(左); A1b → A1b1(右); A2 → A2a(左)
  const fidA1 = await mkNode(uid.A1, rootA, "left", rootA, "", 0);
  const fidA2 = await mkNode(uid.A2, rootA, "right", rootA, "", 0);
  const fidA1a = await mkNode(uid.A1a, fidA1, "left", rootA, "L.", 1);
  const fidA1b = await mkNode(uid.A1b, fidA1, "right", rootA, "L.", 1);
  const fidA1a1 = await mkNode(uid.A1a1, fidA1a, "left", rootA, "L.L.", 2);
  const fidA1b1 = await mkNode(uid.A1b1, fidA1b, "right", rootA, "L.R.", 2);
  const fidA2a = await mkNode(uid.A2a, fidA2, "left", rootA, "R.", 1);

  // 树 B: B1(左); 右子位留一个"无账号"节点 (验 ⑦ 新上层没账号)
  const fidB1 = await mkNode(uid.B1, rootB, "left", rootB, "", 0);
  const [orph2] = await db
    .insert(franchisee)
    .values({
      name: `${MARK}-无账号节点`,
      phoneEncrypted: encryptField(P.ORPH2),
      phoneHash: hashForLookup(P.ORPH2),
      referrerId: rootB,
      placementParentId: rootB,
      placementSide: "right",
      placementPath: "R.",
      placementDepth: 1,
      rootId: rootB,
      isActive: true,
      createdBy: admin.id,
    })
    .returning({ id: franchisee.id });

  // 无关树 O: O1(左)
  const fidO1 = await mkNode(uid.O1, rootO, "left", rootO, "", 0);

  // A 树里也放一个"无账号"节点 (A1a 的右子位, 验 ⑦ 被搬的节点没账号)
  //   ⚠ 不能占 A2 的右子位 —— 那是 ⑧ 要搬进去的目标窟窿
  const [orph] = await db
    .insert(franchisee)
    .values({
      name: `${MARK}-无账号节点`,
      phoneEncrypted: encryptField(P.ORPH),
      phoneHash: hashForLookup(P.ORPH),
      referrerId: fidA1a,
      placementParentId: fidA1a,
      placementSide: "right",
      placementPath: "L.L.R.",
      placementDepth: 3,
      rootId: rootA,
      isActive: true,
      createdBy: admin.id,
    })
    .returning({ id: franchisee.id });

  const node = (fid: bigint) =>
    db.select().from(franchisee).where(eq(franchisee.id, fid)).limit(1);

  const reparent = (over: Partial<Parameters<typeof adminReparentNode>[0]>) =>
    adminReparentNode(
      {
        moveFid: fidA1b,
        newParentFid: fidA2,
        side: "right",
        reason: "冒烟: 运营核对后改上层",
        adminUserId: admin.id,
        ...over,
      },
      ctx
    );

  const expectThrow = async (label: string, fn: () => Promise<unknown>, needle: string) => {
    try {
      await fn();
      ck(label, false, "居然成功了");
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      ck(label, msg.includes(needle), msg);
    }
  };

  // ===== 拒绝路径 =====
  await expectThrow("① 原因太短 → 拒", () => reparent({ reason: " x" }), "必须填写原因");
  await expectThrow("② 被搬节点不存在 → 拒", () => reparent({ moveFid: BigInt(999999999) }), "不存在");
  await expectThrow("② 新上层不存在 → 拒", () => reparent({ newParentFid: BigInt(999999999) }), "不存在");
  await expectThrow("③ 新上层 = 自己 → 拒", () => reparent({ newParentFid: fidA1b }), "她自己");
  await expectThrow(
    "④ 新上层在自己的下线里 → 拒 (成环)",
    () => reparent({ moveFid: rootA, newParentFid: fidA1a1 }),
    "下线"
  );
  await expectThrow(
    "⑤ 那条线已经有人 → 拒",
    () => reparent({ newParentFid: fidA2, side: "left" }), // A2 左 = A2a
    "已经有"
  );
  await expectThrow(
    "⑥ 本来就在那个位置 → 拒",
    () => reparent({ moveFid: fidA1b, newParentFid: fidA1, side: "right" }),
    "本来就在"
  );
  await expectThrow(
    "⑦ 被搬的节点没账号 → 拒",
    () => reparent({ moveFid: orph.id, newParentFid: fidA2, side: "left" }),
    "还没有账号"
  );
  await expectThrow(
    "⑦ 新上层没账号 → 拒",
    () => reparent({ moveFid: fidA1a1, newParentFid: orph2.id, side: "left" }),
    "还没有账号"
  );

  // ===== ⑧ 非根换上层: A1b (L.R. depth2) → A2 的 B线 (R.R.) =====
  const r1 = await reparent({ moveFid: fidA1b, newParentFid: fidA2, side: "right" });
  const [m1] = await node(fidA1b);
  const [c1] = await node(fidA1b1);
  ck("⑧ 顶层节点 path 换成新位置", m1.placementPath === "R.R.", `path=${m1.placementPath}`);
  ck("⑧ 顶层节点 depth 重算", m1.placementDepth === 2, `depth=${m1.placementDepth}`);
  ck("⑧ 顶层节点 root_id 不变 (同树内搬)", m1.rootId === rootA, `root=${m1.rootId}`);
  ck("⑧ 顶层节点 placement_parent_id → 新上层", m1.placementParentId === fidA2, `parent=${m1.placementParentId}`);
  ck(
    "⑧ 顶层节点 referrer_id 原地不动 (拆栏: 改上层不篡改推荐人)",
    m1.referrerId === fidA1,
    `ref=${m1.referrerId} (推荐人是 A1)`
  );
  ck("⑧ 顶层节点 placement_side → B线", m1.placementSide === "right", `${m1.placementSide}`);
  ck("⑧ 子树整体跟着走 (深度 +0, path 换前缀)", c1.placementPath === "R.R.R." && c1.placementDepth === 3, `path=${c1.placementPath} depth=${c1.placementDepth}`);
  ck("⑧ 子树 root_id 也对", c1.rootId === rootA, `root=${c1.rootId}`);
  ck("⑧ 返回值: 子树规模 = 2", r1.subtreeSize === 2, `size=${r1.subtreeSize}`);
  ck("⑧ 返回值: 没合并树", r1.mergedTrees === false);
  ck("⑧ 返回值: 原/新上层名字对", r1.fromParentName?.endsWith("A1") === true && r1.toParentName?.endsWith("A2") === true, `${r1.fromParentName} → ${r1.toParentName}`);

  // 原来的线空出来了 (A1 的右子位没人了)
  const [oldSlot] = await db
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(
      and(
        eq(franchisee.rootId, rootA),
        eq(franchisee.placementPath, "L.R."),
        eq(franchisee.isActive, true)
      )
    )
    .limit(1);
  ck("⑧ 原来的线释放了 (没人在 L.R.)", oldSlot == null, `占用者=${oldSlot?.id}`);

  // ⑩ 留痕
  const notes = m1.notesEncrypted ? decryptField(m1.notesEncrypted) : "";
  ck("⑩ 备注追加了改上层记录", notes.includes("管理员改上层") && notes.includes("运营核对后改上层"), notes.slice(-60));
  const audits = await db
    .select({ id: auditLog.id, tableName: auditLog.tableName, recordId: auditLog.recordId })
    .from(auditLog)
    .where(and(eq(auditLog.tableName, "franchisee"), eq(auditLog.recordId, fidA1b)))
    .limit(5);
  ck("⑩ audit_log 记下了这次变更", audits.length > 0, `rows=${audits.length}`);

  // ===== ⑨ 树根挂到别的树: 树 B → A1 的右子位 (刚空出来) =====
  const rootCountBefore = r1.rootCount;
  const r2 = await reparent({ moveFid: rootB, newParentFid: fidA1, side: "right", reason: "冒烟: 两棵树其实是一棵" });
  const [m2] = await node(rootB);
  const [b1] = await node(fidB1);
  const [bx] = await node(orph2.id);
  const [o1] = await node(fidO1);
  ck("⑨ 树根挂过去: path = 新基路径", m2.placementPath === "L.R.", `path=${m2.placementPath}`);
  ck("⑨ 树根挂过去: depth = 新父层+1", m2.placementDepth === 2, `depth=${m2.placementDepth}`);
  ck("⑨ 树根挂过去: root_id 改宗到 A", m2.rootId === rootA, `root=${m2.rootId}`);
  ck("⑨ 整棵树跟着下移 (B1: 'L.' → 'L.R.L.')", b1.placementPath === "L.R.L." && b1.placementDepth === 3, `path=${b1.placementPath} depth=${b1.placementDepth}`);
  ck("⑨ 无账号节点也一起搬 (不丢)", bx.placementPath === "L.R.R." && bx.placementDepth === 3, `path=${bx.placementPath}`);
  ck("⑨ root_id 全树改宗", b1.rootId === rootA && bx.rootId === rootA);
  ck("⑨ 合并了树 → mergedTrees=true", r2.mergedTrees === true);
  ck("⑨ 树数量 -1", r2.rootCount === rootCountBefore - 1, `${rootCountBefore} → ${r2.rootCount}`);
  ck("⑨ 无关的第三棵树一点没动", o1.placementPath === "L." && o1.rootId === rootO && o1.placementDepth === 1, `path=${o1.placementPath} root=${o1.rootId}`);

  // 图谱查询无重复行 + 覆盖整棵合并后的树
  const graph = await getPlacementTree(rootA);
  const flat: { id: string }[] = [];
  const walk = (n: { id: string; children?: unknown[] } | null) => {
    if (!n) return;
    flat.push({ id: n.id });
    for (const c of (n.children ?? []) as { id: string; children?: unknown[] }[]) walk(c);
  };
  walk(graph as unknown as { id: string; children?: unknown[] });
  const uniq = new Set(flat.map((f) => f.id));
  ck("⑨ 图谱无重复节点行", uniq.size === flat.length, `rows=${flat.length} uniq=${uniq.size}`);
  ck("⑨ 图谱覆盖合并后的整棵树 (A系 9 + B系 3 = 12)", flat.length === 12, `rows=${flat.length}`);

  const allNodes = await listAdminNodes();
  const dup = allNodes.filter((n) => n.rootFid === rootA.toString()).length;
  ck("⑨ 管理端节点总览: A 树 12 行 (不多不少)", dup === 12, `rows=${dup}`);

  // ===== ⑫ 拆栏验证: 推荐人 ≠ 点位父, 且强改上层不动推荐人 =====
  // 场景 (现实里天天发生): 张姐 (A2) 把人推荐进来, 但她名下一层两个位子都满了
  //   → 落位算法 BFS 顺延, 人实际落在她下线 (A2a) 名下。
  //   拆栏前: referrer_id 被写成**实际父节点** (A2a) → "谁推荐了她"当场就错了。
  //   拆栏后: referrer_id = A2 (推荐人), placement_parent_id = A2a (点位父)。
  const uidFb = await account("FB顺延落位", P.FB);
  const created = await createFranchisee(
    { name: `${MARK}-FB顺延落位`, phone: P.FB, referrerId: fidA2, sideHint: "left" },
    ctx,
    admin.id
  );
  const fbFid = BigInt(created.id);
  const [fb] = await node(fbFid);
  ck(
    "⑫ 落位: 推荐人那侧满了 → BFS 顺延到别人名下",
    fb.placementParentId === fidA2a && fb.placementPath === "R.L.L.",
    `parent=${fb.placementParentId} path=${fb.placementPath}`
  );
  ck(
    "⑫ 推荐人栏 = 当初那位推荐人 (不是实际落位的父)",
    fb.referrerId === fidA2 && fb.referrerId !== fb.placementParentId,
    `referrer=${fb.referrerId} placementParent=${fb.placementParentId}`
  );
  const referrerBefore = fb.referrerId;

  // 再把她强改上层 → 只该动点位父, 推荐人一个字都不能变
  const r3 = await reparent({
    moveFid: fbFid,
    newParentFid: fidA2a,
    side: "right",
    reason: "冒烟: 拆栏后强改上层不该改写推荐人",
  });
  const [fb2] = await node(fbFid);
  ck("⑫ 强改上层: 点位父改到新上层", fb2.placementParentId === fidA2a && fb2.placementPath === "R.L.R.", `parent=${fb2.placementParentId} path=${fb2.placementPath}`);
  ck("⑫ 强改上层: **推荐人一个字没变**", fb2.referrerId === referrerBefore, `before=${referrerBefore} after=${fb2.referrerId}`);
  ck("⑫ 返回值 referrerTouched=false (可断言的不变量)", r3.referrerTouched === false, `referrerTouched=${r3.referrerTouched}`);
  ck("⑫ 账号也还绑着", (await node(fbFid))[0].isActive === true);

  // ⑫-e 用户可见口径 (HTTP): 「我的上级」卡读的是**点位父**, 不是推荐人
  //   数据源: GET /api/me 的 franchisee.referrer (键名历史遗留, 语义 = 我的上层点位)
  const aliveMe = await fetch(`${BASE}/api/health`)
    .then((r) => r.ok)
    .catch(() => false);
  if (!aliveMe) {
    console.log(`⏭  ⑫ 「我的上级」= 点位父 跳过 (${BASE} 不可达, 未起 dev server)`);
  } else {
    const loginFb = await fetch(`${BASE}/api/auth/flutter-login`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ identifier: P.FB, password: "Test1234" }),
    });
    const { sessionToken: fbToken } = (await loginFb.json()) as { sessionToken?: string };
    if (!fbToken) {
      ck("⑫ 取 FB 账号 session (验「我的上级」)", false, `login=${loginFb.status}`);
    } else {
      const meRes = await fetch(`${BASE}/api/me`, {
        headers: { Cookie: `authjs.session-token=${fbToken}` },
      });
      const meBody = (await meRes.json()) as {
        franchisee?: { referrer?: { id?: string; name?: string } | null } | null;
      };
      ck(
        "⑫ GET /api/me「我的上级」= 点位父 A2a (不是推荐人 A2)",
        meBody.franchisee?.referrer?.id === fidA2a.toString() &&
          meBody.franchisee?.referrer?.id !== fidA2.toString(),
        `parent=${fidA2a} referrer=${fidA2} api=${meBody.franchisee?.referrer?.id}`
      );
    }
  }

  // ---- ⑪ 鉴权: 非管理员 403 (HTTP 段) ----
  const alive = await fetch(`${BASE}/api/health`)
    .then((r) => r.ok)
    .catch(() => false);
  if (!alive) {
    console.log(`⏭  ⑪ 跳过 (${BASE} 不可达, 未起 dev server)`);
  } else {
    await createAccountWithProfile({
      name: `${MARK}-非管理员`,
      phone: P.SALES,
      password: "Test1234",
      referralCode: code.code,
      actorUserId: admin.id,
    });
    const login = await fetch(`${BASE}/api/auth/flutter-login`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ identifier: P.SALES, password: "Test1234" }),
    });
    const { sessionToken } = (await login.json()) as { sessionToken?: string };
    if (!sessionToken) {
      ck("⑪ 取非管理员 session", false, `login=${login.status}`);
    } else {
      const res = await fetch(`${BASE}/api/admin/nodes/${fidA1b}/reparent`, {
        method: "POST",
        headers: {
          Cookie: `authjs.session-token=${sessionToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ newParentFid: String(fidA1a), side: "left", reason: "越权尝试" }),
      });
      ck("⑪ 非管理员 POST 强改上层 → 403", res.status === 403, `status=${res.status}`);
    }
  }

  // ---- ⑬ 全库结构一致性: 点位父列 ≡ path 推出来的父 (拆栏前提, 一条都不能错) ----
  {
    const { execSync } = await import("node:child_process");
    try {
      execSync("npx tsx scripts/audit-placement-integrity.ts --strict", { stdio: "pipe" });
      ck("⑬ 全库巡检: 点位父列 ≡ path / side / depth, 无重复位子", true);
    } catch (e) {
      const out = (e as { stdout?: Buffer }).stdout?.toString() ?? "";
      ck("⑬ 全库巡检: 点位父列 ≡ path / side / depth, 无重复位子", false, out.split("\n").slice(-14).join(" / "));
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
