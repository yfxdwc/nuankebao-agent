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
  franchisee,
  franchisePlacementConfirm,
  franchisePlacementRequest,
} from "@/lib/db/schema";
import { hashForLookup } from "@/lib/crypto/field";

const PHONES = ["13900009999", "13900007777", "13900008888"];

async function main() {
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
    const c = await db.delete(customer).where(eq(customer.phoneHash, h)).returning({ id: customer.id });
    const f = await db
      .delete(franchisee)
      .where(eq(franchisee.phoneHash, h))
      .returning({ id: franchisee.id });
    console.log(`✓ ${phone}: 申请单 ${reqs.length} / 客户 ${c.length} / 加盟商 ${f.length}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
