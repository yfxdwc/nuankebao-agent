// ============================================
// 管理员 · 用户总览 (全部注册用户 + 加盟树节点)
// ============================================
// 主人 2026-09-21 拍:
//   「管理员的『我的』页面增加入口 → 全部注册用户管理页, 列表/图谱两种视图,
//     图谱能区分 加盟(接入节点树) / 未加盟(独立节点), 付费会员头像上有会员标识」
//
// 为什么做在 APK 里而不是 web admin: 同 admin_tools_page.dart 的理由 ——
//   web admin 冻结中 (ADR-0005), 而建根/看人这类操作主人在手机上就要能做。
//
// 只读总览, 不做任何写; 唯一写操作在 createRootForUser() (建根, admin 专用)
//
// 读敏感字段的口径 (AGENTS §3): 手机号**只读出来打码**, 明文不出这个文件;
//   管理员看的是「谁是谁」, 不是「号码是多少」——要看号请走主人拍板的专门入口
// ============================================

import { and, desc, eq, isNull, sql } from "drizzle-orm";

import { db } from "@/lib/db";
import { franchisee, membership, referralCode, user } from "@/lib/db/schema";
import { decryptField, encryptField } from "@/lib/crypto/field";
import { maskPhone } from "@/lib/utils";
import { memberFlagOf } from "@/lib/billing/member-flag";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";

export interface AdminUserView {
  id: string;
  name: string;
  /** 登录名 (如 admin); sales 用手机号登录 → 可为 null */
  username: string | null;
  role: string;
  isActive: boolean;
  avatarUrl: string | null;
  /** 打码手机号 (138****8000); 解密失败 = 空串 (脏数据不炸整页) */
  phoneMasked: string;
  /** 推荐码 (每人一个; 建号时分配, 见 ADR-0013) */
  referralCode: string | null;
  /** 会员 (role=admin 视为永久会员, 与 getMembership 口径一致) */
  member: {
    isMember: boolean;
    permanent: boolean;
    until: string | null;
  };
  /** 加盟节点 (null = 未加盟 = 图谱里的独立节点) */
  franchiseeId: string | null;
  createdAt: string;
}

export interface AdminNodeView {
  /** franchisee.id */
  fid: string;
  /** 节点显示名 = 加盟商名 (业务身份, 与客户图谱口径一致) */
  name: string;
  /** 绑定账号的姓名 (与加盟商名不同时前端可补一行「账号: x」) */
  accountName: string | null;
  /**
   * 父子关系 = franchisee.referrer_id (父节点 id)。
   *
   * ⚠ 别用 placement_path 推导父: 多根时每个根 path 都是 '' → depth=1 的节点会同时
   *   匹配到全部根 (JOIN 出重复行, 图谱错位)。path 只是根内相对路径, 跨根不唯一。
   */
  parentFid: string | null;
  side: "left" | "right" | null;
  depth: number;
  isRoot: boolean;
  /** 绑定的账号 (null = 历史/脚本造的节点, 没有账号能登录) */
  userId: string | null;
  avatarUrl: string | null;
  member: boolean;
}

export interface AdminUsersSummary {
  total: number;
  joined: number;
  notJoined: number;
  members: number;
  roots: number;
  /** 加盟树里没有账号的节点 (脚本/历史数据, 图谱上标注「无账号」) */
  nodesWithoutAccount: number;
}

export interface AdminUsersOverview {
  users: AdminUserView[];
  nodes: AdminNodeView[];
  summary: AdminUsersSummary;
}

/** 会员视图 (admin 角色 = 永久会员, 与 entitlements.getMembership 同一条规则) */
function memberOf(
  role: string,
  memberUntil: Date | null,
  now: Date
): AdminUserView["member"] {
  if (role === "admin") {
    return { isMember: true, permanent: true, until: null };
  }
  return {
    // 判定口径唯一在 member-flag.ts (admin 分支上面已提前返回, 这里 role 传非 admin)
    isMember: memberFlagOf(role, memberUntil, now),
    permanent: false,
    until: memberUntil ? memberUntil.toISOString() : null,
  };
}

/** 全部注册用户 (含会员 / 推荐码 / 加盟绑定) */
export async function listAdminUsers(now: Date = new Date()): Promise<AdminUserView[]> {
  const rows = await db
    .select({
      id: user.id,
      name: user.name,
      username: user.username,
      role: user.role,
      isActive: user.isActive,
      avatarUrl: user.avatarUrl,
      phoneEncrypted: user.phoneEncrypted,
      referralCode: referralCode.code,
      memberUntil: membership.memberUntil,
      // ⚠ 必须用 JOIN 出来的**活节点** id, 不用 user.franchisee_id 原值:
      //   dev 库里就有指向已删/不存在节点 (fid 136) 的历史行 → 直接信原值会把
      //   「未加盟」显示成「加盟」(图谱上人也挂不上树)
      franchiseeId: franchisee.id,
      createdAt: user.createdAt,
    })
    .from(user)
    .leftJoin(referralCode, eq(referralCode.userId, user.id))
    .leftJoin(membership, eq(membership.userId, user.id))
    .leftJoin(
      franchisee,
      and(eq(franchisee.id, user.franchiseeId), isNull(franchisee.deletedAt))
    )
    .orderBy(desc(user.createdAt), desc(user.id));

  return rows.map((r) => {
    let phoneMasked = "";
    try {
      phoneMasked = maskPhone(decryptField(r.phoneEncrypted));
    } catch {
      phoneMasked = "";
    }
    return {
      id: r.id.toString(),
      name: r.name,
      username: r.username,
      role: r.role,
      isActive: r.isActive,
      avatarUrl: r.avatarUrl,
      phoneMasked,
      referralCode: r.referralCode ?? null,
      member: memberOf(r.role, r.memberUntil, now),
      franchiseeId: r.franchiseeId ? r.franchiseeId.toString() : null,
      createdAt: r.createdAt.toISOString(),
    };
  });
}

/**
 * 全部加盟节点 (含**没有账号**的历史/脚本节点 —— 不带上它们图谱会断成一片孤岛)
 * 父子关系由 placement_path 推导: 'L.R.' 的父 = 'L.' (路径末尾固定 2 字符)
 */
export async function listAdminNodes(now: Date = new Date()): Promise<AdminNodeView[]> {
  const rows = await db.execute<{
    fid: string;
    name: string;
    parent_fid: string | null;
    side: string | null;
    depth: number;
    path: string;
    user_id: string | null;
    user_name: string | null;
    avatar_url: string | null;
    role: string | null;
    member_until: Date | string | null;
  }>(sql`
    SELECT f.id                                        AS fid,
           f.name                                      AS name,
           p.id                                        AS parent_fid,
           f.placement_side                            AS side,
           f.placement_depth                           AS depth,
           f.placement_path                            AS path,
           u.id                                        AS user_id,
           u.name                                      AS user_name,
           u.avatar_url                                AS avatar_url,
           u.role                                      AS role,
           m.member_until                              AS member_until
    FROM franchisee f
    -- ⚠ 父子关系用 referrer_id (父节点 id), 不要用 placement_path 推导:
    --   多根系统里每个根的 placement_path 都是 '' → 按 path 连父会把 depth=1 的节点
    --   连到**每一个根**上 (实测 2 个根时节点行数翻倍, 图谱整棵错位)
    LEFT JOIN franchisee p
           ON p.id = f.referrer_id
          AND p.deleted_at IS NULL
    LEFT JOIN "user" u
           ON u.franchisee_id = f.id
    LEFT JOIN membership m
           ON m.user_id = u.id
    WHERE f.deleted_at IS NULL
    ORDER BY f.placement_depth, f.id
  `);

  return rows.map((r) => {
    const until =
      r.member_until == null
        ? null
        : r.member_until instanceof Date
          ? r.member_until
          : new Date(r.member_until);
    return {
      fid: String(r.fid),
      name: r.name as string,
      accountName: (r.user_name as string | null) ?? null,
      parentFid: r.parent_fid == null ? null : String(r.parent_fid),
      side: (r.side as "left" | "right" | null) ?? null,
      depth: Number(r.depth ?? 0),
      isRoot: (r.path ?? "") === "",
      userId: r.user_id == null ? null : String(r.user_id),
      avatarUrl: r.avatar_url ?? null,
      member: memberOf(r.role ?? "sales", until, now).isMember,
    };
  });
}

export async function getAdminUsersOverview(
  now: Date = new Date()
): Promise<AdminUsersOverview> {
  const [users, nodes] = await Promise.all([listAdminUsers(now), listAdminNodes(now)]);
  return {
    users,
    nodes,
    summary: {
      total: users.length,
      joined: users.filter((u) => u.franchiseeId != null).length,
      notJoined: users.filter((u) => u.franchiseeId == null).length,
      members: users.filter((u) => u.member.isMember).length,
      roots: nodes.filter((n) => n.isRoot).length,
      nodesWithoutAccount: nodes.filter((n) => n.userId == null).length,
    },
  };
}

// ============================================
// 建根 (Bootstrap Root) — 主人 2026-09-21 拍: 「建根 = 先有账号」
// ============================================
// 为什么需要: 三方确认(设置者 + 本人 + 父节点)**天然盖不到根** —— 根没有父节点,
//   0 节点时三方里两方物理不存在。所以建根走 admin 单方 + 审计 (与 §6.5 落位豁免、
//   §6.6 建号豁免同一条原则: 树内多方确认, 树外系统级 admin 单方 + 留痕)。
//
// 与老 POST /api/franchisees 的区别 (为什么新写一个函数而不是复用):
//   老接口会 **INSERT 一条新 user** → 对"已有账号"建根必然撞唯一约束;
//   建根必须**挂到已注册账号**上: INSERT franchisee + UPDATE user.franchisee_id
//
// 不变量:
//   - 目标账号必须存在且 is_active
//   - 目标账号**不能已经在加盟树里** (一个账号一个节点)
//   - 建完根 → 后续节点照旧走三方确认 (本函数不碰 placement-requests)
// ============================================

export interface CreateRootInput {
  /** 要建成根的**已注册**账号 id */
  userId: bigint;
  /** 操作的管理员账号 id (审计 + created_by) */
  adminUserId: bigint;
  /** 建根原因 (必填, 审计留痕) */
  note: string;
}

export interface CreateRootResult {
  franchiseeId: string;
  userId: string;
  name: string;
  /** 建完后的根数量 (>1 = 多团队/多门店, 见 B1) */
  rootCount: number;
}

export async function createRootForUser(
  input: CreateRootInput,
  ctx: AuditContext
): Promise<CreateRootResult> {
  if (!input.note.trim()) {
    throw new Error("建根必须填写原因 (审计留痕)");
  }

  return withAuditContext(ctx, async (tx) => {
    const [target] = await tx
      .select()
      .from(user)
      .where(eq(user.id, input.userId))
      .limit(1);
    if (!target) throw new Error("目标账号不存在");
    if (!target.isActive) throw new Error("目标账号已停用, 不能设为根节点");
    if (target.franchiseeId != null) {
      throw new Error("该账号已经在加盟树里了 (一个账号一个节点)");
    }

    const [created] = await tx
      .insert(franchisee)
      .values({
        name: target.name,
        // 同一自然人的号 → 原样搬 (hash 用于查重; 加密值直接复制, 不解密再加密)
        phoneEncrypted: target.phoneEncrypted,
        phoneHash: target.phoneHash,
        referrerId: null,
        placementSide: null,
        placementPath: "",
        placementDepth: 0,
        isActive: true,
        notesEncrypted: encryptField(`建根: ${input.note.trim()}`),
        createdBy: input.adminUserId,
      })
      .returning();

    await tx
      .update(user)
      .set({ franchiseeId: created.id, updatedAt: sql`NOW()` })
      .where(eq(user.id, input.userId));

    const roots = await tx
      .select({ id: franchisee.id })
      .from(franchisee)
      .where(
        and(eq(franchisee.placementPath, ""), isNull(franchisee.deletedAt))
      );

    return {
      franchiseeId: created.id.toString(),
      userId: input.userId.toString(),
      name: created.name,
      rootCount: roots.length,
    };
  });
}
