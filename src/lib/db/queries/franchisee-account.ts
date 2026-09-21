// ============================================
// 「节点 ⇒ 账号」不变量 (主人 2026-09-21 拍)
// ============================================
// 主人原话: 「无账号节点为什么要存在? 不能禁止/消除无账号节点吗, 要成为节点首先必需有账号。」
//
// 三条口径:
//   ① **新建节点必须绑账号**: 目标手机号必须已有 active user, 且建完自检绑定成功
//      (失败 → 抛错 → 事务回滚, 不留下孤儿节点)
//   ② **落地即绑**: linkAccountAndCustomer 是新节点落地的标准配套动作
//      (createFranchisee / 三方确认 create / promote 新建 三条路径共用本文件实现)
//   ③ **存量自愈**: 无账号的老节点, 等真人用该手机号注册时由注册流程自动认领
//      (见 src/lib/auth/registration.ts), 或用 scripts/audit-orphan-nodes.ts 巡检/处理
//
// ⚠ 历史包袱: 早期 seed / 脚本 / 老 web admin 直接 INSERT franchisee, 没管账号 ——
//   这就是"无账号节点"的来源。新代码一律走本文件的校验。
// ============================================

import { and, eq, isNull, sql } from "drizzle-orm";

import { db } from "@/lib/db";
import { customer, franchisee, user } from "@/lib/db/schema";
import { decryptField } from "@/lib/crypto/field";
import { franchiseeCustomerValues } from "./customer";

type Exec = typeof db;

/** 该手机号有没有可登录的账号 (active) */
export async function findActiveUserByPhoneHash(
  exec: Exec,
  phoneHash: string
): Promise<{ id: bigint; franchiseeId: bigint | null } | null> {
  const [u] = await exec
    .select({ id: user.id, franchiseeId: user.franchiseeId })
    .from(user)
    .where(and(eq(user.phoneHash, phoneHash), eq(user.isActive, true)))
    .limit(1);
  return u ?? null;
}

/**
 * 新建节点前的硬门槛: 这位加盟商必须已经有账号 (主人 2026-09-21 拍)
 *   - 没有 → 抛人话错误, 调用方直接转 400
 */
export async function requireAccountForNode(
  exec: Exec,
  phoneHash: string
): Promise<{ userId: bigint }> {
  const u = await findActiveUserByPhoneHash(exec, phoneHash);
  if (!u) {
    throw new Error(
      "这位加盟商还没有可登录的账号 —— 节点必须对应一个账号: 请先让她用这个手机号注册登录, 再落位"
    );
  }
  return { userId: u.id };
}

/** 这个节点绑的账号 (null = 孤儿节点 / 账号已停用) —— 不抛异常的查询版 */
export async function findNodeAccount(
  exec: Exec,
  fid: bigint
): Promise<{ id: bigint } | null> {
  const [row] = await exec
    .select({ id: user.id })
    .from(user)
    .where(and(eq(user.franchiseeId, fid), eq(user.isActive, true)))
    .limit(1);
  return row ?? null;
}

/**
 * 新节点落地后的自检 (建完必须绑上账号, 否则回滚)
 *   - 正常流程 100% 通过 (落位确认要求"本人"用该手机号登录过);
 *     这里兜的是脏数据 / 并发停用账号 / 历史脚本造的节点
 */
export async function assertNodeHasAccount(
  exec: Exec,
  fid: bigint,
  label = "加盟节点"
): Promise<void> {
  const row = await findNodeAccount(exec, fid);
  if (!row) {
    throw new Error(
      `${label} #${fid} 没有绑上账号 —— 节点必须对应一个账号 (已回滚, 请先让对方注册登录)`
    );
  }
}

/**
 * 新节点落地的标准配套动作 (create / promote / 老 createFranchisee 共用):
 *   ① 该手机号已有账号 → 绑 user.franchisee_id
 *      (绑了她才能: 登录进图谱 / 在后续「三方确认」里作为本人拍板)
 *   ② 落一份客户档案 (主人 2026-09-18 拍, 方案 A)
 *
 * 客户档案要明文 → 申请单里存的是密文, 这里解密 (franchiseeCustomerValues 内部再加密)
 */
export async function linkAccountAndCustomer(
  exec: Exec,
  opts: {
    fid: bigint;
    phoneHash: string | null;
    phoneEncrypted: string | null;
    name: string;
    createdBy: bigint;
  }
): Promise<void> {
  if (opts.phoneHash) {
    const [u] = await exec
      .select({ id: user.id, fid: user.franchiseeId })
      .from(user)
      .where(eq(user.phoneHash, opts.phoneHash))
      .limit(1);
    if (u) {
      let needBind = u.fid == null;
      if (!needBind && u.fid != null) {
        // 旧绑定指向已删/不存在的加盟商 → 重新绑到新节点
        const [old] = await exec
          .select({ deletedAt: franchisee.deletedAt })
          .from(franchisee)
          .where(eq(franchisee.id, u.fid))
          .limit(1);
        needBind = old == null || old.deletedAt != null;
      }
      if (needBind) {
        await exec
          .update(user)
          .set({ franchiseeId: opts.fid, updatedAt: sql`NOW()` })
          .where(eq(user.id, u.id));
      }
    }
  }

  const plainPhone = opts.phoneEncrypted ? decryptField(opts.phoneEncrypted) : "";
  await exec
    .insert(customer)
    .values(
      franchiseeCustomerValues({
        name: opts.name,
        phone: plainPhone,
        createdBy: opts.createdBy,
      })
    )
    .onConflictDoNothing({ target: customer.phoneHash });
}

/**
 * 建号时的自愈 (主人 2026-09-21 拍: 消除无账号节点):
 *   新账号的手机号若命中一个**已存在但没账号**的加盟节点 → 直接把账号绑上去
 *   (她本来就是树里的人 —— 老 seed / 老数据留下的孤儿节点, 一注册就补上了)
 *
 * 只处理"该节点没有任何 active 账号"的情况; 已经有账号的节点不动。
 */
export async function adoptOrphanNodeForNewAccount(
  exec: Exec,
  opts: { userId: bigint; phoneHash: string }
): Promise<{ adoptedFid: bigint } | null> {
  const [node] = await exec
    .select({ id: franchisee.id })
    .from(franchisee)
    .where(
      and(eq(franchisee.phoneHash, opts.phoneHash), isNull(franchisee.deletedAt))
    )
    .limit(1);
  if (!node) return null;

  const [bound] = await exec
    .select({ id: user.id })
    .from(user)
    .where(and(eq(user.franchiseeId, node.id), eq(user.isActive, true)))
    .limit(1);
  if (bound) return null; // 这个节点已经有账号了

  await exec
    .update(user)
    .set({ franchiseeId: node.id, updatedAt: sql`NOW()` })
    .where(eq(user.id, opts.userId));
  return { adoptedFid: node.id };
}
