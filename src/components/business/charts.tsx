"use client";

import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  LineChart,
  Line,
} from "recharts";

import { useChartColors } from "@/lib/use-theme-colors";

// ============================================
// 图表组件 (基于 Recharts)
// ============================================

interface MonthlyData {
  month: string;
  count: number;
}

interface IntervalData {
  range: string;
  count: number;
}

export function MonthlyTrendChart({ data }: { data: MonthlyData[] }) {
  const c = useChartColors();
  if (data.length === 0 || data.every((d) => d.count === 0)) {
    return (
      <p className="text-sm text-muted-foreground text-center py-8">
        暂无数据
      </p>
    );
  }

  // 显示月份 (YYYY-MM → MM月)
  const formatted = data.map((d) => ({
    month: d.month.slice(5) + "月",
    count: d.count,
  }));

  return (
    <ResponsiveContainer width="100%" height={250}>
      <LineChart data={formatted} margin={{ top: 10, right: 20, left: 0, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke={c.grid} />
        <XAxis dataKey="month" stroke={c.axis} />
        <YAxis allowDecimals={false} stroke={c.axis} />
        <Tooltip
          contentStyle={{ borderRadius: 6, border: `1px solid ${c.border}`, background: c.surface }}
          formatter={(v: number) => [`${v} 次`, "到店"]}
        />
        <Line
          type="monotone"
          dataKey="count"
          stroke={c.series1}
          strokeWidth={2}
          dot={{ fill: c.series1, r: 4 }}
          activeDot={{ r: 6 }}
        />
      </LineChart>
    </ResponsiveContainer>
  );
}

export function RepurchaseChart({ data }: { data: IntervalData[] }) {
  const c = useChartColors();
  if (data.length === 0 || data.every((d) => d.count === 0)) {
    return (
      <p className="text-sm text-muted-foreground text-center py-8">
        暂无数据 (需要至少 2 条不同日期的养生记录)
      </p>
    );
  }

  return (
    <ResponsiveContainer width="100%" height={250}>
      <BarChart data={data} margin={{ top: 10, right: 20, left: 0, bottom: 0 }}>
        <CartesianGrid strokeDasharray="3 3" stroke={c.grid} />
        <XAxis dataKey="range" stroke={c.axis} />
        <YAxis allowDecimals={false} stroke={c.axis} />
        <Tooltip
          contentStyle={{ borderRadius: 6, border: `1px solid ${c.border}`, background: c.surface }}
          formatter={(v: number) => [`${v} 位`, "客户"]}
        />
        <Bar dataKey="count" fill={c.series1} radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}