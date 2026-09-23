// ============================================
// 客户洞察参数元数据 单测
// ============================================
// 守护的东西 (最重要的一条在最前面):
//   ① **元数据的 min/max 与 resolveInsightConfig 的夹取范围完全一致**
//      —— admin 页允许填的范围必须等于后端会接受的范围。
//      不一致的后果: UI 让填 -5, 后端悄悄夹成 0, 用户以为存进去了 —— 最气人的一类配置 bug。
//      做法: 给每个数值参数喂 min-1 / max+1, 断言后端夹回的就是 min / max。
//   ② 每个元数据 path 在生效配置里**真实存在** (防拼错 "scoring.effect.recentNN")
//   ③ 分组/路径/标签无重复
//   ④ readParam / writeParam 的语义 (含 immutable 不改入参)
//
// 跑: pnpm test:run tests/insight-param-meta.test.ts

import { describe, it, expect } from "vitest";

import {
  INSIGHT_PARAM_META,
  INSIGHT_PARAM_GROUPS,
  paramsOfGroup,
  readParam,
  writeParam,
  flattenConfig,
} from "@/lib/customer/insight-param-meta";
import {
  DEFAULT_INSIGHT_CONFIG,
  resolveInsightConfig,
} from "@/lib/customer/insight-config";

describe("元数据自洽", () => {
  it("path 不重复", () => {
    const paths = INSIGHT_PARAM_META.map((p) => p.path);
    expect(new Set(paths).size).toBe(paths.length);
  });

  it("label 不重复 (同一分组内) — 免得 UI 上两个一样的名字", () => {
    for (const g of INSIGHT_PARAM_GROUPS) {
      const labels = paramsOfGroup(g.id).map((p) => p.label);
      expect(new Set(labels).size, `分组 ${g.id} 有重名`).toBe(labels.length);
    }
  });

  it("每个分组都至少有一个参数 (空分组 = UI 上一个点不开的折叠面板)", () => {
    for (const g of INSIGHT_PARAM_GROUPS) {
      expect(paramsOfGroup(g.id).length, `分组 ${g.id} 是空的`).toBeGreaterThan(0);
    }
  });

  it("每个参数都挂在已声明的分组上", () => {
    const ids = new Set(INSIGHT_PARAM_GROUPS.map((g) => g.id));
    for (const p of INSIGHT_PARAM_META) {
      expect(ids.has(p.group), `${p.path} 的分组 ${p.group} 未声明`).toBe(true);
    }
  });

  it("数值型都有 min/max 且 min < max", () => {
    for (const p of INSIGHT_PARAM_META.filter((x) => x.type === "number")) {
      expect(p.min, `${p.path} 缺 min`).toBeTypeOf("number");
      expect(p.max, `${p.path} 缺 max`).toBeTypeOf("number");
      expect(p.min!, `${p.path} min >= max`).toBeLessThan(p.max!);
    }
  });

  it("每个 path 在默认配置里真实存在且类型对得上", () => {
    for (const p of INSIGHT_PARAM_META) {
      const v = readParam(DEFAULT_INSIGHT_CONFIG, p.path);
      expect(v, `${p.path} 在默认配置里读不到 (path 拼错了?)`).toBeDefined();
      if (p.type === "number") {
        expect(typeof v, `${p.path} 默认值不是数字`).toBe("number");
      } else {
        expect(["high", "medium", "low"], `${p.path} 默认值不是优先级`).toContain(v);
      }
    }
  });

  it("默认值本身落在声明的区间内 (否则一打开页面就显示越界)", () => {
    for (const p of INSIGHT_PARAM_META.filter((x) => x.type === "number")) {
      const v = readParam(DEFAULT_INSIGHT_CONFIG, p.path) as number;
      expect(v, `${p.path} 默认值 ${v} < min ${p.min}`).toBeGreaterThanOrEqual(p.min!);
      expect(v, `${p.path} 默认值 ${v} > max ${p.max}`).toBeLessThanOrEqual(p.max!);
    }
  });
});

// ⭐ 本文件最重要的一组
describe("元数据区间 ≡ resolveInsightConfig 夹取范围", () => {
  const numeric = INSIGHT_PARAM_META.filter((p) => p.type === "number");

  it.each(numeric.map((p) => [p.path, p.min!, p.max!]))(
    "%s: 低于 min 会被夹到 %s / 高于 max 会被夹到 %s",
    (path, min, max) => {
      const below = resolveInsightConfig(setPath(path, min - 1));
      expect(readParam(below, path), `${path} 下界不一致`).toBe(min);

      const above = resolveInsightConfig(setPath(path, max + 1));
      expect(readParam(above, path), `${path} 上界不一致`).toBe(max);
    }
  );

  it.each(numeric.map((p) => [p.path]))(
    "%s: 区间内的值能生效 (不是被夹住的那个)",
    (path) => {
      const meta = numeric.find((p) => p.path === path)!;
      // 取区间中点, 避开恰好等于边界的歧义
      const mid = (meta.min! + meta.max!) / 2;
      if (mid <= meta.min! || mid >= meta.max!) return; // 区间太窄, 跳过

      const out = resolveInsightConfig(setPath(path, mid));
      const actual = readParam(out, path) as number;

      // 为什么带容差: 部分参数是「条数」, resolveInsightConfig 会 Math.round
      //   (scoring.effect.recentN / trend.headN / tailN), 中点 25.5 → 26 是**对的**。
      //   窄区间 (权重 0-1 这类) 不可能取整, 所以用极紧的容差 —— 免得容差把
      //   "被夹到边界" 这种真 bug 盖过去。
      const tolerance = meta.max! - meta.min! >= 5 ? 1 : 0.001;
      expect(
        Math.abs(actual - mid),
        `${path}: 期望接近 ${mid}, 实际 ${actual}`
      ).toBeLessThanOrEqual(tolerance);
    }
  );
});

describe("readParam / writeParam", () => {
  it("readParam: 深路径读得到; 中间缺失返回 undefined 而不是抛", () => {
    expect(readParam({ a: { b: { c: 7 } } }, "a.b.c")).toBe(7);
    expect(readParam({ a: {} }, "a.b.c")).toBeUndefined();
    expect(readParam(null, "a.b")).toBeUndefined();
    expect(readParam({ a: 1 }, "a.b")).toBeUndefined();
  });

  it("writeParam: 写入深路径, 且**不修改入参** (React state 靠这个刷新)", () => {
    const before = { a: { b: { c: 1 } } };
    const after = writeParam(before, "a.b.c", 2);

    expect(readParam(after, "a.b.c")).toBe(2);
    // 原对象纹丝不动
    expect(readParam(before, "a.b.c")).toBe(1);
    // 逐层是新对象 (浅拷贝链)
    expect(after.a).not.toBe(before.a);
  });

  it("writeParam: 中间层缺失时自动建出来", () => {
    const after = writeParam({ a: {} } as Record<string, unknown>, "a.b.c", 5);
    expect(readParam(after, "a.b.c")).toBe(5);
  });

  it("flattenConfig: 每个元数据 path 都有值", () => {
    const flat = flattenConfig(DEFAULT_INSIGHT_CONFIG);
    for (const p of INSIGHT_PARAM_META) {
      expect(flat[p.path], `${p.path} 没有扁平化出来`).toBeDefined();
    }
    expect(Object.keys(flat).length).toBe(INSIGHT_PARAM_META.length);
  });
});

/** 按点号路径包一层覆盖对象, 喂给 resolveInsightConfig */
function setPath(path: string, value: unknown): Record<string, unknown> {
  return writeParam({} as Record<string, unknown>, path, value);
}
