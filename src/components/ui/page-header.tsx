// ============================================
// PageHeader — B 档 · 页面顶部标题区
// ============================================
//
// 设计要点 (docs/ui-principles.md):
//   - 层级靠字重+颜色, 不靠放大 (原则 2): 标题 20 / 描述 13,
//     全靠 "text-content-primary vs text-content-secondary" 区分, 没有装饰
//   - 容器越少越好 (原则 4): 标题不加图标/色块装饰 —— 那个留给 sidebar/topbar
//   - 不用"卡片"包: 仅靠 gap-section(20) 与下方内容拉开 (原则 3)
//
// 用法:
//   <PageHeader
//     title="客户"
//     description="管理你的所有客户档案 + 跟进记录"
//     actions={<Button>新增客户</Button>}
//   >
//     {/* 可选: 标题下的次级内容, 比如 TabBar / 统计条 */}
//   </PageHeader>
// ============================================

import * as React from "react";
import { cn } from "@/lib/utils";

export interface PageHeaderProps {
  /** 页面主标题 (B 档: 20px / 600 / 一级文字色) */
  title: string;
  /** 标题下方的副说明 (B 档: 13px / 一级→次级文字色) */
  description?: React.ReactNode;
  /** 右侧动作区: 主按钮 / 筛选 / 主题切换等 */
  actions?: React.ReactNode;
  /** 标题下方可选内容: Tab / 统计条 / 面包屑等 */
  children?: React.ReactNode;
  className?: string;
}

// 注意: 这是 Server Component (纯展示, 无交互/状态, 不打 "use client")
// 任务硬约束 (B0b §1): "纯展示组件不要加 use client, 避免把整页拖进客户端渲染"
const PageHeader = React.forwardRef<HTMLElement, PageHeaderProps>(
  ({ title, description, actions, children, className }, ref) => (
    <header
      ref={ref}
      // 整体: 列布局 (移动端) → 横排 + 上下居中 (桌面)
      //   gap-section(20) 让 header 与下方内容自然分组 (原则 3)
      className={cn(
        "flex flex-col gap-section-y md:flex-row md:items-start md:justify-between",
        className,
      )}
    >
      {/* 标题 + 描述 + 可选次级内容 (左/上, 主区) */}
      <div className="min-w-0 flex-1 space-y-tight">
        <h1 className="text-title font-semibold text-content-primary">
          {title}
        </h1>
        {description && (
          <p className="text-body text-content-secondary">{description}</p>
        )}
        {children}
      </div>

      {/* 动作区 (右/下): 移动端整行宽度, 桌面端自动收缩不挤压标题 */}
      {actions && (
        <div className="flex w-full flex-col gap-2 md:w-auto md:flex-row md:items-center md:gap-inline md:shrink-0">
          {actions}
        </div>
      )}
    </header>
  ),
);
PageHeader.displayName = "PageHeader";

export { PageHeader };