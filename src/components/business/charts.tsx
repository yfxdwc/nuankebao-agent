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

const COLORS = {
  primary: "#1f8a4c",
  primaryLight: "#7bc097",
  muted: "#a1a1aa",
};

export function MonthlyTrendChart({ data }: { data: MonthlyData[] }) {
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
        <CartesianGrid strokeDasharray="3 3" stroke="#e5e5e5" />
        <XAxis dataKey="month" stroke="#888" />
        <YAxis allowDecimals={false} stroke="#888" />
        <Tooltip
          contentStyle={{ borderRadius: 6, border: "1px solid #e5e5e5" }}
          formatter={(v: number) => [`${v} 次`, "到店"]}
        />
        <Line
          type="monotone"
          dataKey="count"
          stroke={COLORS.primary}
          strokeWidth={2}
          dot={{ fill: COLORS.primary, r: 4 }}
          activeDot={{ r: 6 }}
        />
      </LineChart>
    </ResponsiveContainer>
  );
}

export function RepurchaseChart({ data }: { data: IntervalData[] }) {
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
        <CartesianGrid strokeDasharray="3 3" stroke="#e5e5e5" />
        <XAxis dataKey="range" stroke="#888" />
        <YAxis allowDecimals={false} stroke="#888" />
        <Tooltip
          contentStyle={{ borderRadius: 6, border: "1px solid #e5e5e5" }}
          formatter={(v: number) => [`${v} 位`, "客户"]}
        />
        <Bar dataKey="count" fill={COLORS.primary} radius={[4, 4, 0, 0]} />
      </BarChart>
    </ResponsiveContainer>
  );
}