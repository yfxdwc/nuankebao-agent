// ============================================
// DevPageHeader — 7 个 /dev/* 子页通用 header (DRY 重构, v0.1.4)
//
// 抽取前: 7 个 page.tsx 各自复制 22 行 header 代码
// 抽取后: 1 行调用, 改一处生效 7 处
// ============================================

import Link from "next/link";
import { ArrowLeft, type LucideIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

interface DevBadge {
  label: string;
  variant?: "outline" | "secondary" | "destructive" | "default";
}

interface DevPageHeaderProps {
  backHref: string;
  backLabel: string;
  icon: LucideIcon;
  title: string;
  description: React.ReactNode;
  badges?: (string | DevBadge)[];
}

export function DevPageHeader({
  backHref,
  backLabel,
  icon: Icon,
  title,
  description,
  badges = [],
}: DevPageHeaderProps) {
  return (
    <>
      <Button variant="ghost" size="sm" asChild className="mb-3">
        <Link href={backHref}>
          <ArrowLeft className="h-4 w-4 mr-1" />
          {backLabel}
        </Link>
      </Button>

      <div className="flex items-center gap-2 mb-2">
        <Icon className="h-7 w-7 text-primary" />
        <h1 className="text-3xl font-bold text-foreground">{title}</h1>
      </div>
      <p className="text-muted-foreground">{description}</p>

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
    </>
  );
}
