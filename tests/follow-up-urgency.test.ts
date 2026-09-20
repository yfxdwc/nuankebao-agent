// ============================================
// 跟进紧急度 / 推荐标签 单测 (纯函数, 不碰库)
// ============================================
// 方案: docs/follow-up-list-plan.md §3 (信号表) + §4 (标签)
// 主人拍板: 紧急度排序只给会员(Q1) / 标签最多 2 个(Q2) / 动作文案(Q3) / 加盟商轻微加权(Q7)

import { describe, it, expect } from "vitest";
import {
  computeUrgency,
  pickFollowUpTags,
  daysBetween,
  type UrgencyInput,
} from "@/lib/follow-up/urgency";
import { solarBirthdayWindow } from "@/lib/follow-up/birthday";

const NOW = new Date("2026-09-20T09:00:00Z");
const daysAgo = (n: number) => new Date(NOW.getTime() - n * 86_400_000);

function base(over: Partial<UrgencyInput> = {}): UrgencyInput {
  return {
    customerType: "normal",
    createdAt: daysAgo(200),
    lastInteractionAt: daysAgo(2), // 刚联系过
    lastVisitAt: daysAgo(10),
    openTaskDueAts: [],
    now: NOW,
    ...over,
  };
}

describe("computeUrgency — 信号", () => {
  it("刚联系过 + 任务未到期 → 休眠池 (p4), 分数很低", () => {
    const r = computeUrgency(base());
    expect(r.score).toBe(0);
    expect(r.level).toBe("p4");
    expect(r.reason).toBe("跟进节奏正常");
  });

  it("跟进任务逾期 3 天 → 40 + 6 = 46 分, 且理由带逾期天数", () => {
    const r = computeUrgency(base({ openTaskDueAts: [daysAgo(3)] }));
    expect(r.score).toBe(46);
    expect(r.level).toBe("p2");
    expect(r.reason).toContain("逾期 3 天");
  });

  it("逾期封顶: 逾期 30 天也只算 40 + 20 = 60", () => {
    const r = computeUrgency(base({ openTaskDueAts: [daysAgo(30)] }));
    expect(r.score).toBe(60);
  });

  it("任务今天到期 → 30 分, 理由 = 今天有跟进任务到期", () => {
    const r = computeUrgency(base({ openTaskDueAts: [new Date("2026-09-20T18:00:00Z")] }));
    expect(r.score).toBe(30);
    expect(r.reason).toBe("今天有跟进任务到期");
  });

  it("逾期 + 很久没联系 → 两条信号叠加 (40+2 + 42 = 84, p0) 且理由两句", () => {
    const r = computeUrgency(
      base({ openTaskDueAts: [daysAgo(1)], lastInteractionAt: daysAgo(35) })
    );
    expect(r.score).toBe(84);
    expect(r.level).toBe("p0");
    expect(r.reason).toContain("逾期 1 天");
    expect(r.reason).toContain("35 天没联系");
  });

  it("距上次联系分档: 5 天 8 分 / 10 天 18 分 / 20 天 30 分 / 40 天 42 分 / 70 天 55 分", () => {
    const pts = (d: number) => computeUrgency(base({ lastInteractionAt: daysAgo(d) })).score;
    expect(pts(5)).toBe(8);
    expect(pts(10)).toBe(18);
    expect(pts(20)).toBe(30);
    expect(pts(40)).toBe(42);
    expect(pts(70)).toBe(55);
  });

  it("从没联系过的新客 (建档 9 天) → 35 分 + 新客理由", () => {
    const r = computeUrgency(base({ lastInteractionAt: null, createdAt: daysAgo(9) }));
    expect(r.score).toBe(35);
    expect(r.reason).toContain("还没联系过");
    expect(r.daysSinceContact).toBeNull();
  });

  it("刚建档 1 天且没联系 → 不算急 (0 分; 给销售一天缓冲)", () => {
    const r = computeUrgency(base({ lastInteractionAt: null, createdAt: daysAgo(1) }));
    expect(r.score).toBe(0);
  });

  it("生日当天 (会员信号) → 60 分, 理由 = 今天生日", () => {
    const r = computeUrgency(
      base({ birthday: { daysUntil: 0, remindDays: 3 } })
    );
    expect(r.score).toBe(60);
    expect(r.level).toBe("p1");
    expect(r.reason).toContain("今天生日");
    expect(r.signals.find((s) => s.key === "birthday_window")?.memberOnly).toBe(true);
  });

  it("生日窗口内 (2 天) → 45 分; 窗口外 (5 天, 窗口 3) → 0 分", () => {
    expect(
      computeUrgency(base({ birthday: { daysUntil: 2, remindDays: 3 } })).score
    ).toBe(45);
    expect(
      computeUrgency(base({ birthday: { daysUntil: 5, remindDays: 3 } })).score
    ).toBe(0);
  });

  it("非会员: 不传 birthday/repurchase → 会员信号天然不参与 (分数不虚高)", () => {
    const memberish = computeUrgency(
      base({
        birthday: { daysUntil: 0, remindDays: 3 },
        repurchase: { windowOpenedAt: daysAgo(2) },
      })
    );
    const free = computeUrgency(base());
    expect(memberish.score).toBeGreaterThan(free.score);
    expect(free.signals.every((s) => !s.memberOnly)).toBe(true);
  });

  it("复购窗口已开 5 天 → 50 分", () => {
    const r = computeUrgency(base({ repurchase: { windowOpenedAt: daysAgo(5) } }));
    expect(r.score).toBe(50);
    expect(r.reason).toContain("复购窗口");
  });

  it("加入加权: 加盟商 +5 / 种子 +5 / 普通 +0", () => {
    expect(computeUrgency(base({ customerType: "franchisee" })).score).toBe(5);
    expect(computeUrgency(base({ customerType: "seed" })).score).toBe(5);
    expect(computeUrgency(base({ customerType: "normal" })).score).toBe(0);
  });

  it("「加盟商」身份不当理由 (理由里不出现)", () => {
    const r = computeUrgency(base({ customerType: "franchisee" }));
    expect(r.reason).not.toContain("加盟商");
  });

  it("超长期未到店 (120 天) → +10", () => {
    const r = computeUrgency(base({ lastVisitAt: daysAgo(120) }));
    expect(r.score).toBe(10);
    expect(r.reason).toContain("120 天没到店");
  });

  it("封顶 100: 逾期 30 天 + 90 天没联系 + 生日 + 复购 + 加盟", () => {
    const r = computeUrgency(
      base({
        customerType: "franchisee",
        lastInteractionAt: daysAgo(90),
        lastVisitAt: daysAgo(200),
        openTaskDueAts: [daysAgo(30)],
        birthday: { daysUntil: 0, remindDays: 3 },
        repurchase: { windowOpenedAt: daysAgo(1) },
      })
    );
    expect(r.score).toBe(100);
    expect(r.level).toBe("p0");
  });

  it("分级边界: 逾期本身封顶 60 (p1); 想上 p0 必须叠加「很久没联系」", () => {
    // 逾期封顶: 40 + min(20, 2d)
    const byOverdue = (d: number) => computeUrgency(base({ openTaskDueAts: [daysAgo(d)] }));
    expect(byOverdue(1).score).toBe(42);
    expect(byOverdue(10).score).toBe(60);
    expect(byOverdue(10).level).toBe("p1"); // 单靠任务到不了 p0
    // 逾期 15 天 (60) + 30 天没联系 (42) = 100 → p0
    const combo = computeUrgency(
      base({ openTaskDueAts: [daysAgo(15)], lastInteractionAt: daysAgo(30) })
    );
    expect(combo.score).toBe(100);
    expect(combo.level).toBe("p0");
    // 边界档位
    expect(computeUrgency(base({ openTaskDueAts: [daysAgo(1)], lastInteractionAt: daysAgo(20) })).score).toBe(72); // 42+30 → p1
    expect(computeUrgency(base({ openTaskDueAts: [daysAgo(1)], lastInteractionAt: daysAgo(10) })).score).toBe(60); // 42+18 → p1
    expect(computeUrgency(base({ openTaskDueAts: [daysAgo(1)], lastInteractionAt: daysAgo(5) })).score).toBe(50);  // 42+8  → p2
    expect(computeUrgency(base({ lastInteractionAt: daysAgo(15) })).level).toBe("p3"); // 30 → p3
    expect(computeUrgency(base({ lastInteractionAt: daysAgo(5) })).level).toBe("p4");  // 8  → p4
  });
});

describe("pickFollowUpTags — 标签 (最多 2 个)", () => {
  const tagsOf = (input: UrgencyInput) => {
    const r = computeUrgency(input);
    return pickFollowUpTags(r, input);
  };

  it("正常节奏 → 不给标签 (安静)", () => {
    expect(tagsOf(base())).toEqual([]);
  });

  it("任务逾期 → 🔥该回访了 (动作文案)", () => {
    const tags = tagsOf(base({ openTaskDueAts: [daysAgo(2)] }));
    expect(tags).toHaveLength(1);
    expect(tags[0].key).toBe("overdue");
    expect(tags[0].label).toBe("该回访了");
    expect(tags[0].emoji).toBe("🔥");
  });

  it("从没联系过 → 🌟新客首访", () => {
    const tags = tagsOf(base({ lastInteractionAt: null, createdAt: daysAgo(9) }));
    expect(tags[0].key).toBe("new_lead");
  });

  it("70 天没联系 → 💤沉睡; 40 天 → ⚠️掉线", () => {
    expect(tagsOf(base({ lastInteractionAt: daysAgo(70) }))[0].key).toBe("stale");
    expect(tagsOf(base({ lastInteractionAt: daysAgo(40) }))[0].key).toBe("cold");
  });

  it("动作标签 + 生日标签 可共存 (最多 2 个)", () => {
    const tags = tagsOf(
      base({
        openTaskDueAts: [daysAgo(1)],
        birthday: { daysUntil: 1, remindDays: 3 },
      })
    );
    expect(tags).toHaveLength(2);
    expect(tags.map((t) => t.key)).toEqual(["overdue", "birthday"]);
  });

  it("生日优先于复购 (日历标签只留一个)", () => {
    const tags = tagsOf(
      base({
        birthday: { daysUntil: 0, remindDays: 0 },
        repurchase: { windowOpenedAt: daysAgo(1) },
      })
    );
    expect(tags.map((t) => t.key)).toEqual(["birthday"]);
  });

  it("复购窗口 → 🔁复购窗口 (会员标签, 标记 memberOnly)", () => {
    const tags = tagsOf(base({ repurchase: { windowOpenedAt: daysAgo(1) } }));
    expect(tags[0].key).toBe("repurchase");
    expect(tags[0].memberOnly).toBe(true);
  });

  it("标签文案都 ≤ 4 个字 (中老年可读; 数字放第二行/hint)", () => {
    const samples = [
      base({ openTaskDueAts: [daysAgo(1)] }),
      base({ lastInteractionAt: null, createdAt: daysAgo(9) }),
      base({ lastInteractionAt: daysAgo(40) }),
      base({ lastInteractionAt: daysAgo(70) }),
      base({ birthday: { daysUntil: 3, remindDays: 3 } }),
      base({ repurchase: { windowOpenedAt: daysAgo(1) } }),
    ];
    for (const s of samples) {
      for (const t of tagsOf(s)) {
        expect(t.label.length).toBeLessThanOrEqual(4);
      }
    }
  });
});

describe("solarBirthdayWindow — 阳历生日窗口", () => {
  it("今天生日 → 0 天", () => {
    const w = solarBirthdayWindow(9, 20, "solar", 3, NOW);
    expect(w?.daysUntil).toBe(0);
  });
  it("明天生日 → 1 天", () => {
    expect(solarBirthdayWindow(9, 21, "solar", 3, NOW)?.daysUntil).toBe(1);
  });
  it("今年已过 → 算到明年 (跨年)", () => {
    const w = solarBirthdayWindow(1, 5, "solar", 3, NOW);
    expect(w?.daysUntil).toBe(107); // 2026-09-20 → 2027-01-05
  });
  it("2/29 在平年落到 2/28", () => {
    const w = solarBirthdayWindow(2, 29, "solar", 7, new Date("2027-02-25T00:00:00Z"));
    expect(w?.daysUntil).toBe(3); // 2027 平年 → 2/28
  });
  it("农历 → 服务端返回 null (客户端负责展示)", () => {
    expect(solarBirthdayWindow(8, 15, "lunar", 3, NOW)).toBeNull();
  });
  it("缺月/日 → null", () => {
    expect(solarBirthdayWindow(null, 15, "solar", 3, NOW)).toBeNull();
    expect(solarBirthdayWindow(8, null, "solar", 3, NOW)).toBeNull();
  });
  it("remindDays 缺省 → 0 (只有当天才算窗口内)", () => {
    expect(solarBirthdayWindow(9, 20, "solar", null, NOW)?.remindDays).toBe(0);
  });
});

describe("daysBetween", () => {
  it("按日历天算 (昨天 23:00 = 1 天前; 不因小时差漂移)", () => {
    expect(daysBetween(new Date("2026-09-19T23:00:00Z"), NOW)).toBe(1);
    expect(daysBetween(new Date("2026-09-19T08:00:00Z"), NOW)).toBe(1);
    expect(daysBetween(new Date("2026-09-20T08:00:00Z"), NOW)).toBe(0);
  });
});
