// ============================================
// 无账号加盟节点 巡检 / 处理 (主人 2026-09-21 拍)
// ============================================
// 主人原话: 「无账号节点为什么要存在? 不能禁止/消除无账号节点吗, 要成为节点首先必需有账号。」
//
// 口径:
//   - 新节点已经被硬门槛挡住 (requireAccountForNode + assertNodeHasAccount, 见
//     src/lib/db/queries/franchisee-account.ts)
//   - **存量**老节点 (早期 seed / 脚本 / 老 web admin 直接 INSERT) 用本脚本处理
//   - 真人注册时也会自动认领同手机号的孤儿节点 (registration.ts 自愈)
//
// 用法:
//   npx tsx scripts/audit-orphan-nodes.ts                    # 只报清单 (默认, 不动数据)
//   npx tsx scripts/audit-orphan-nodes.ts --bind             # 给每个孤儿节点补一个账号 (dev/运维)
//   npx tsx scripts/audit-orphan-nodes.ts --prune            # 软删**没有下线**的孤儿节点 (释放点位)
//   npx tsx scripts/audit-orphan-nodes.ts --bind --password=dev123456
//
// ⚠ --prune 会软删数据 (释放点位): 只删没有下线的; 有下线的必须人工处理
//   (让她本人注册 → 自愈绑定, 或走管理员「强改上层」/强删)
// ============================================

// ⚠ 必须是第一个 import (见 scripts/_env.ts)
import "./_env";

import { and, eq, inArray, isNull } from "drizzle-orm";

import { db } from "@/lib/db";
import { franchisee, user } from "@/lib/db/schema";
import { decryptField, hashForLookup } from "@/lib/crypto/field";
import { createAccountWithProfile } from "@/lib/auth/registration";

const args = process.argv.slice(2);
const doBind = args.includes("--bind");
const doPrune = args.includes("--prune");
const PASSWORD = args.find((a) => a.startsWith("--password="))?.split("=")[1];

interface Orphan {
  fid: bigint;
  name: string;
  path: string;
  depth: number;
  rootId: bigint | null;
  phone: string;
  childCount: number;
}

async function listOrphans(): Promise<Orphan[]> {
  const rows = await db
    .select({
      fid: franchisee.id,
      name: franchisee.name,
      path: franchisee.placementPath,
      depth: franchisee.placementDepth,
      rootId: franchisee.rootId,
      phoneEncrypted: franchisee.phoneEncrypted,
      uid: user.id,
    })
    .from(franchisee)
    .leftJoin(
      user,
      and(eq(user.franchiseeId, franchisee.id), eq(user.isActive, true))
    )
    .where(isNull(franchisee.deletedAt));
  const orphans = rows.filter((r) => r.uid == null);
  if (orphans.length === 0) return [];

  // 下线数 (同树 + path 前缀; 多根口径见 ADR-0014)
  const all = await db
    .select({
      id: franchisee.id,
      rootId: franchisee.rootId,
      path: franchisee.placementPath,
    })
    .from(franchisee)
    .where(isNull(franchisee.deletedAt));

  return orphans.map((o) => {
    const root = o.rootId ?? o.fid;
    const childCount = all.filter(
      (c) =>
        c.id !== o.fid &&
        (c.rootId ?? c.id) === root &&
        c.path !== o.path &&
        c.path.startsWith(o.path === "" ? "" : o.path) &&
        (o.path === "" ? c.path !== "" : true)
    ).length;
    return {
      fid: o.fid,
      name: o.name,
      path: o.path,
      depth: o.depth,
      rootId: o.rootId,
      phone: decryptField(o.phoneEncrypted),
      childCount,
    };
  });
}

async function main() {
  const [admin] = await db
    .select({ id: user.id })
    .from(user)
    .where(eq(user.role, "admin"))
    .limit(1);
  if (!admin) throw new Error("库里没有 admin, 先跑 pnpm db:ensure-admin");

  const orphans = await listOrphans();
  if (orphans.length === 0) {
    console.log("✅ 没有无账号节点 —— 全部节点都有可登录账号");
    return;
  }

  console.log(
    `⚠ 发现 ${orphans.length} 个无账号节点 (主人 2026-09-21 拍: 节点必须对应账号)\n`
  );
  console.log(
    ["fid", "名字", "层级", "下线", "手机号"].join("\t") + "\n" + "-".repeat(72)
  );
  for (const o of orphans) {
    console.log(
      [`#${o.fid}`, o.name, `第${o.depth}层`, String(o.childCount), o.phone].join(
        "\t"
      )
    );
  }
  const leaves = orphans.filter((o) => o.childCount === 0);
  const parents = orphans.filter((o) => o.childCount > 0);
  console.log(
    `\n小结: 无下线 ${leaves.length} 个 (可 --prune 软删) · 有下线 ${parents.length} 个 ` +
      "(只能让她本人注册自愈, 或走管理员强改上层/强删)"
  );

  if (doBind) {
    console.log(`\n→ --bind: 给这 ${orphans.length} 个节点各补一个账号 (注册流程会自动认领节点)`);
    let okCount = 0;
    let skipCount = 0;
    for (const o of orphans) {
      try {
        const res = await createAccountWithProfile({
          name: o.name,
          phone: o.phone,
          password: PASSWORD,
          allowNoReferral: true, // 运维补号: 没有推荐人 (不是被谁拉进来的)
          actorUserId: admin.id,
        });
        const adopted = res.adoptedFranchiseeId != null;
        adopted ? okCount++ : skipCount++;
        console.log(
          `${adopted ? "✅" : "⚠"} #${o.fid} ${o.name} → 账号 #${res.userId}` +
            (adopted ? "" : " (账号建了但没认领节点 —— 请人工看)")
        );
      } catch (e) {
        skipCount++;
        console.log(`⚠ #${o.fid} ${o.name} → 跳过: ${(e as Error).message}`);
      }
    }
    console.log(`\n补号完成: 认领成功 ${okCount} / 跳过 ${skipCount}`);
  }

  if (doPrune) {
    console.log(`\n→ --prune: 软删 ${leaves.length} 个**没有下线**的孤儿节点 (释放点位)`);
    if (leaves.length > 0) {
      await db
        .update(franchisee)
        .set({ deletedAt: new Date(), isActive: false })
        .where(
          inArray(
            franchisee.id,
            leaves.map((o) => o.fid)
          )
        );
      console.log(`✅ 已软删 ${leaves.length} 个 (客户档案保留, 不删人)`);
      const hashes = leaves.map((o) => hashForLookup(o.phone));
      const customers = await db
        .select({ id: user.id })
        .from(user)
        .where(inArray(user.phoneHash, hashes));
      console.log(
        `提示: 这 ${leaves.length} 位若还有客户档案 (${customers.length} 个同名账号), 客户档案保留 —— 他们退回「种子/普通客户」`
      );
    }
  }

  if (!doBind && !doPrune) {
    console.log(
      "\n(默认只报清单, 没动数据。要处理: --bind 补账号 / --prune 软删没有下线的)"
    );
  }
}

main().catch((e) => {
  console.error("💥", e);
  process.exit(1);
});
