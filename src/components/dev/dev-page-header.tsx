// ============================================
// DevPageHeader — /admin/dev/* 子页通用 header (DRY 重构, v0.1.4)
//
// v0.1.4 主人 2026-09-14 拍板 (master-decide):
// 开发工具子模块以"顶部 tab 导航 + 内容区"方式呈现 (components/dev/dev-tabs-nav.tsx).
// 子页用 DevPageHeader 显示 icon + title + description + badges, 不再需要 back 按钮
// (顶部 tab 永远显示, 不需要 back).
// ============================================

import { type LucideIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";

interface DevBadge {
  label: string;
  variant?: "outline" | "secondary" | "destructive" | "default";
}

interface DevPageHeaderProps {
  /** @deprecated v0.1.4 起顶部 tab 替代 back 按钮, 此 prop 保留兼容但不再渲染 */
  backHref?: string;
  /** @deprecated 同 backHref */
  backLabel?: string;
  icon: LucideIcon;
  title: string;
  description: React.ReactNode;
  badges?: (string | DevBadge)[];
}

export function DevPageHeader({
  backHref: _backHref,
  backLabel: _backLabel,
  icon: Icon,
  title,
  description,
  badges = [],
}: DevPageHeaderProps) {
  return (
    <div className="mb-4 md:mb-6">
      <div className="flex items-center gap-2 mb-2">
        <Icon className="h-6 w-6 md:h-7 md:w-7 text-primary" />
        <h1 className="text-2xl md:text-3xl font-bold text-foreground">
          {title}
        </h1>
      </div>
      <p className="text-sm md:text-base text-muted-foreground">
        {description}
      </p>

      {badges.length > 0 && (
        <div className="mt-3 flex gap-2 flex-wrap">
          {badges.map((b, i) => {
            const badge: DevBadge =
              typeof b === "string" ? { label: b } : b;
            return (
              <Badge key={i} variant={badge.variant ?? "secondary"}>
                {badge.label}
              </Badge>
            );
          })}
        </div>
      )}
    </div>
  );
}