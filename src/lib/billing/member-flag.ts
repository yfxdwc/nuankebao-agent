// ============================================
// 「是不是会员」的唯一判定口径 (读侧批量版)
// ============================================
// ADR-0012 的规则只有一条: member_until > now() = 会员; 角色即规则 = role='admin' 永久会员
// (与 entitlements.getMembership 同一口径 —— 那是**单用户**版, 这里是**批量读**版)
//
// 为什么需要批量版:
//   图谱一个屏幕 20+ 个节点、客户列表一页 20 行, 每个节点回一次库 = N+1 查询。
//   所以查询层一次 JOIN 出 (role, member_until), 在 JS 里逐行判; 或者用下面的
//   SQL 表达式直接算成布尔列 (EXISTS 子查询, 不产生重复行)。
//
// ★ 口径唯一性: JS 版 (memberFlagOf) 和 SQL 版 (memberExistsSql) 必须永远等价。
//   改判定规则时**两处一起改** —— 这是本文件存在的理由 (比散在 5 个查询里靠谱)。
//
// 实时性 (主人 2026-09-21 拍「会员标识实时同步」):
//   不落库、不缓存任何 member 布尔值。每次读都按当前 member_until / role 现算 →
//   充值转会员 / 到期掉会员, 下次拉列表或图谱就变, 不需要任何同步任务。

import { sql, type SQL } from "drizzle-orm";
import { db } from "@/lib/db";

/**
 * 单行判定 (纯函数, 单测用)
 *
 * @param role        user.role ('admin' = 永久会员)
 * @param memberUntil membership.member_until (null = 没充值过)
 * @param now         判定时刻 (默认当前; 测试可注入固定时刻)
 */
export function memberFlagOf(
  role: string | null | undefined,
  memberUntil: Date | string | null | undefined,
  now: Date = new Date()
): boolean {
  // 角色即规则: 系统管理员是永久会员 (与 getMembership 分支一致)
  if (role === "admin") return true;
  if (memberUntil == null) return false;
  const until = memberUntil instanceof Date ? memberUntil : new Date(memberUntil);
  if (Number.isNaN(until.getTime())) return false; // 脏值一律当非会员 (不炸整页)
  return until.getTime() > now.getTime();
}

/**
 * 会员存在性 SQL 表达式 (bool 列)
 *
 * @param match 关联条件 (节点 → 账号), 二选一:
 *   - 加盟节点: sql`u.franchisee_id = ${franchisee.id}`
 *   - 客户档案: sql`u.phone_hash = ${customer.phoneHash}` (账号=客户, 见 ADR-0013)
 *
 * 用 EXISTS 而不是 LEFT JOIN: 一个节点理论上可能挂多个账号 (脏数据) → JOIN 会把
 * 树/列表的行数变多 (节点重复), EXISTS 恒返回一行。NOW() 由库自己取, 不用应用时间。
 */
export function memberExistsSql(match: SQL): SQL<boolean> {
  return sql`EXISTS (
    SELECT 1 FROM "user" u
    LEFT JOIN membership m ON m.user_id = u.id
    WHERE ${match}
      AND (u.role = 'admin' OR m.member_until > NOW())
  )`;
}

/**
 * 单条判定: 这个手机号 hash 有没有「会员账号」 (create / get 单行场景)
 *
 * 列表/图谱走 SQL 布尔列 (memberExistsSql 直接选出来); 单行场景没法在行里带列,
 * 所以把同一个表达式 SELECT 出来 —— 口径仍然只有 memberExistsSql 一处。
 */
export async function memberFlagByPhoneHash(phoneHash: string): Promise<boolean> {
  const rows = await db.execute<{ m: boolean }>(
    sql`SELECT ${memberExistsSql(sql`u.phone_hash = ${phoneHash}`)} AS m`
  );
  return rows[0]?.m === true;
}
