// ============================================
// 会员降级: 读取时的字段过滤 (ADR-0012)
// ============================================
// 为什么不是"拒绝访问": 生日提醒是**设置项**, 不是数据本身。
// 非会员把它读成 null → 提醒逻辑自然不触发; 数据仍在库里, 续费后原设置自动回来。
// (与"存量数据可见、不可新增"的口径一致 —— 详见 ADR-0012 §5)

/** 单条客户: 去掉生日提醒设置 */
export function stripBirthdayReminder<T extends { birthdayRemindDays?: number | null }>(
  row: T
): T {
  return { ...row, birthdayRemindDays: null };
}

/** 列表/分页结果: 逐条去掉 (兼容 { items } / { data } / 数组 三种形状) */
export function stripBirthdayReminderFromList<T>(payload: T): T {
  if (Array.isArray(payload)) {
    return payload.map((r) => stripBirthdayReminder(r)) as unknown as T;
  }
  if (payload && typeof payload === "object") {
    const obj = payload as Record<string, unknown> & {
      items?: { birthdayRemindDays?: number | null }[];
      data?: { birthdayRemindDays?: number | null }[];
    };
    if (Array.isArray(obj.items)) {
      return { ...obj, items: obj.items.map((r) => stripBirthdayReminder(r)) } as unknown as T;
    }
    if (Array.isArray(obj.data)) {
      return { ...obj, data: obj.data.map((r) => stripBirthdayReminder(r)) } as unknown as T;
    }
  }
  return payload;
}
