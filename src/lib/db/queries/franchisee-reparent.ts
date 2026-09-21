// ============================================
// 管理员 · 协商处理后**强改上层** (Reparent) —— 主人 2026-09-21 拍
// ============================================
// 主人原话:
//   「上层」= 点位父, 不一定是推荐码提供人。**上层一旦有人不能撤换**,
//   除非联系系统管理员协商处理。
//   「给管理员一个『协商处理后强改上层』的后台功能」
//
// 为什么需要这个口子:
//   常规改上层只有两条路 —— ① 三方确认里定的位置 (落位时定, 之后不动);
//   ② 认领上级 (promote, 只对**树根**开放, 见 franchisee-placement.ts)。
//   两者都不覆盖「上层填错了 / 现实里换了上级 / 两棵树其实是一棵」这类运营事实。
//   本函数就是那条**唯一的人工例外通道**: admin 单方 + 强制留原因 + 审计。
//
// 与三方确认的关系 (为什么不做成 placement_request 的一种 kind):
//   三方确认的价值 = 三方都点头才动 (本人 / 设置者 / 父节点)。
//   而本功能的**前提就是三方谈不拢** (上层不同意 / 上层人都不在 app 里), 硬塞进同一张
//   状态机 = 给「单方即执行」开分支, 后续改动最容易在这里被滥用 (同 admin-users.ts
//   里建根为什么不塞进去的理由)。所以: 独立入口 + 鉴权 + 必填原因 + 审计。
//
// 一次改动动什么 (整棵子树):
//   - placement_path   : 新基路径 + 原子树相对路径 (顶层节点 = 新基路径本身)
//                        ↑ 不是简单的前缀拼接: 顶层节点换线 (A↔B) 时它自己那段要丢掉,
//                          只有后代保留相对后缀
//   - placement_depth  : 整棵子树 + (新父层号+1 - 原层号)
//   - root_id          : 整棵子树改宗到新父所在的树 (多根合并 —— 两棵树在这里接上)
//   - placement_parent_id / placement_side (仅顶层节点): 指向新上层 + 新线别
//   - notes_encrypted  : 追加一行「谁在什么时候把谁改到哪 + 原因」(与建根同口径的留痕)
//
// ⚠ **不动 referrer_id** (推荐人) —— 这正是主人 2026-09-21 拍"拆栏"的目的:
//   改的是"她挂在谁下面"(结构), 不该改写"谁把她拉进来的"(业务关系)。
//   拆栏前两者共用一栏, 强改上层只能一起改 → 会篡改推荐关系;
//   现在 `placement_parent_id` 专门记点位父 (migration 0019), `referrer_id` 原地不动。
// ============================================

import { and, eq, isNull, sql } from "drizzle-orm";

import { db } from "@/lib/db";
import { franchisee, type PlacementSide } from "@/lib/db/schema";
import { decryptField, encryptField } from "@/lib/crypto/field";
import { withAuditContext, type AuditContext } from "@/lib/audit/context";
import { findNodeAccount } from "./franchisee-account";

/** path 最后一段 → 左/右侧 ('L.R.' → right); '' → null */
function sideFromPath(path: string): PlacementSide | null {
  if (path.endsWith("L.")) return "left";
  if (path.endsWith("R.")) return "right";
  return null;
}

/** 'L.R.' → 'L.' (placement 父节点路径); '' → null (树根没有上层) */
function parentPathOf(path: string): string | null {
  return path === "" ? null : path.slice(0, -2);
}

export interface ReparentInput {
  /** 要调整的节点 (整棵子树跟着走) */
  moveFid: bigint;
  /** 新的上层节点 (点位父) */
  newParentFid: bigint;
  /** 她在新上层下面占哪条线 (A线 = left / B线 = right) */
  side: PlacementSide;
  /** 原因 (必填 2-200 字 —— 这条通道是"协商处理", 没原因将来查不清) */
  reason: string;
  /** 操作的管理员账号 id */
  adminUserId: bigint;
}

export interface ReparentResult {
  moveFid: string;
  moveName: string;
  /** 原上层 (null = 她原来是树根) */
  fromParentFid: string | null;
  fromParentName: string | null;
  /** 新上层 */
  toParentFid: string;
  toParentName: string;
  side: PlacementSide;
  /** 改完之后顶层节点的新路径 / 新层号 */
  newPath: string;
  newDepth: number;
  /** 跟着一起动的节点数 (含她自己) */
  subtreeSize: number;
  /**
   * 她的「推荐人」有没有被这次操作改写 —— 恒为 false。
   * ⚠ 显式返回 (而不是省掉) 是为了让冒烟/前端能断言这条不变量:
   *   结构性改动 (挂到谁下面) **不允许**污染业务关系 (谁推荐了她)。
   */
  referrerTouched: boolean;
  /** 两棵树是否在这里合并了 (原 root ≠ 新 root) */
  mergedTrees: boolean;
  /** 改完之后全库的树数量 (前端一句人话: "现在共 N 棵树") */
  rootCount: number;
}

const SIDE_LABEL: Record<PlacementSide, string> = {
  left: "A线 (左)",
  right: "B线 (右)",
};

/** 追加一行留痕到备注 (读不出来就当空的, 不因为脏数据炸掉整个操作) */
function appendNote(
  current: string | null,
  line: string
): string {
  const base = current?.trim() ?? "";
  return base ? `${base}\n${line}` : line;
}

/**
 * 强改上层 (管理员专用, 单方生效 + 留痕)
 *
 * 拒绝的情形 (每条都是人话, 直接给前端弹):
 *   ① 原因没填 / 太短
 *   ② 节点或新上层不存在 (已解除加盟)
 *   ③ 新上层 = 她自己
 *   ④ 新上层在她自己的子树里 (成环 → 树会断)
 *   ⑤ 新上层那条线已经有人
 *   ⑥ 她本来就在那个位置 (没变化, 不用改)
 *   ⑦ 任一方**没有账号** (节点 ⇒ 账号 不变量, 见 franchisee-account.ts)
 *   ⑧ 任一方 root_id 缺失 (脏数据, 先跑数据修复, 不许瞎搬)
 */
export async function adminReparentNode(
  input: ReparentInput,
  ctx: AuditContext
): Promise<ReparentResult> {
  const reason = input.reason.trim();
  if (reason.length < 2) {
    throw new Error("改上层必须填写原因 (2-200 字, 审计要留痕)");
  }
  if (reason.length > 200) {
    throw new Error("原因最长 200 字");
  }
  if (input.moveFid === input.newParentFid) {
    throw new Error("不能把她自己的上层设成她自己");
  }
  if (input.side !== "left" && input.side !== "right") {
    throw new Error("线别只能是 A线 (left) 或 B线 (right)");
  }

  return withAuditContext(ctx, async (tx) => {
    const [move] = await tx
      .select()
      .from(franchisee)
      .where(and(eq(franchisee.id, input.moveFid), isNull(franchisee.deletedAt)))
      .limit(1);
    if (!move) throw new Error("要调整的加盟节点不存在 (可能已解除加盟)");

    const [parent] = await tx
      .select()
      .from(franchisee)
      .where(
        and(eq(franchisee.id, input.newParentFid), isNull(franchisee.deletedAt))
      )
      .limit(1);
    if (!parent) throw new Error("新的上层节点不存在 (可能已解除加盟)");

    // ⑧ 脏数据兜底: 非根却没有树归属 → 无法安全整树搬迁
    if (move.placementPath !== "" && move.rootId == null) {
      throw new Error("这个节点缺少加盟树归属 (root_id 为空), 先跑数据修复再改上层");
    }
    if (parent.placementPath !== "" && parent.rootId == null) {
      throw new Error("新的上层节点缺少加盟树归属 (root_id 为空), 先跑数据修复再让他当上层");
    }

    const moveRootId = move.rootId ?? move.id;
    const parentRootId = parent.rootId ?? parent.id;

    // ⑦ 节点 ⇒ 账号 不变量: 没账号的不该是节点, 更不该被搬来搬去
    if (!(await findNodeAccount(tx, move.id))) {
      throw new Error(
        `「${move.name}」还没有账号 —— 先让她用这个手机号注册登录, 再调整上层`
      );
    }
    if (!(await findNodeAccount(tx, parent.id))) {
      throw new Error(
        `新的上层「${parent.name}」还没有账号 —— 先让他用这个手机号注册登录, 才能当上层`
      );
    }

    // ④ 成环: 新上层不能落在她自己的子树里 (同树 + path 前缀; 跨树不可能成环)
    if (parentRootId === moveRootId) {
      const parentInMoveSubtree =
        move.placementPath === "" ||
        (parent.placementPath !== move.placementPath &&
          parent.placementPath.startsWith(move.placementPath));
      if (parentInMoveSubtree) {
        throw new Error(
          parent.id === move.id
            ? "不能把她自己的上层设成她自己"
            : `「${parent.name}」在她自己的下线里 —— 不能当下层自己的上层 (会把树打断)`
        );
      }
    }

    const newBasePath =
      parent.placementPath + (input.side === "left" ? "L." : "R.");
    const newDepth = parent.placementDepth + 1;

    // ⑥ 原地不动就不用改 (幂等: 重复点不会写出一堆假审计)
    if (move.placementPath === newBasePath) {
      throw new Error(`她本来就在「${parent.name}」的${SIDE_LABEL[input.side]}上, 不需要改`);
    }

    // ⑤ 目标线必须空着 (按 path + root_id 判 —— 这是图谱/上层的权威口径)
    const [clash] = await tx
      .select({ id: franchisee.id, name: franchisee.name })
      .from(franchisee)
      .where(
        and(
          eq(franchisee.rootId, parentRootId),
          eq(franchisee.placementPath, newBasePath),
          isNull(franchisee.deletedAt)
        )
      )
      .limit(1);
    if (clash) {
      throw new Error(
        `「${parent.name}」的${SIDE_LABEL[input.side]}已经有「${clash.name}」了 —— 一个人的一层只有 A线 / B线 两个位置`
      );
    }

    // ---- 整棵子树搬过去 ----
    // 子树口径: 新根 = 整个 root_id 那棵树; 非根 = 同树 + path 前缀 (含她自己)
    const subtreeWhere =
      move.placementPath === ""
        ? sql`(${franchisee.rootId} = ${moveRootId} OR ${franchisee.id} = ${moveRootId})`
        : sql`${franchisee.rootId} = ${moveRootId} AND ${franchisee.placementPath} LIKE ${move.placementPath + "%"}`;

    const subtree = await tx
      .select({ id: franchisee.id })
      .from(franchisee)
      .where(and(isNull(franchisee.deletedAt), subtreeWhere));

    const depthDelta = newDepth - move.placementDepth;
    // `substring(path from len(旧顶层path)+1)` = 后代在原树里的相对后缀
    //   ⚠ 必须 (..)::int 显式转类型: 参数是 unknown 时 PG 会挑中 `substring(text from text)`
    //     (= 正则版), 匹配不上直接给 NULL → 撞 placement_path NOT NULL (踩过)
    //   顶层节点自己 → 后缀为空 → 新 path 正好是 newBasePath (换线才算得对)
    //   树根搬迁 → 旧 path 为 '' → 后缀 = 全部 → 整棵树按原结构下降一层
    const skipChars = move.placementPath.length;
    await tx.execute(sql`
      UPDATE franchisee
      SET placement_path = ${newBasePath} || substring(placement_path from (${skipChars + 1})::int),
          placement_depth = placement_depth + ${depthDelta},
          root_id = ${parentRootId},
          updated_at = NOW()
      WHERE deleted_at IS NULL AND ${subtreeWhere}
    `);

    // 顶层节点: 点位父 (新列) + 线别。**绝不碰 referrer_id** (推荐人, 见文件头)
    const [oldParent] = parentPathOf(move.placementPath) == null
      ? []
      : await tx
          .select({ id: franchisee.id, name: franchisee.name })
          .from(franchisee)
          .where(
            and(
              eq(franchisee.rootId, moveRootId),
              eq(franchisee.placementPath, parentPathOf(move.placementPath)!),
              isNull(franchisee.deletedAt)
            )
          )
          .limit(1);

    const stamp = new Date().toISOString().slice(0, 10);
    const fromLabel = oldParent ? `「${oldParent.name}」` : "无 (她原来是树根)";
    let currentNotes: string | null = null;
    try {
      currentNotes = move.notesEncrypted ? decryptField(move.notesEncrypted) : null;
    } catch {
      currentNotes = null; // 备注读不出来不阻断业务 (审计里仍有原值)
    }
    const noteLine = `[${stamp} 管理员改上层] ${fromLabel} → 「${parent.name}」的${SIDE_LABEL[input.side]}: ${reason}`;

    await tx
      .update(franchisee)
      .set({
        placementParentId: parent.id,
        placementSide: input.side,
        notesEncrypted: encryptField(appendNote(currentNotes, noteLine)),
        updatedAt: sql`NOW()`,
      })
      .where(eq(franchisee.id, move.id));

    const roots = await tx
      .select({ id: franchisee.id })
      .from(franchisee)
      .where(and(eq(franchisee.placementPath, ""), isNull(franchisee.deletedAt)));

    return {
      moveFid: move.id.toString(),
      moveName: move.name,
      fromParentFid: oldParent ? oldParent.id.toString() : null,
      fromParentName: oldParent ? oldParent.name : null,
      toParentFid: parent.id.toString(),
      toParentName: parent.name,
      side: input.side,
      newPath: newBasePath,
      newDepth,
      subtreeSize: subtree.length,
      referrerTouched: false,
      mergedTrees: moveRootId !== parentRootId,
      rootCount: roots.length,
    };
  });
}
