// ============================================
// DataTable — 表格原语 (Web admin 的主力)
// ============================================
//
// 设计要点 (docs/ui-principles.md):
//   - 表格**整体**无外边框无阴影, 只靠分隔线 (原则 4: 容器越少越好)
//   - 行高 h-11(44px) / 表头 h-9(36px) —— B 档紧凑专业
//   - 行 hover 用 hover:bg-surface-subtle (中性交互色, 不靠品牌色)
//   - 选中用 bg-brand-surface —— 同 "FilterChip active" 的语义色, 不靠描边
//   - 表头文字 12px / 500 / 三级文字色, 不大写 (中文无大小写, 英文也别学 SaaS)
//   - 数字列右对齐 + tabular-nums (原则 1: 数字一眼可扫)
//   - 表格无障碍: caption / scope=col
//
// 用法:
//   <Table>
//     <TableHeader>
//       <TableRow>
//         <TableHead>姓名</TableHead>
//         <TableHead align="right">最近跟进</TableHead>
//       </TableRow>
//     </TableHeader>
//     <TableBody>
//       <TableRow><TableCell>张三</TableCell><TableCell align="right">3 天前</TableCell></TableRow>
//       ... <TableEmpty colSpan={3} />
//     </TableBody>
//   </Table>
// ============================================

import * as React from "react";
import { cn } from "@/lib/utils";
import { EmptyState } from "@/components/ui/empty-state";
import type { LucideIcon } from "lucide-react";

// ---- Root ----
const Table = React.forwardRef<
  HTMLTableElement,
  React.TableHTMLAttributes<HTMLTableElement>
>(({ className, ...props }, ref) => (
  <div className="w-full overflow-x-auto">
    {/* w-full + min-w-table 兜底, 防止窄屏挤压; 表格本身无外边框 */}
    <table
      ref={ref}
      className={cn("w-full min-w-table caption-bottom text-body", className)}
      {...props}
    />
  </div>
));
Table.displayName = "Table";

// ---- Header / Body / Footer ----
const TableHeader = React.forwardRef<
  HTMLTableSectionElement,
  React.HTMLAttributes<HTMLTableSectionElement>
>(({ className, ...props }, ref) => (
  // 不用大写字母 (中文没有大小写, 英文也别学 SaaS 那种 ALL CAPS 表头)
  <thead
    ref={ref}
    className={cn("bg-surface-subtle/50", className)}
    {...props}
  />
));
TableHeader.displayName = "TableHeader";

const TableBody = React.forwardRef<
  HTMLTableSectionElement,
  React.HTMLAttributes<HTMLTableSectionElement>
>(({ className, ...props }, ref) => (
  <tbody
    ref={ref}
    className={cn("[&_tr:last-child]:border-0", className)}
    {...props}
  />
));
TableBody.displayName = "TableBody";

const TableFooter = React.forwardRef<
  HTMLTableSectionElement,
  React.HTMLAttributes<HTMLTableSectionElement>
>(({ className, ...props }, ref) => (
  <tfoot
    ref={ref}
    className={cn(
      "border-t border-divider bg-surface-subtle/40 font-medium",
      className,
    )}
    {...props}
  />
));
TableFooter.displayName = "TableFooter";

// ---- Row ----
const TableRow = React.forwardRef<
  HTMLTableRowElement,
  React.HTMLAttributes<HTMLTableRowElement> & {
    selected?: boolean;
  }
>(({ className, selected, ...props }, ref) => (
  // h-11(44px) 数据行, 选中态走品牌 surface 色 —— 与 chip active 语义对齐
  <tr
    ref={ref}
    data-state={selected ? "selected" : undefined}
    className={cn(
      "h-11 border-b border-divider transition-colors hover:bg-surface-subtle",
      "data-[state=selected]:bg-brand-surface",
      className,
    )}
    {...props}
  />
));
TableRow.displayName = "TableRow";

// ---- Head / Cell ----
const TableHead = React.forwardRef<
  HTMLTableCellElement,
  React.ThHTMLAttributes<HTMLTableCellElement> & {
    align?: "left" | "right" | "center";
  }
>(({ className, align = "left", ...props }, ref) => {
  // 表头高度 h-9(36px), 字号 caption(12), 字重 medium, 三级文字色
  // tabular-nums 永远开 (数字列多, 没坏处)
  const alignClass =
    align === "right"
      ? "text-right"
      : align === "center"
      ? "text-center"
      : "text-left";
  return (
    <th
      ref={ref}
      scope="col"
      className={cn(
        "h-9 px-3 align-middle text-caption font-medium text-content-tertiary tabular-nums",
        alignClass,
        className,
      )}
      {...props}
    />
  );
});
TableHead.displayName = "TableHead";

const TableCell = React.forwardRef<
  HTMLTableCellElement,
  React.TdHTMLAttributes<HTMLTableCellElement> & {
    align?: "left" | "right" | "center";
    /** 数字列右对齐 + tabular-nums 一键开 (原则 1) */
    numeric?: boolean;
  }
>(({ className, align, numeric, ...props }, ref) => {
  const isRight = align === "right" || numeric;
  return (
    <td
      ref={ref}
      className={cn(
        "px-3 align-middle",
        // 文字列: 静默不处理; 数字列右对齐 + tabular-nums
        isRight && "text-right tabular-nums",
        // align prop 单独走 (e.g. center 对图标列)
        !isRight && align === "center" && "text-center",
        !isRight && align === "left" && "text-left",
        className,
      )}
      {...props}
    />
  );
});
TableCell.displayName = "TableCell";

// ---- Caption (a11y) ----
const TableCaption = React.forwardRef<
  HTMLTableCaptionElement,
  React.HTMLAttributes<HTMLTableCaptionElement>
>(({ className, ...props }, ref) => (
  // sr-only: 给屏幕阅读器用, 视觉上不显示
  <caption
    ref={ref}
    className={cn("sr-only", className)}
    {...props}
  />
));
TableCaption.displayName = "TableCaption";

// ---- Empty (整表无数据) ----
// 占满一行的 <td colSpan={N}>, 内部复用 EmptyState size="md"
const TableEmpty = React.forwardRef<
  HTMLTableCellElement,
  React.TdHTMLAttributes<HTMLTableCellElement> & {
    colSpan: number;
    title: string;
    description?: React.ReactNode;
    /** 与 EmptyState.icon 同型: lucide 图标 */
    icon?: LucideIcon;
    action?: React.ReactNode;
  }
>(({ colSpan, title, description, icon, action, className, ...props }, ref) => (
  <td
    ref={ref}
    colSpan={colSpan}
    className={cn("p-0 align-middle", className)}
    {...props}
  >
    <EmptyState
      icon={icon}
      title={title}
      description={description}
      action={action}
      size="md"
    />
  </td>
));
TableEmpty.displayName = "TableEmpty";

export {
  Table,
  TableHeader,
  TableBody,
  TableFooter,
  TableHead,
  TableRow,
  TableCell,
  TableCaption,
  TableEmpty,
};