// ============================================
// 生日: 距下次生日还有几天 (服务端, 跟进紧急度用)
// ============================================
// ⚠️ 目前只支持**阳历** (solar); 农历生日服务端返回 null (不参与紧急度),
//    由客户端 (Flutter `core/utils/birthday.dart`, 有 lunar 包) 负责展示。
//    服务端要支持农历需要一个 TS 农历库 (lunar-typescript) 或预计算列 —— 见方案 §13 风险表。
//
// 边界 (与客户端一致):
//   - 月/日 任一为空 → null (只知道年份也算不出来)
//   - 2/29 在平年 → 按 2 月最后一天 (2/28) 算
//   - 只往前看 0-370 天

export interface BirthdayWindow {
  /** 距下次生日还有几天 (0 = 今天) */
  daysUntil: number;
  /** 提醒窗口 (7/3/0 天); null = 不提醒 */
  remindDays: number;
}

export function solarBirthdayWindow(
  month: number | null,
  day: number | null,
  calendar: string,
  remindDays: number | null,
  now: Date
): BirthdayWindow | null {
  if (month == null || day == null) return null;
  if (calendar !== "solar") return null; // 农历: 服务端暂不支持 (客户端展示)
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  const today = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate())
  );

  const build = (year: number) => {
    // 2/29 平年 → 落到 2/28 (与客户端一致, 不报错)
    const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();
    const d = Math.min(day, lastDay);
    return new Date(Date.UTC(year, month - 1, d));
  };

  let next = build(today.getUTCFullYear());
  if (next.getTime() < today.getTime()) {
    next = build(today.getUTCFullYear() + 1);
  }
  const daysUntil = Math.round((next.getTime() - today.getTime()) / 86_400_000);
  return { daysUntil, remindDays: remindDays ?? 0 };
}
