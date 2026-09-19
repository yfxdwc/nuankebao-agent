// ============================================
// 落位「三方确认」冒烟脚本 (dev only)
//
// 跑: npx tsx scripts/smoke-placement-confirm.ts
// 覆盖: 发起 → 新加盟商本人确认 → 目标父节点确认 → 落位执行 → 校验 path/referrer
//       + 预占校验 (同点位二次发起应报错) + 拒绝分支
// 幂等: 会先清掉自己上次造的测试数据 (手机号 13900009999 / 13900007777)
// ============================================

import { config as loadEnv } from "dotenv";
loadEnv({ path: ".env.local" });

import { eq, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  franchisee,
  user,
  customer,
  franchisePlacementRequest,
  franchisePlacementConfirm,
} from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import {
  createPlacementRequest,
  decidePlacementRequest,
  getPlacementRequest,
  type PlacementActor,
} from "@/lib/db/queries/franchisee-placement";

const ROOT_FID = BigInt(process.env.ROOT_FID ?? "75");
/** 目标父节点: 不指定就自动挑一个「左位空闲」的节点 (根子树内, 优先浅层) */
const PARENT_FID_ARG = process.env.PARENT_FID
  ? BigInt(process.env.PARENT_FID)
  : null;
const NEW_PHONE = "13900009999";
const REJECT_PHONE = "13900007777";
const PARENT_PHONE = "13900000082";
const ctx = { userId: BigInt(1), ipAddress: "127.0.0.1" };

async function ensureUser(phone: string, name: string, fid: bigint | null) {
  const phoneHash = hashForLookup(phone);
  const [existing] = await db
    .select()
    .from(user)
    .where(eq(user.phoneHash, phoneHash))
    .limit(1);
  if (existing) {
    if (fid != null && existing.franchiseeId !== fid) {
      await db
        .update(user)
        .set({ franchiseeId: fid })
        .where(eq(user.id, existing.id));
    }
    return { ...existing, franchiseeId: fid ?? existing.franchiseeId, phoneHash };
  }
  const [created] = await db
    .insert(user)
    .values({
      name,
      phoneEncrypted: encryptField(phone),
      phoneHash,
      role: "sales",
      franchiseeId: fid,
    })
    .returning();
  return created;
}

function assert(cond: unknown, msg: string) {
  if (!cond) throw new Error(`❌ ${msg}`);
  console.log(`✓ ${msg}`);
}

async function cleanupPhones() {
  for (const phone of [NEW_PHONE, REJECT_PHONE]) {
    const h = hashForLookup(phone);
    // 先清申请单 (含上次跑挂留下的 pending, 否则点位被预占)
    const reqs = await db
      .select({ id: franchisePlacementRequest.id })
      .from(franchisePlacementRequest)
      .where(eq(franchisePlacementRequest.newPhoneHash, h));
    for (const r of reqs) {
      await db
        .delete(franchisePlacementConfirm)
        .where(eq(franchisePlacementConfirm.requestId, r.id));
      await db
        .delete(franchisePlacementRequest)
        .where(eq(franchisePlacementRequest.id, r.id));
    }
    await db.delete(customer).where(eq(customer.phoneHash, h));
    await db.delete(franchisee).where(eq(franchisee.phoneHash, h));
  }
}

async function main() {
  const [root] = await db
    .select()
    .from(franchisee)
    .where(eq(franchisee.id, ROOT_FID));
  let parent = PARENT_FID_ARG
    ? (
        await db
          .select()
          .from(franchisee)
          .where(eq(franchisee.id, PARENT_FID_ARG))
      )[0]
    : undefined;
  if (!parent) {
    // 自动找「左位空闲」的节点 (根子树内)
    const rows = await db.execute(sql`
      SELECT f.id, f.name, f.placement_path, f.placement_depth
      FROM franchisee f
      WHERE f.deleted_at IS NULL
        AND f.placement_path LIKE ${root.placementPath + "%"}
        AND NOT EXISTS (
          SELECT 1 FROM franchisee c
          WHERE c.deleted_at IS NULL AND c.placement_path = f.placement_path || 'L.'
        )
      ORDER BY f.placement_depth, f.id
      LIMIT 1
    `);
    const row = (rows as unknown as { id: bigint; name: string; placement_path: string; placement_depth: number }[])[0];
    if (!row) throw new Error("找不到左位空闲的节点");
    // ⚠ 原样 execute 拿到的 int8 是 string, 必须转 BigInt (不然 target_parent 匹配不上)
    parent = {
      id: BigInt(row.id as unknown as string),
      name: row.name,
      placementPath: row.placement_path,
      placementDepth: Number(row.placement_depth),
    } as typeof franchisee.$inferSelect;
  }
  if (!root || !parent) throw new Error(`种子数据缺 ${ROOT_FID}`);
  console.log(`根 = #${root.id} ${root.name} path="${root.placementPath}"`);
  console.log(
    `目标父节点 = #${parent.id} ${parent.name} path="${parent.placementPath}"`
  );

  const parentUser = await ensureUser(
    PARENT_PHONE,
    `冒烟-父节点${parent.id}`,
    parent.id
  );
  const newUser = await ensureUser(NEW_PHONE, "冒烟-新加盟商", null);
  assert(parentUser.franchiseeId === parent.id, "父节点账号已绑定 franchisee");
  assert(!!newUser, "新加盟商账号就绪 (未绑 franchisee)");

  const actorRoot: PlacementActor = {
    userId: BigInt(1),
    fid: root.id,
    phoneHash: null,
  };
  const actorNew: PlacementActor = {
    userId: newUser.id,
    fid: null,
    phoneHash: hashForLookup(NEW_PHONE),
  };
  const actorParent: PlacementActor = {
    userId: parentUser.id,
    fid: parent.id,
    phoneHash: hashForLookup(PARENT_PHONE),
  };

  await cleanupPhones();

  // 1) 发起
  const req = await createPlacementRequest(
    {
      kind: "create",
      initiatorFid: root.id,
      initiatorUserId: BigInt(1),
      targetParentFid: parent.id,
      targetSide: "left",
      newName: "冒烟-新加盟商",
      newPhone: NEW_PHONE,
    },
    ctx
  );
  assert(req.status === "pending", "发起后状态 pending");
  assert(req.required.length === 3, "发起人≠父节点 → 需要三方确认");
  assert(req.confirms.length === 1, "发起人自动记 1 票");

  // 2) 预占: 同点位二次发起应被拦
  let blocked = false;
  try {
    await createPlacementRequest(
      {
        kind: "create",
        initiatorFid: root.id,
        initiatorUserId: BigInt(1),
        targetParentFid: parent.id,
        targetSide: "left",
        newName: "冒烟-重复",
        newPhone: "13900008888",
      },
      ctx
    );
  } catch (e) {
    blocked = true;
    console.log("  预占生效 →", (e as Error).message);
  }
  assert(blocked, "同点位二次发起被预占拦下");

  // 3) 新加盟商本人确认
  const afterNew = await decidePlacementRequest(
    BigInt(req.id),
    actorNew,
    "approve",
    ctx
  );
  assert(afterNew.status === "pending", "新加盟商确认后仍待父节点 (2/3)");

  // 4) 目标父节点确认 → 执行
  const done = await decidePlacementRequest(
    BigInt(req.id),
    actorParent,
    "approve",
    ctx
  );
  assert(done.status === "executed", "三方齐 → executed");

  // 5) 校验落位
  const [created] = await db
    .select()
    .from(franchisee)
    .where(eq(franchisee.phoneHash, hashForLookup(NEW_PHONE)));
  assert(!!created, "新加盟商已入库");
  const expectPath = parent.placementPath + "L.";
  assert(created.placementPath === expectPath, `path = "${expectPath}"`);
  assert(
    created.placementDepth === parent.placementDepth + 1,
    `depth = 父+1 (${created.placementDepth})`
  );
  assert(created.referrerId === root.id, "推荐人 = 发起人 (设置者)");
  assert(created.placementSide === "left", "点位 = 左");
  const [cust] = await db
    .select()
    .from(customer)
    .where(eq(customer.phoneHash, hashForLookup(NEW_PHONE)));
  assert(!!cust, "同步落了客户档案");

  // 6) 拒绝分支 (右侧新点位)
  const req2 = await createPlacementRequest(
    {
      kind: "create",
      initiatorFid: root.id,
      initiatorUserId: BigInt(1),
      targetParentFid: parent.id,
      targetSide: "right",
      newName: "冒烟-被拒",
      newPhone: REJECT_PHONE,
    },
    ctx
  );
  const rejected = await decidePlacementRequest(
    BigInt(req2.id),
    actorParent,
    "reject",
    ctx
  );
  assert(rejected.status === "rejected", "父节点拒绝 → rejected");
  const [notCreated] = await db
    .select()
    .from(franchisee)
    .where(eq(franchisee.phoneHash, hashForLookup(REJECT_PHONE)));
  assert(!notCreated, "拒绝后没有落位");

  // 7) 详情 + 角色判定
  const view = await getPlacementRequest(BigInt(req.id), actorParent);
  assert(view?.myRole === "target_parent", "父节点账号判定为 target_parent");
  assert(view?.myDecision === "approve", "并看到自己已 approve");

  console.log("\n✅ 冒烟通过 (测试数据保留: 冒烟-新加盟商, 需要清理跑 scripts/cleanup-smoke-placement.ts)");
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
