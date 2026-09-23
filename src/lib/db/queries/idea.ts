// ============================================
// idea-store: 主人待开发想法 / 备忘录的 CRUD 业务层
// ============================================
//
// v0.1.5 主人 2026-09-23 拍 (ask_user d3e7f2a1 第二轮):
//   「我需要能手动记录一个待开发的想法, 有些备忘的意思, 可以增删改,
//    完成后勾选完成, 或丢弃」
//
// 服务端是单一真相源: API route 全部走这层 (避免每个 route 自己拼 SQL)。
//
// 设计:
//   - 状态机 (在 updateIdea 里集中处理, 不让调用方自己算 completed_at):
//     open      → done       填 completed_at = NOW()
//     done      → open       清 completed_at = NULL
//     done      → discarded  清 completed_at = NULL (discarded 不算"完成时间")
//     open      → discarded  清 completed_at = NULL (本来就 NULL)
//     discarded → open       清 completed_at = NULL
//     discarded → done       填 completed_at = NOW() (重新激活 + 直接完成)
//   - 写路径一律走 withAuditContext: idea_audit 触发器自动落 audit_log,
//     主人 review 时能查到"什么时候把哪个想法改成了什么状态"
//   - 列出按 updated_at DESC, 让主人最近动的想法在最上面 (符合直觉)
//   - 不分页: 主人自己的想法数量不大, 一次拉全不爆; 真到几百条再加分页
// ============================================

import { and, desc, eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { idea, type Idea, type IdeaStatus, type NewIdea } from "@/lib/db/schema";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";

// ============================================
// 读
// ============================================

export interface ListIdeasOptions {
  userId: bigint;
  /** 不传 = 全部; 传了 = 只查这个状态 (单 tab 用) */
  status?: IdeaStatus;
}

/**
 * API-friendly row shape (id/userId 都是 string, JSON 安全)
 * 跟 customers store::CustomerView 同口径 (NextResponse.json 不能序列化 BigInt)
 */
export interface IdeaApi {
  id: string;
  userId: string;
  title: string;
  description: string;
  status: IdeaStatus;
  createdAt: string; // ISO
  updatedAt: string;
  completedAt: string | null;
}

function toApiRow(row: Idea): IdeaApi {
  return {
    id: row.id.toString(),
    userId: row.userId.toString(),
    title: row.title,
    description: row.description,
    status: row.status,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    completedAt: row.completedAt ? row.completedAt.toISOString() : null,
  };
}

/** 列出一个主人的想法 (按 updated_at DESC) */
export async function listIdeas(opts: ListIdeasOptions): Promise<IdeaApi[]> {
  const where = opts.status
    ? and(eq(idea.userId, opts.userId), eq(idea.status, opts.status))
    : eq(idea.userId, opts.userId);

  const rows = await db
    .select()
    .from(idea)
    .where(where)
    .orderBy(desc(idea.updatedAt));
  return rows.map(toApiRow);
}

/** 取单条想法 (返回 null = 不存在或不属于这个 user) */
export async function getIdea(
  id: bigint,
  userId: bigint
): Promise<IdeaApi | null> {
  const [row] = await db
    .select()
    .from(idea)
    .where(and(eq(idea.id, id), eq(idea.userId, userId)))
    .limit(1);
  return row ? toApiRow(row) : null;
}

// ============================================
// 写 (走 audit context → idea_audit 触发器落 audit_log)
// ============================================

export interface CreateIdeaInput {
  userId: bigint;
  title: string;
  description?: string;
}

export async function createIdea(
  input: CreateIdeaInput,
  audit: AuditContext
): Promise<IdeaApi> {
  const row: NewIdea = {
    userId: input.userId,
    title: input.title.trim(),
    // description 允许 undefined → DB 默认空字符串 (zod 也允许空)
    description: input.description?.trim() ?? "",
    status: "open",
  };

  return await withAuditContext(audit, async (tx) => {
    const [inserted] = await tx.insert(idea).values(row).returning();
    if (!inserted) {
      throw new Error("createIdea: 插入未返回行 (DB 异常)");
    }
    return toApiRow(inserted);
  });
}

export interface UpdateIdeaPatch {
  title?: string;
  description?: string;
  status?: IdeaStatus;
}

export class IdeaNotFoundError extends Error {
  constructor(public readonly ideaId: bigint) {
    super(`想法不存在或不属于该用户: ${ideaId}`);
    this.name = "IdeaNotFoundError";
  }
}

/**
 * 更新想法 (只传要改的字段)
 *
 * 状态机在内部处理:
 *   - status 转 done       → 自动填 completed_at = NOW()
 *   - status 转 open       → 自动清 completed_at = NULL
 *   - status 转 discarded  → completed_at 不动 (语义: "丢弃那天"不算完成时间)
 */
export async function updateIdea(
  id: bigint,
  userId: bigint,
  patch: UpdateIdeaPatch,
  audit: AuditContext
): Promise<IdeaApi> {
  return await withAuditContext(audit, async (tx) => {
    // 1) 先确认这条想法属于这个 user (不暴露其他 user 的 id 是否存在)
    const [existing] = await tx
      .select({ id: idea.id })
      .from(idea)
      .where(and(eq(idea.id, id), eq(idea.userId, userId)))
      .limit(1);

    if (!existing) {
      throw new IdeaNotFoundError(id);
    }

    // 2) 算要 SET 哪些列 (含 completed_at 的状态机逻辑)
    const set: Partial<NewIdea> = {
      updatedAt: new Date(),
    };
    if (patch.title !== undefined) set.title = patch.title.trim();
    if (patch.description !== undefined) set.description = patch.description.trim();
    if (patch.status !== undefined) {
      set.status = patch.status;
      // 状态机: 同步 completed_at
      set.completedAt =
        patch.status === "done"
          ? new Date()
          : patch.status === "open"
          ? null
          : patch.status === "discarded"
          ? null // 丢弃时不留完成时间 (语义: 丢弃那天 ≠ 完成那天)
          : undefined;
    }

    const [updated] = await tx
      .update(idea)
      .set(set)
      .where(and(eq(idea.id, id), eq(idea.userId, userId)))
      .returning();

    if (!updated) {
      // 理论上不存在 (刚 select 出来); 防御性抛错
      throw new Error(`updateIdea: 未返回更新行, id=${id}`);
    }
    return toApiRow(updated);
  });
}

/** 真删 (audit_log 留痕; 主人说"丢弃"通常用 status='discarded', 这里是硬删) */
export async function deleteIdea(
  id: bigint,
  userId: bigint,
  audit: AuditContext
): Promise<boolean> {
  return await withAuditContext(audit, async (tx) => {
    const result = await tx
      .delete(idea)
      .where(and(eq(idea.id, id), eq(idea.userId, userId)))
      .returning({ id: idea.id });
    return result.length > 0;
  });
}