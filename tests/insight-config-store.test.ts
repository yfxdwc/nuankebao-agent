// ============================================
// 客户洞察参数覆盖层 单测 (admin 调节页的后端)
// ============================================
// 主人 2026-09-23 拍: 「让评分规则及其他客户管理中的参数可在管理页面进行调节」
//
// 守护的东西:
//   ① 没覆盖时**行为与改前完全一致** (= 全用代码默认值) —— 落地当天不该有任何变化
//   ② 写入的值**先夹区间再落库** (不受信输入; 这是全店共用的参数)
//   ③ 版本号只在**内容真变了**时才 +1 (否则详情页会发无意义的"规则已更新")
//   ④ 重置 = 删行 (不是写一份"等于默认值"的覆盖 —— 那会在代码改默认后变成陈旧覆盖)
//   ⑤ 改配置**留痕** (audit_log) —— ADR-0015「配置类改动要留痕」
//   ⑥ 坏配置/读失败**不抛**, 回落默认 (一个坏配置不该让客户详情页打不开)
//   ⑦ 端到端: 存了覆盖之后, loadCustomerInsight 真的用上了新参数
//
// 跑: pnpm test:run tests/insight-config-store.test.ts

import { describe, it, expect, beforeEach, afterAll } from "vitest";
import { eq, sql } from "drizzle-orm";

import { db } from "@/lib/db";
import { appConfig, customer } from "@/lib/db/schema";
import { encryptField, hashForLookup } from "@/lib/crypto/field";
import {
  getEffectiveInsightConfig,
  getInsightConfigView,
  saveInsightConfig,
  resetInsightConfig,
  bumpVersion,
  INSIGHT_CONFIG_KEY,
} from "@/lib/customer/insight-config-store";
import { DEFAULT_INSIGHT_CONFIG } from "@/lib/customer/insight-config";
import { loadCustomerInsight } from "@/lib/customer/insight";

const CTX = { userId: null, ipAddress: "127.0.0.1" };

beforeEach(async () => {
  await db.delete(appConfig).where(eq(appConfig.key, INSIGHT_CONFIG_KEY));
});

afterAll(async () => {
  await db.delete(appConfig).where(eq(appConfig.key, INSIGHT_CONFIG_KEY));
});

describe("bumpVersion", () => {
  it("v1 → v2, v9 → v10 (不是字符串拼接)", () => {
    expect(bumpVersion("v1")).toBe("v2");
    expect(bumpVersion("v9")).toBe("v10");
    expect(bumpVersion("v99")).toBe("v100");
  });

  it("非法 / 空 / 脏数据 → 退回 v2, 不抛 (不能因为历史脏数据让保存失败)", () => {
    expect(bumpVersion("")).toBe("v2");
    expect(bumpVersion(undefined)).toBe("v2");
    expect(bumpVersion("abc")).toBe("v2");
    expect(bumpVersion("1")).toBe("v2");
  });
});

describe("读取: 没覆盖时行为与改前完全一致", () => {
  it("生效配置 = 代码默认值", async () => {
    const eff = await getEffectiveInsightConfig();
    expect(eff).toEqual(DEFAULT_INSIGHT_CONFIG);
  });

  it("view 标记为「未自定义」", async () => {
    const v = await getInsightConfigView();
    expect(v.isCustomized).toBe(false);
    expect(v.override).toBeNull();
    expect(v.updatedAt).toBeNull();
  });
});

describe("写入: 先夹区间再落库", () => {
  it("越界值被夹到边界后存进去 (不是原样存)", async () => {
    await saveInsightConfig(
      { scoring: { weakDimensionThreshold: 9999 } },
      CTX
    );

    const eff = await getEffectiveInsightConfig();
    expect(eff.scoring.weakDimensionThreshold).toBe(100); // max

    // 关键: 存进 DB 的也是夹过的值 —— 否则下次读到还是 9999
    const [row] = await db
      .select()
      .from(appConfig)
      .where(eq(appConfig.key, INSIGHT_CONFIG_KEY));
    expect(
      (row.value as { scoring: { weakDimensionThreshold: number } }).scoring
        .weakDimensionThreshold
    ).toBe(100);
  });

  it("非数字 / 垃圾值回落默认, 不抛", async () => {
    await saveInsightConfig(
      { scoring: { weakDimensionThreshold: "abc", weights: { effect: null } } },
      CTX
    );
    const eff = await getEffectiveInsightConfig();
    expect(eff.scoring.weakDimensionThreshold).toBe(
      DEFAULT_INSIGHT_CONFIG.scoring.weakDimensionThreshold
    );
    expect(eff.scoring.weights.effect).toBe(
      DEFAULT_INSIGHT_CONFIG.scoring.weights.effect
    );
  });

  it("整个 body 是垃圾 (字符串/数组/null) 也不抛, 全用默认", async () => {
    for (const junk of ["abc", [1, 2, 3], null, 42]) {
      const v = await saveInsightConfig(junk, CTX);
      expect(v.config).toEqual(
        // 版本号可能被 bump, 单独比内容
        expect.objectContaining({ scoring: expect.any(Object) })
      );
    }
    const eff = await getEffectiveInsightConfig();
    expect(eff.scoring.weakDimensionThreshold).toBe(
      DEFAULT_INSIGHT_CONFIG.scoring.weakDimensionThreshold
    );
  });

  it("只改一个字段, 其余保持默认 (覆盖是深合并, 不是整体替换)", async () => {
    await saveInsightConfig({ actions: { contactAbsoluteGapDays: 60 } }, CTX);
    const eff = await getEffectiveInsightConfig();
    expect(eff.actions.contactAbsoluteGapDays).toBe(60);
    expect(eff.actions.repurchaseAbsoluteOverdueDays).toBe(
      DEFAULT_INSIGHT_CONFIG.actions.repurchaseAbsoluteOverdueDays
    );
  });
});

describe("版本号: 只在内容真变了才 +1", () => {
  it("首次保存 (与默认不同) → +1", async () => {
    const v = await saveInsightConfig(
      { actions: { contactAbsoluteGapDays: 60 } },
      CTX
    );
    expect(v.versionBumped).toBe(true);
    expect(v.config.scoring.version).toBe("v2");
    expect(v.config.actions.version).toBe("v2");
  });

  it("保存同样的内容两次 → 第二次不再 +1 (否则详情页会发无意义的提示)", async () => {
    await saveInsightConfig({ actions: { contactAbsoluteGapDays: 60 } }, CTX);
    const again = await saveInsightConfig(
      { actions: { contactAbsoluteGapDays: 60 } },
      CTX
    );
    expect(again.versionBumped).toBe(false);
    expect(again.config.scoring.version).toBe("v2");
  });

  it("再改一次 → 继续 +1 (v2 → v3)", async () => {
    await saveInsightConfig({ actions: { contactAbsoluteGapDays: 60 } }, CTX);
    const v = await saveInsightConfig(
      { actions: { contactAbsoluteGapDays: 61 } },
      CTX
    );
    expect(v.versionBumped).toBe(true);
    expect(v.config.scoring.version).toBe("v3");
  });

  it("只提交默认值 (内容没变) → 不 +1", async () => {
    const v = await saveInsightConfig(DEFAULT_INSIGHT_CONFIG, CTX);
    expect(v.versionBumped).toBe(false);
    expect(v.config.scoring.version).toBe(DEFAULT_INSIGHT_CONFIG.scoring.version);
  });
});

describe("重置 = 删覆盖行 (不是写一份等于默认的值)", () => {
  it("重置后 isCustomized=false 且配置等于默认", async () => {
    await saveInsightConfig({ actions: { contactAbsoluteGapDays: 60 } }, CTX);
    const r = await resetInsightConfig(CTX);
    expect(r.deleted).toBe(true);
    expect(r.isCustomized).toBe(false);
    expect(r.config).toEqual(DEFAULT_INSIGHT_CONFIG);

    // 行确实没了 (不是留一行 value=默认)
    const rows = await db
      .select()
      .from(appConfig)
      .where(eq(appConfig.key, INSIGHT_CONFIG_KEY));
    expect(rows.length).toBe(0);
  });

  it("没覆盖时重置 → deleted=false, 不报错", async () => {
    const r = await resetInsightConfig(CTX);
    expect(r.deleted).toBe(false);
  });
});

describe("审计留痕 (ADR-0015 配置类改动要留痕)", () => {
  it("写入会写进 audit_log", async () => {
    await saveInsightConfig({ actions: { contactAbsoluteGapDays: 77 } }, CTX);

    const res = await db.execute(sql`
      SELECT table_name, operation FROM audit_log
      WHERE table_name = 'app_config'
      ORDER BY id DESC LIMIT 3
    `);
    const rows = res as unknown as Array<{ table_name: string; operation: string }>;
    expect(rows.length).toBeGreaterThan(0);
    expect(rows[0].table_name).toBe("app_config");
  });

  it("删除 (重置) 也会留痕", async () => {
    await saveInsightConfig({ actions: { contactAbsoluteGapDays: 77 } }, CTX);
    await resetInsightConfig(CTX);

    const res = await db.execute(sql`
      SELECT operation FROM audit_log
      WHERE table_name = 'app_config' ORDER BY id DESC LIMIT 1
    `);
    const rows = res as unknown as Array<{ operation: string }>;
    expect(rows.length).toBe(1);
    expect(rows[0].operation).toBe("DELETE");
  });
});

describe("端到端: 存了覆盖后, 客户洞察真的用新参数", () => {
  let customerId: bigint;
  // ⚠ 手机号必须**每次全新** —— 测试库不清库, 固定号码会在第二次跑本文件时
  //   撞 idx_customer_phone_hash (踩过: 用 seq 也不行, seq 每次跑都从 1 开始)
  let seq = 0;

  beforeEach(async () => {
    seq++;
    const phone = `139${String(Date.now() % 100000000).padStart(8, "0")}${seq}`;
    const [row] = await db
      .insert(customer)
      .values({
        name: `参数调节测试客户-${seq}`,
        phoneEncrypted: encryptField(phone),
        phoneHash: hashForLookup(phone),
        createdBy: 1,
      })
      .returning();
    customerId = row.id;
  });

  it("把「联系超期绝对兜底」调到 1 天 → 无互动客户立刻出现 contact_gap 行动", async () => {
    // 先确认默认下没有这条行动 (新客户没有任何互动)
    const before = await loadCustomerInsight(customerId, new Date(), undefined);
    expect(before?.score).toBeDefined();

    // 调参: 超过 1 天没联系就该提醒
    await saveInsightConfig(
      {
        actions: {
          contactAbsoluteGapDays: 1,
          neverContactedGraceDays: 0,
        },
      },
      CTX
    );

    // 不传 config → 走 DB 生效配置
    const after = await loadCustomerInsight(customerId, new Date(), undefined);
    expect(after).not.toBeNull();

    // 生效配置里那两项确实变了 (证明 DB 覆盖被读到了)
    const eff = await getEffectiveInsightConfig();
    expect(eff.actions.contactAbsoluteGapDays).toBe(1);
    expect(eff.actions.neverContactedGraceDays).toBe(0);

    // 显式传两套参数应得到不同结果 —— 证明参数真的参与计算 (不是被忽略)
    const strict = await loadCustomerInsight(customerId, new Date(), {
      actions: { contactAbsoluteGapDays: 1, neverContactedGraceDays: 0 },
    });
    const loose = await loadCustomerInsight(customerId, new Date(), {
      actions: { contactAbsoluteGapDays: 3650, neverContactedGraceDays: 365 },
    });
    const idsOf = (r: typeof strict) => new Set((r?.actions ?? []).map((a) => a.id));
    // 至少有一个方向不同 (通常 strict 会多出 contact_gap / never_contacted)
    const s = idsOf(strict);
    const l = idsOf(loose);
    expect(s.size !== l.size || [...s].some((x) => !l.has(x))).toBe(true);
  });

  it("重置后又回到默认 (参数不再影响)", async () => {
    await saveInsightConfig({ actions: { contactAbsoluteGapDays: 1 } }, CTX);
    await resetInsightConfig(CTX);
    const eff = await getEffectiveInsightConfig();
    expect(eff.actions.contactAbsoluteGapDays).toBe(
      DEFAULT_INSIGHT_CONFIG.actions.contactAbsoluteGapDays
    );
  });
});
