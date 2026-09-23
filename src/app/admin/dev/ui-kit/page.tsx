// ============================================
// /admin/dev/ui-kit — 组件语言层验收靶子
// ============================================
//
// 本页**不是**业务页面, 是 B0b「UI 全面升级 · Web 组件语言层」的可视化验收页。
// B3 批会用这里展示的组件重写 12 个 admin 页面, 所以:
//   - 每个组件必须在这里被渲染一遍 (活的, 不是文档)
//   - 规格对照区把字号档 / 间距 / 圆角 / 热区的**实际取值**展示出来
//   - 调用方使用 props 遵循 src/components/ui/*.tsx 的类型签名
//
// 设计原则 (docs/ui-principles.md):
//   - 用 PageHeader 作页头, Section 分组, 不画外层装饰
//   - "规格对照"用 StatRow 展示每个 token 的取值 —— 与具体业务组件混用验证
//
// 严禁:
//   - 在这里引入新依赖
//   - 改业务页面 (本目录外)
//   - 改 token / 改护栏
// ============================================

import type { Metadata } from "next";

import { PageHeader } from "@/components/ui/page-header";
import { Section, SectionHeader, SectionBody } from "@/components/ui/section";
import {
  Table,
  TableHeader,
  TableBody,
  TableRow,
  TableHead,
  TableCell,
  TableEmpty,
} from "@/components/ui/data-table";
import { EmptyState } from "@/components/ui/empty-state";
import { FilterBar, FilterChip } from "@/components/ui/filter-bar";
import { StatRow, StatGroup } from "@/components/ui/stat-row";
import { Skeleton, SkeletonList } from "@/components/ui/skeleton";
import { Button } from "@/components/ui/button";
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";

import {
  Users,
  Plus,
  Search,
  Inbox,
  ArrowUpRight,
  type LucideIcon,
} from "lucide-react";

import { typeScale, size as sizeTokens, radius, space } from "@/lib/design-tokens.g";

// admin 全部强制 SSR (跟兄弟页保持一致)
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "UI 套件 · 开发工具 · 暖客宝",
  description: "Web 组件语言层验收靶子 (B0b)",
};

// ----------------------------------------------------------
// 数据: 仅本页用, 不污染业务层
// ----------------------------------------------------------

const sampleRows = [
  { name: "李梅", status: "活跃", updated: "3 天前" },
  { name: "王雪", status: "新客户", updated: "今早" },
  { name: "陈芳", status: "待跟进", updated: "昨天" },
];

// 字号档 — token 是 raw key (design-tokens.json scales.type), className 是 Tailwind 别名
const typeSpecs: Array<{
  token: keyof typeof typeScale;
  className: string;
  px: number;
  usage: string;
}> = [
  { token: "xs", className: "text-caption", px: typeScale.xs, usage: "角标 / 时间戳 / 辅助" },
  { token: "sm", className: "text-body", px: typeScale.sm, usage: "副文 / 帮助文字" },
  { token: "md", className: "text-body-lg", px: typeScale.md, usage: "正文 (B 档默认)" },
  { token: "lg", className: "text-title-sm", px: typeScale.lg, usage: "区块标题" },
  { token: "xl", className: "text-title", px: typeScale.xl, usage: "页面标题" },
  { token: "xxl", className: "text-display", px: typeScale.xxl, usage: "主页大数字 / hero" },
];

const spaceSpecs: Array<{ key: string; px: number; usage: string }> = [
  { key: "tightGap (4)", px: space.s4, usage: "组内紧贴" },
  { key: "inlineGap (8)", px: space.s8, usage: "组内同行" },
  { key: "cardGap (10)", px: space.s10, usage: "卡片之间" },
  { key: "cardPadding (14)", px: space.s14, usage: "卡片内边距" },
  { key: "pagePadding (16)", px: space.s16, usage: "页面左右边距" },
  { key: "sectionGap (20)", px: space.s20, usage: "区块之间" },
];

const radiusSpecs: Array<{ key: string; px: number; usage: string }> = [
  { key: "badge (4)", px: radius.r4, usage: "小标签" },
  { key: "md (6)", px: radius.r6, usage: "按钮 / 输入 / Skeleton" },
  { key: "card (10)", px: radius.r10, usage: "卡片" },
  { key: "dialog (14)", px: radius.r14, usage: "弹层" },
  { key: "sheet (16)", px: radius.r16, usage: "底部抽屉" },
  { key: "chip (pill)", px: radius.full, usage: "胶囊 / 全圆" },
];

const sizeSpecs: Array<{ key: string; px: number; usage: string }> = [
  { key: "controlSm (32)", px: sizeTokens.controlSm, usage: "紧凑控件 (桌面密集工具栏)" },
  { key: "controlMd (34)", px: sizeTokens.controlMd, usage: "常规控件" },
  { key: "buttonMinHeight (40)", px: sizeTokens.buttonMinHeight, usage: "次按钮" },
  { key: "controlLg (44)", px: sizeTokens.controlLg, usage: "大控件" },
  { key: "buttonLgHeight (48)", px: sizeTokens.buttonLgHeight, usage: "主按钮 (B 档)" },
  { key: "tapMin (48)", px: sizeTokens.tapMin, usage: "热区下限 (硬门槛)" },
  { key: "fabSize (56)", px: sizeTokens.fabSize, usage: "FAB" },
  { key: "listRowHeight (60)", px: sizeTokens.listRowHeight, usage: "列表行 (移动端)" },
];

// ----------------------------------------------------------
// 小组件: 规格条 (一段标题 + 横条 + 取值) —— 仅本页演示用
// ----------------------------------------------------------

function SpecBar({
  label,
  px,
  visualWidth,
}: {
  label: string;
  px: number;
  /** 横条像素长度 —— 与 px 同数值方便肉眼对比 */
  visualWidth: number;
}) {
  return (
    <div className="flex items-center gap-inline py-1">
      <span className="w-44 shrink-0 text-body text-content-secondary tabular-nums">
        {label}
      </span>
      <span
        className="h-2 rounded-badge bg-brand-surface"
        style={{ width: visualWidth }}
        aria-hidden
      />
      <span className="text-caption text-content-tertiary tabular-nums">
        {px}px
      </span>
    </div>
  );
}

// ===================================================
// 页面主体
// ===================================================

export default function UiKitPage() {
  return (
    <div className="mx-auto max-w-5xl space-y-section-y pb-section-y">
      {/* --- 页头 --- */}
      <PageHeader
        title="UI 套件"
        description="Web 组件语言层 (B0b) 验收靶子 — 7 个基础组件 + 规格对照"
        actions={
          <>
            <Badge variant="outline">B0b · Web 组件语言层</Badge>
            <Button variant="outline" size="sm">
              <ArrowUpRight className="h-4 w-4" />
              docs/ui-principles.md
            </Button>
          </>
        }
      >
        <p className="text-caption text-content-tertiary">
          下面是 <code className="font-mono">src/components/ui/</code> 下本批新增的 7 个组件。
          契约 (命名 / props / 视觉规则) 比实现更重要 — B3 批会用这里定义的接口重写 12 个 admin 页面。
        </p>
      </PageHeader>

      {/* --- 1. PageHeader --- */}
      <Section
        title="PageHeader · 页面顶部标题区"
        description="纯展示, Server Component. 层级靠字重+颜色, 不靠放大. 不用图标/色块装饰标题."
      >
        <SectionBody>
          <PageHeader
            title="客户"
            description="管理所有客户档案 + 跟进记录 + 健康追踪"
            actions={
              <>
                <Button variant="ghost" size="sm">
                  导出
                </Button>
                <Button size="sm">
                  <Plus className="h-4 w-4" />
                  新增客户
                </Button>
              </>
            }
          />
        </SectionBody>
      </Section>

      {/* --- 2. Section / SectionHeader / SectionBody --- */}
      <Section
        title="Section · 内容分组原语"
        description="默认无边框无阴影, 仅靠 gap-section(20) 拉开. bordered=true 时画 border-y."
      >
        <SectionHeader
          title="三种用法对比"
          description="A. 默认 (推荐) · B. 带描述 · C. bordered (长列表分组)"
        />
        <SectionBody>
          {/* A. 默认: 无边框 */}
          <div className="rounded-card bg-surface-subtle p-card-x">
            <p className="text-body text-content-secondary">
              A · 默认 Section — 仅靠外层 gap-section 与其他区块拉开, 不画线.
            </p>
          </div>

          {/* B. 带描述 + 右侧 action */}
          <Section
            title="B · 带标题 + 描述 + 动作"
            description="用 SectionHeader 的 action prop 右对齐"
            action={
              <Button variant="ghost" size="sm">
                查看更多
              </Button>
            }
          >
            <SectionBody>
              <p className="text-body text-content-secondary">
                区块内容 (这里只是一段示例文本).
              </p>
            </SectionBody>
          </Section>

          {/* C. bordered */}
          <Section
            bordered
            title="C · bordered=true"
            description="用于表格/长列表的语义边界"
          >
            <SectionBody divided>
              <p className="py-3 text-body text-content-secondary">行 1 (divide-y 分隔)</p>
              <p className="py-3 text-body text-content-secondary">行 2 (divide-y 分隔)</p>
              <p className="py-3 text-body text-content-secondary">行 3 (divide-y 分隔)</p>
            </SectionBody>
          </Section>
        </SectionBody>
      </Section>

      {/* --- 3. DataTable --- */}
      <Section
        title="DataTable · 表格原语"
        description="Web admin 的主力组件. 整体无外边框无阴影, 只靠分隔线. h-11 数据行 / h-9 表头."
      >
        <SectionBody>
          <Card variant="outlined">
            <CardContent className="p-0">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>姓名</TableHead>
                    <TableHead>状态</TableHead>
                    <TableHead align="right">最近跟进</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {sampleRows.map((r) => (
                    <TableRow key={r.name}>
                      <TableCell className="font-medium">{r.name}</TableCell>
                      <TableCell>{r.status}</TableCell>
                      <TableCell align="right" className="text-content-secondary">
                        {r.updated}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>

          {/* Empty 状态 (TableEmpty) */}
          <Card variant="outlined" className="mt-section-y">
            <CardContent className="p-0">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>姓名</TableHead>
                    <TableHead align="right">最近跟进</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  <TableEmpty
                    colSpan={2}
                    icon={Inbox}
                    title="还没有客户"
                    description="录入第一位客户, 系统会帮你管起来"
                    action={
                      <Button size="sm">
                        <Plus className="h-4 w-4" />
                        新增客户
                      </Button>
                    }
                  />
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </SectionBody>
      </Section>

      {/* --- 4. EmptyState --- */}
      <Section
        title="EmptyState · 空状态占位"
        description="图标三级文字色 (不画彩色背景). 必须给出口 (原则 8)."
      >
        <SectionBody>
          <Card variant="outlined">
            <CardContent className="p-0">
              <EmptyState
                icon={Users}
                title="还没有客户"
                description="从销售现场录入第一位客户, 系统会帮你管起来"
                action={
                  <Button>
                    <Plus className="h-4 w-4" />
                    新增客户
                  </Button>
                }
              />
            </CardContent>
          </Card>

          <Card variant="outlined">
            <CardContent className="p-0">
              <EmptyState
                size="sm"
                icon={Search}
                title="没有匹配的搜索结果"
                description="换个关键词试试"
                action={
                  <Button variant="ghost" size="sm">
                    清除筛选
                  </Button>
                }
              />
            </CardContent>
          </Card>
        </SectionBody>
      </Section>

      {/* --- 5. FilterBar / FilterChip --- */}
      <Section
        title="FilterBar · FilterChip · 筛选区"
        description="Web admin 表格页头部标准件. Chip 是胶囊 (全圆), 不要描边 (描边 = SaaS 观感)."
      >
        <SectionBody>
          <FilterBar
            actions={
              <>
                <Button variant="ghost" size="sm">
                  清除
                </Button>
                <Button variant="outline" size="sm">
                  导出
                </Button>
              </>
            }
          >
            <FilterChip active count={42}>
              全部
            </FilterChip>
            <FilterChip count={5}>新客户</FilterChip>
            <FilterChip count={28}>活跃</FilterChip>
            <FilterChip count={9}>待跟进</FilterChip>
            <FilterChip count={3} disabled>
              已归档 (暂不可选)
            </FilterChip>
          </FilterBar>

          {/* 第二行: 演示不带 actions */}
          <FilterBar>
            <FilterChip>本月</FilterChip>
            <FilterChip active>本季度</FilterChip>
            <FilterChip>本年度</FilterChip>
          </FilterBar>
        </SectionBody>
      </Section>

      {/* --- 6. StatRow / StatGroup --- */}
      <Section
        title="StatRow · StatGroup · 关键信息行"
        description="替代「一堆小卡片展示统计数字」. 用 divide-y 分隔行, 不画卡片. tone 只改 value 颜色."
      >
        <SectionBody>
          <StatGroup title="客户概览">
            <StatRow label="我的客户" value="42" />
            <StatRow
              label="本月新增"
              value="5"
              tone="success"
              hint="+12% MoM"
            />
            <StatRow
              label="待跟进"
              value="3"
              tone="warning"
            />
            <StatRow
              label="流失"
              value="1"
              tone="danger"
            />
            <StatRow
              label="本月订单"
              value="¥18,400"
              tone="brand"
              hint="6 单"
            />
          </StatGroup>
        </SectionBody>
      </Section>

      {/* --- 7. Skeleton / SkeletonList --- */}
      <Section
        title="Skeleton · SkeletonList · 加载占位"
        description="默认无动画 (反炫技 · 原则 7). 行高与真实列表一致以减少加载完成时的跳动."
      >
        <SectionBody>
          <Card variant="outlined">
            <CardHeader>
              <CardTitle className="text-base">单个 Skeleton (任意形状)</CardTitle>
            </CardHeader>
            <CardContent className="space-y-inline">
              <Skeleton className="h-4 w-32" />
              <Skeleton className="h-4 w-48" />
              <Skeleton className="h-10 w-full" />
              <Skeleton className="h-20 w-full" />
            </CardContent>
          </Card>

          <Card variant="outlined">
            <CardHeader>
              <CardTitle className="text-base">SkeletonList (模拟列表行)</CardTitle>
            </CardHeader>
            <CardContent className="p-0">
              <SkeletonList rows={4} showLeading showSubtitle />
            </CardContent>
          </Card>
        </SectionBody>
      </Section>

      {/* --- 规格对照 (Specification Reference) --- */}
      <Section
        title="规格对照 · 字号 / 间距 / 圆角 / 热区"
        description="所有取值的真源是 design/tokens/design-tokens.json. 这里只是把档位可视化, 方便 review 时一眼对齐."
      >
        <SectionBody>
          <div className="grid gap-section-y md:grid-cols-2">
            {/* 字号 */}
            <Card variant="outlined">
              <CardHeader>
                <CardTitle className="text-base">字号 (scales.type)</CardTitle>
              </CardHeader>
              <CardContent className="space-y-inline">
                {typeSpecs.map((s) => (
                  <div key={s.token} className="flex items-baseline gap-inline">
                    <span
                      className={`${s.className} text-content-primary`}
                      style={{ minWidth: 80 }}
                    >
                      {s.token}
                    </span>
                    <span className="text-caption text-content-tertiary tabular-nums">
                      {s.px}px
                    </span>
                    <span className="ml-auto text-caption text-content-secondary">
                      {s.usage}
                    </span>
                  </div>
                ))}
              </CardContent>
            </Card>

            {/* 间距 */}
            <Card variant="outlined">
              <CardHeader>
                <CardTitle className="text-base">间距 (semantic.space)</CardTitle>
              </CardHeader>
              <CardContent className="space-y-tight">
                {spaceSpecs.map((s) => (
                  <SpecBar key={s.key} label={s.key} px={s.px} visualWidth={s.px * 4} />
                ))}
              </CardContent>
            </Card>

            {/* 圆角 */}
            <Card variant="outlined">
              <CardHeader>
                <CardTitle className="text-base">圆角 (semantic.radius)</CardTitle>
              </CardHeader>
              <CardContent className="space-y-inline">
                {radiusSpecs.map((s) => (
                  <div key={s.key} className="flex items-center gap-inline">
                    <div
                      className="h-8 w-16 bg-brand-surface border border-divider"
                      style={{ borderRadius: s.px === 999 ? 999 : s.px }}
                      aria-hidden
                    />
                    <span className="text-body text-content-primary tabular-nums">
                      {s.key}
                    </span>
                    <span className="ml-auto text-caption text-content-secondary">
                      {s.usage}
                    </span>
                  </div>
                ))}
              </CardContent>
            </Card>

            {/* 尺寸 / 热区 */}
            <Card variant="outlined">
              <CardHeader>
                <CardTitle className="text-base">尺寸 / 热区 (scales.size)</CardTitle>
              </CardHeader>
              <CardContent className="space-y-tight">
                {sizeSpecs.map((s) => (
                  <SpecBar key={s.key} label={s.key} px={s.px} visualWidth={s.px * 3} />
                ))}
              </CardContent>
            </Card>
          </div>
        </SectionBody>
      </Section>

      {/* --- 反 vibe 备忘 --- */}
      <Section bordered title="反 vibe 备忘">
        <SectionBody>
          <ul className="space-y-inline text-body text-content-secondary">
            <li>❌ 表格加外边框 / 加阴影 → 只用分隔线</li>
            <li>❌ 列表项包卡片 → 用 divide-y + StatRow/ListRow</li>
            <li>❌ FilterChip 加 border → 用实底/纯背景</li>
            <li>❌ Skeleton 加 animate-pulse 默认值 → 调用方按需开</li>
            <li>❌ 字号 22px+ 表达"重要" → 靠字重 + 颜色</li>
            <li>❌ 空状态没有 action → 必须给出口</li>
            <li>❌ 用调色板类 (Tailwind 数字色阶) → 一律走语义层 (bg-brand / bg-success-surface …)</li>
          </ul>
        </SectionBody>
      </Section>

      {/* --- 页尾 --- */}
      <footer className="border-t border-divider pt-section-y">
        <p className="text-caption text-content-tertiary">
          本页是 B0b 组件语言层的验收靶子, 不是业务页面.
          所有组件契约见 <code className="font-mono">src/components/ui/*.tsx</code>;
          所有数值真源见 <code className="font-mono">design/tokens/design-tokens.json</code>;
          验收标准见 <code className="font-mono">docs/ui-principles.md</code>.
        </p>
      </footer>
    </div>
  );
}