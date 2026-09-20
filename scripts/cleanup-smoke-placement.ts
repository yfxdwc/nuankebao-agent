// ============================================
// 清理冒烟脚本造的测试数据 (scripts/smoke-placement-confirm.ts 的收尾)
//
// 跑: npx tsx scripts/cleanup-smoke-placement.ts
// 清: 手机号 13900009999 / 13900007777 / 13900008888 相关的
//     客户档案 + 加盟商 + 落位申请单/确认记录
// 保留: 测试账号 (user) —— 主人/我下次还想演练三方确认时直接复用
// ============================================

import { config as loadEnv } from "dotenv";
loadEnv({ path: ".env.local" });

import { eq, inArray, or } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  customer,
  user,
  franchisee,
  franchisePlacementConfirm,
  franchisePlacementRequest,
} from "@/lib/db/schema";
import { hashForLookup } from "@/lib/crypto/field";
import { sql } from "drizzle-orm";

const PHONES = ["13900009999", "13900007777", "13900008888"];

async function main() {
  // 先清「孤儿 pending 单」: move/unjoin 单指向已删/不存在的节点 (上次跑挂留下的)
  const orphanRows = (await db.execute(sql`
    SELECT r.id FROM franchise_placement_request r
    WHERE r.status = 'pending' AND r.kind <> 'create'
      AND NOT EXISTS (
        SELECT 1 FROM franchisee f
        WHERE f.id = r.move_fid AND f.deleted_at IS NULL
      )
  `)) as unknown as { id: string }[];
  for (const r of orphanRows) {
    await db
      .delete(franchisePlacementConfirm)
      .where(eq(franchisePlacementConfirm.requestId, BigInt(r.id)));
    await db
      .delete(franchisePlacementRequest)
      .where(eq(franchisePlacementRequest.id, BigInt(r.id)));
  }
  if (orphanRows.length > 0) console.log(`✓ 孤儿 pending 单清理: ${orphanRows.length}`);

  for (const phone of PHONES) {
    const h = hashForLookup(phone);
    // 测试加盟商 id (unjoin 单挂在 move_fid 上, 不挂 phone hash)
    const fids = (
      await db
        .select({ id: franchisee.id })
        .from(franchisee)
        .where(eq(franchisee.phoneHash, h))
    ).map((r) => r.id);
    const reqs = await db
      .select({ id: franchisePlacementRequest.id })
      .from(franchisePlacementRequest)
      .where(
        fids.length > 0
          ? or(
              eq(franchisePlacementRequest.newPhoneHash, h),
              inArray(franchisePlacementRequest.moveFid, fids)
            )!
          : eq(franchisePlacementRequest.newPhoneHash, h)
      );
    for (const r of reqs) {
      await db
        .delete(franchisePlacementConfirm)
        .where(eq(franchisePlacementConfirm.requestId, r.id));
      await db
        .delete(franchisePlacementRequest)
        .where(eq(franchisePlacementRequest.id, r.id));
    }
    // ⚠ 主人 2026-09-19 拍「建号即强制建档」: 该手机号如果**还有账号**, 客户档案不能删
    //   (否则账号与客户档案的绑定被清掉 → 不变量破; 冒烟账号复用同一批手机号时踩过)
    const [ownerAccount] = await db
      .select({ id: user.id })
      .from(user)
      .where(eq(user.phoneHash, h))
      .limit(1);
    const c = ownerAccount
      ? []
      : await db
          .delete(customer)
          .where(eq(customer.phoneHash, h))
          .returning({ id: customer.id });
    const f = await db
      .delete(franchisee)
      .where(eq(franchisee.phoneHash, h))
      .returning({ id: franchisee.id });
    console.log(
      `✓ ${phone}: 申请单 ${reqs.length} / 客户 ${c.length}${ownerAccount ? " (账号还在, 档案保留)" : ""} / 加盟商 ${f.length}`
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
