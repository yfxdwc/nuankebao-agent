// ============================================
// Section / SectionHeader / SectionBody — 内容分组原语
// ============================================
//
// 设计要点 (docs/ui-principles.md):
//   - 默认无边框无阴影 (原则 4: 容器越少越好):
//     <Section> 仅靠 gap-section(20) 与上一区块拉开, 不画线
//   - bordered=true 时才画 border-y (用于表格/长列表分组的语义边界)
//   - SectionHeader: 区块标题 17/600 + 描述 13/二级文字色 (原则 2)
//   - SectionBody 可选 divide-y (同质列表用分隔线代替卡片, 原则 4)
//
// 用法:
//   // 普通信息块 (推荐默认): 无边框
//   <Section title="最近跟进" description="按时间倒序">
//     <ListRow>...</ListRow>
//   </Section>
//
//   // 表格分组 (bordered): 用上下分隔线分组
//   <Section bordered>
//     <SectionHeader title="客户列表" />
//     <SectionBody divided>
//       {items.map(it => <Row key={it.id} ... />)}
//     </SectionBody>
//   </Section>
// ============================================

import * as React from "react";
import { cn } from "@/lib/utils";

// ----- SectionHeader: 标题 + 描述 + 右对齐动作 -----

export interface SectionHeaderProps {
  title?: React.ReactNode;
  description?: React.ReactNode;
  /** 右对齐动作 (通常是 Button variant="ghost" size="sm") */
  action?: React.ReactNode;
  className?: string;
}

const SectionHeader = React.forwardRef<HTMLDivElement, SectionHeaderProps>(
  ({ title, description, action, className }, ref) => (
    <div
      ref={ref}
      // gap-inline(8) 让标题/描述贴紧形成"视觉块" (原则 3)
      className={cn(
        "flex items-start justify-between gap-inline",
        // 标题与下方内容拉开, 避免一坨 —— gap-section-y 而非 tightGap(4)
        // 因为标题组是"独立区块", 不是组内元素
        "mb-section-y",
        className,
      )}
    >
      <div className="min-w-0 flex-1 space-y-tight">
        {title && (
          <h2 className="text-title-sm font-semibold text-content-primary">
            {title}
          </h2>
        )}
        {description && (
          <p className="text-body text-content-secondary">{description}</p>
        )}
      </div>
      {action && <div className="shrink-0">{action}</div>}
    </div>
  ),
);
SectionHeader.displayName = "SectionHeader";

// ----- SectionBody: 容器主体, 默认组内间距 8 -----

export interface SectionBodyProps {
  children: React.ReactNode;
  className?: string;
  /** 同质列表场景: 用分隔线代替"每条都包卡片" (原则 4) */
  divided?: boolean;
}

const SectionBody = React.forwardRef<HTMLDivElement, SectionBodyProps>(
  ({ children, divided = false, className }, ref) => (
    <div
      ref={ref}
      // 组内垂直间距 8 (inlineGap) —— 与父 SectionHeader 的 20 形成 "1:2.5 留白比"
      // (原则 3: 留白比 ≈ 1:2; 实际 8:20 = 1:2.5, 略偏紧但更符合"B 档紧凑专业"目标)
      className={cn(
        divided ? "divide-y divide-divider" : "flex flex-col gap-inline",
        className,
      )}
    >
      {children}
    </div>
  ),
);
SectionBody.displayName = "SectionBody";

// ----- Section: 完整结构 (Header + Body), 受控 border 开关 -----

export interface SectionProps {
  title?: React.ReactNode;
  description?: React.ReactNode;
  action?: React.ReactNode;
  children?: React.ReactNode;
  className?: string;
  /**
   * 默认 false: 无边框无阴影, 仅靠外层 gap-section 拉开
   * true: 加 border-y + my-section-y —— 用于表格/长列表的语义分组
   */
  bordered?: boolean;
}

const Section = React.forwardRef<HTMLElement, SectionProps>(
  (
    {
      title,
      description,
      action,
      children,
      bordered = false,
      className,
    },
    ref,
  ) => {
    const headerProps = { title, description, action };
    const hasHeader = title !== undefined || description !== undefined || action !== undefined;

    return (
      <section
        ref={ref}
        // 默认无装饰 —— 留给父级 space-y 把区块拉开
        // bordered 时画上下分隔线 + 上下 padding, 营造"独立分组"感
        className={cn(!bordered && "space-y-section-y", bordered && "border-y border-divider py-section-y", className)}
      >
        {hasHeader && <SectionHeader {...headerProps} />}
        {/* children 直接渲染; 调用方可以自己再包 <SectionBody divided> */}
        {children}
      </section>
    );
  },
);
Section.displayName = "Section";

export { Section, SectionHeader, SectionBody };