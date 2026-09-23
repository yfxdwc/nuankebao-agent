// POST /api/admin/insight-config/impact
//   回答 admin 页那个问题: 「改完会把多少客户的分数 / 行动改掉?」
//
// 为什么单独一个接口而不是塞进 PUT 的响应:
//   预览必须**保存前**能看 (用户还没决定要不要保存); 而且它比 PUT 慢得多
//   (每客户要按两套参数各跑一次完整洞察), 塞进 PUT 会把保存按钮卡住。
//
// 算法: 取最近更新的一批客户做**抽样**, 分别用「当前生效配置」和「草稿配置」
//   各跑一次 `loadCustomerInsight`, 比对:
//     - changedScores: 综合分或任一维度分变了
//     - changedActions: 行动条目 id 集合变了 (该做的事变了 —— 对销售更要命)
//
// ⚠ 为什么用 `loadCustomerInsight` 而不是"只算分数":
//   行动规则需要生日窗口 / 建议日 / 待办任务等上下文, 自己拼 `buildActionItems`
//   的入参很容易漏字段 → **低估**影响面 = 让人以为改了没事, 是最危险的假安全。
//
// ⚠ 诚实标注: 这是**抽样估算**, 不是全量。返回体带 `sampled` / `sampledAll`,
//   前端必须显示"抽样 N 位客户"而不是假装精确。全量重算应做成后台任务 (另一张票)。
//
// 权限: role=admin

import { NextRequest, NextResponse } from "next/server";
import { desc, eq, isNull } from "drizzle-orm";

import { auth } from "@/lib/auth";
import { isAuthSkipped } from "@/lib/auth/skip-auth";
import { db } from "@/lib/db";
import { customer as customerTable, user as userTable } from "@/lib/db/schema";
import { loadCustomerInsight } from "@/lib/customer/insight";
import { getEffectiveInsightConfig } from "@/lib/customer/insight-config-store";
import { logger } from "@/lib/errors";

/**
 * 抽样规模: 每位客户按两套参数各跑一次完整洞察 (各 ~6 次查询),
 * 25 × 2 在本机是秒级; 再大就该做成后台任务了。
 */
const SAMPLE_SIZE = 25;

export async function POST(request: NextRequest) {
  const session = await auth();
  if (!isAuthSkipped() && !session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  if (!session?.user?.id) {
    return NextResponse.json({ error: "需要登录" }, { status: 401 });
  }
  const [actor] = await db
    .select({ role: userTable.role })
    .from(userTable)
    .where(eq(userTable.id, BigInt(session.user.id)))
    .limit(1);
  if (actor?.role !== "admin") {
    return NextResponse.json(
      { error: "只有系统管理员能调节客户管理参数", code: "FORBIDDEN" },
      { status: 403 }
    );
  }

  let draft: unknown;
  try {
    draft = await request.json();
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  try {
    const currentCfg = await getEffectiveInsightConfig();
    const now = new Date();

    const rows = await db
      .select({ id: customerTable.id })
      .from(customerTable)
      .where(isNull(customerTable.deletedAt))
      .orderBy(desc(customerTable.updatedAt))
      .limit(SAMPLE_SIZE);

    let compared = 0;
    let changedScores = 0;
    let changedActions = 0;
    const examples: Array<{
      customerId: string;
      scoreBefore: number | null;
      scoreAfter: number | null;
      actionCountBefore: number;
      actionCountAfter: number;
    }> = [];

    for (const r of rows) {
      const [before, after] = await Promise.all([
        loadCustomerInsight(r.id, now, currentCfg),
        loadCustomerInsight(r.id, now, draft),
      ]);
      if (!before || !after) continue;
      compared++;

      const b = before.score;
      const a = after.score;
      const scoreChanged =
        b.overall !== a.overall ||
        b.effect.score !== a.effect.score ||
        b.engagement.score !== a.engagement.score ||
        b.value.score !== a.value.score;
      if (scoreChanged) changedScores++;

      const bIds = new Set(before.actions.map((x) => x.id));
      const aIds = new Set(after.actions.map((x) => x.id));
      const actionsChanged =
        bIds.size !== aIds.size || [...bIds].some((id) => !aIds.has(id));
      if (actionsChanged) changedActions++;

      if ((scoreChanged || actionsChanged) && examples.length < 5) {
        examples.push({
          customerId: r.id.toString(),
          scoreBefore: b.overall,
          scoreAfter: a.overall,
          actionCountBefore: bIds.size,
          actionCountAfter: aIds.size,
        });
      }
    }

    return NextResponse.json({
      /** ⚠ 抽样估算, 不是全量 */
      sampled: compared,
      sampledAll: rows.length < SAMPLE_SIZE,
      sampleSize: SAMPLE_SIZE,
      changedScores,
      changedActions,
      examples,
    });
  } catch (error) {
    logger.error("POST /api/admin/insight-config/impact failed", {}, error);
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}
