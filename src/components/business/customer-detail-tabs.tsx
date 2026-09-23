"use client";

import { useState } from "react";
import Link from "next/link";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Phone, Pencil, Heart, MessageCircle, Plus } from "lucide-react";
import { formatDate } from "@/lib/utils";
import { cn } from "@/lib/utils";

/**
 * 暖客宝 客户详情 Tabs (W16)
 *
 * 移动端: 顶部 3 tab 切换, 内容区只有当前 tab (避免长页滚动)
 * 桌面端: 也用 tab, 但每个 tab 内是 1-2 列
 *
 * 设计原则:
 *   - sticky tab 头, 滚动不丢
 *   - 暖绿 active 态
 *   - 触摸 ≥44px
 */

type Gender = "F" | "M" | "U" | null | undefined;

interface CustomerLite {
  id: string;
  name: string;
  phone: string;
  gender: Gender;
  birthYear: number | null;
  healthTags: string[];
  diseaseHistory: string | null;
  notes: string | null;
  createdAt: Date | string;
}

interface WellnessRecordLite {
  id: string;
  serviceDate: string;
  serviceItemId: string;
  bodyPartIds: string[];
  customerFeedback: string | null;
}

interface InteractionLite {
  id: string;
  type: string;
  summary: string | null;
  createdAt: Date | string;
}

interface Props {
  customer: CustomerLite;
  wellnessRecords: { items: WellnessRecordLite[]; total: number };
  interactions: InteractionLite[];
  serviceMap: Record<string, string>;
  bodyPartMap: Record<string, string>;
}

const TABS = [
  { value: "profile", label: "档案", icon: Phone },
  { value: "wellness", label: "养生", icon: Heart },
  { value: "interactions", label: "联系", icon: MessageCircle },
] as const;

const TYPE_LABELS: Record<string, string> = {
  phone: "电话",
  wechat: "微信",
  visit: "到店",
  holiday_greeting: "节日问候",
  other: "其他",
};

export function CustomerDetailTabs({
  customer,
  wellnessRecords,
  interactions,
  serviceMap,
  bodyPartMap,
}: Props) {
  const [tab, setTab] = useState<(typeof TABS)[number]["value"]>("profile");

  return (
    <div className="space-y-3 md:space-y-6">
      {/* Tab 头 (sticky) */}
      <div className="sticky top-12 md:top-14 z-20 -mx-3 md:mx-0 bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/80 border-b md:border-b-0">
        <div className="flex px-3 md:px-0" role="tablist">
          {TABS.map((t) => {
            const Icon = t.icon;
            const isActive = tab === t.value;
            return (
              <button
                key={t.value}
                type="button"
                role="tab"
                aria-selected={isActive}
                onClick={() => setTab(t.value)}
                className={cn(
                  "flex-1 md:flex-none md:px-6 flex items-center justify-center gap-1.5 py-3 min-h-tap-compact text-sm font-medium border-b-2 transition-colors",
                  isActive
                    ? "border-primary text-primary"
                    : "border-transparent text-muted-foreground hover:text-foreground"
                )}
              >
                <Icon className="h-4 w-4" />
                {t.label}
                <span
                  className={cn(
                    "ml-1 inline-flex items-center justify-center min-w-badge h-4 px-1 rounded-full text-xxs font-semibold",
                    isActive ? "bg-primary/10 text-primary" : "bg-muted text-muted-foreground"
                  )}
                >
                  {t.value === "profile" && "·"}
                  {t.value === "wellness" && wellnessRecords.total}
                  {t.value === "interactions" && interactions.length}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Tab 内容 */}
      {tab === "profile" && <ProfileTab customer={customer} />}
      {tab === "wellness" && (
        <WellnessTab
          customerId={customer.id}
          records={wellnessRecords}
          serviceMap={serviceMap}
          bodyPartMap={bodyPartMap}
        />
      )}
      {tab === "interactions" && <InteractionsTab interactions={interactions} />}
    </div>
  );
}

function ProfileTab({ customer }: { customer: CustomerLite }) {
  return (
    <div className="space-y-2 md:space-y-4">
      {/* 基本信息 */}
      <Card>
        <CardContent className="p-3 md:p-6 space-y-3">
          <div className="flex items-start gap-3">
            <div className="h-12 w-12 md:h-16 md:w-16 rounded-full bg-primary/10 text-primary flex items-center justify-center text-xl md:text-2xl font-medium shrink-0">
              {customer.name.slice(0, 1)}
            </div>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <h2 className="text-lg md:text-2xl font-bold">{customer.name}</h2>
                <Badge variant="outline" className="text-xxs">
                  {customer.gender === "F" ? "女" : customer.gender === "M" ? "男" : "-"}
                </Badge>
              </div>
              <p className="text-xs text-muted-foreground mt-1">
                注册于 {formatDate(customer.createdAt)}
              </p>
            </div>
          </div>
          <div className="grid gap-2 sm:grid-cols-2 pt-2 border-t">
            <div className="flex items-center gap-2 text-sm">
              <Phone className="h-3.5 w-3.5 text-muted-foreground" />
              <a href={`tel:${customer.phone}`} className="text-primary">
                {customer.phone}
              </a>
            </div>
            {customer.birthYear && (
              <div className="text-sm">
                <span className="text-muted-foreground">出生年: </span>
                {customer.birthYear}
              </div>
            )}
          </div>
        </CardContent>
      </Card>

      {/* 健康标签 */}
      {customer.healthTags.length > 0 && (
        <Card>
          <CardContent className="p-3 md:p-6">
            <h3 className="text-xs md:text-sm font-medium text-muted-foreground mb-2">
              健康标签
            </h3>
            <div className="flex flex-wrap gap-1.5">
              {customer.healthTags.map((tag) => (
                <Badge key={tag} variant="secondary" className="text-xs">
                  {tag}
                </Badge>
              ))}
            </div>
          </CardContent>
        </Card>
      )}

      {/* 既往病史 */}
      {customer.diseaseHistory && (
        <Card>
          <CardContent className="p-3 md:p-6">
            <h3 className="text-xs md:text-sm font-medium text-muted-foreground mb-2">
              既往病史 / 过敏
            </h3>
            <p className="text-sm whitespace-pre-wrap">{customer.diseaseHistory}</p>
          </CardContent>
        </Card>
      )}

      {/* 备注 */}
      {customer.notes && (
        <Card>
          <CardContent className="p-3 md:p-6">
            <h3 className="text-xs md:text-sm font-medium text-muted-foreground mb-2">
              备注
            </h3>
            <p className="text-sm whitespace-pre-wrap">{customer.notes}</p>
          </CardContent>
        </Card>
      )}

      {/* 编辑按钮 (移动底部大按钮) */}
      <div className="pt-2">
        <Button asChild className="w-full md:w-auto h-11">
          <Link href={`/admin/customers/${customer.id}/edit`}>
            <Pencil className="h-4 w-4 mr-2" />
            编辑客户档案
          </Link>
        </Button>
      </div>
    </div>
  );
}

function WellnessTab({
  customerId,
  records,
  serviceMap,
  bodyPartMap,
}: {
  customerId: string;
  records: { items: WellnessRecordLite[]; total: number };
  serviceMap: Record<string, string>;
  bodyPartMap: Record<string, string>;
}) {
  return (
    <div className="space-y-2 md:space-y-3">
      {records.items.length === 0 ? (
        <Card>
          <CardContent className="py-8 md:py-12 text-center text-muted-foreground text-sm">
            暂无养生记录
          </CardContent>
        </Card>
      ) : (
        records.items.map((r) => (
          <Link
            key={r.id}
            href={`/admin/wellness-records/${r.id}`}
            className="block active:scale-[0.99] transition-transform"
          >
            <Card className="hover:shadow-md transition-shadow cursor-pointer">
              <CardContent className="p-3 md:p-4">
                <div className="flex items-center justify-between gap-2">
                  <h3 className="text-sm md:text-base font-medium">
                    {formatDate(r.serviceDate)}
                  </h3>
                  <Badge variant="outline" className="text-xxs shrink-0">
                    {serviceMap[r.serviceItemId] ?? `项目 ${r.serviceItemId}`}
                  </Badge>
                </div>
                {r.bodyPartIds.length > 0 && (
                  <div className="flex flex-wrap gap-1 mt-1.5">
                    {r.bodyPartIds.map((id) => (
                      <Badge key={id} variant="secondary" className="text-xxs">
                        {bodyPartMap[id] ?? `#${id}`}
                      </Badge>
                    ))}
                  </div>
                )}
                {r.customerFeedback && (
                  <p className="text-xs text-muted-foreground line-clamp-2 mt-1.5 italic">
                    "{r.customerFeedback}"
                  </p>
                )}
              </CardContent>
            </Card>
          </Link>
        ))
      )}

      <Button
        asChild
        className="w-full md:w-auto h-11 bg-danger hover:bg-danger"
      >
        <Link href={`/admin/wellness-records/new?customerId=${customerId}`}>
          <Plus className="h-4 w-4 mr-2" />
          新增养生记录
        </Link>
      </Button>
    </div>
  );
}

function InteractionsTab({ interactions }: { interactions: InteractionLite[] }) {
  if (interactions.length === 0) {
    return (
      <Card>
        <CardContent className="py-8 md:py-12 text-center text-muted-foreground text-sm">
          暂无联系记录
        </CardContent>
      </Card>
    );
  }
  return (
    <ol className="relative space-y-2 md:space-y-3 ml-3 md:ml-4">
      <div
        className="absolute left-2.5 md:left-3 top-3 bottom-3 w-px bg-border"
        aria-hidden="true"
      />
      {interactions.map((i) => {
        const time = new Date(i.createdAt)
          .toISOString()
          .split("T")[1]
          ?.slice(0, 5);
        return (
          <li key={i.id} className="relative pl-8 md:pl-10">
            <div className="absolute left-0 top-1.5 h-5 w-5 md:h-6 md:w-6 rounded-full bg-primary/10 text-primary flex items-center justify-center ring-2 ring-background">
              <MessageCircle className="h-3 w-3" />
            </div>
            <div className="bg-card border rounded-lg p-2.5 md:p-3">
              <div className="flex items-center justify-between gap-2">
                <Badge variant="outline" className="text-xxs">
                  {TYPE_LABELS[i.type] ?? i.type}
                </Badge>
                <span className="text-xxs text-muted-foreground tabular-nums">
                  {formatDate(i.createdAt)} {time}
                </span>
              </div>
              {i.summary ? (
                <p className="text-xs mt-1.5">{i.summary}</p>
              ) : (
                <p className="text-xxs text-muted-foreground mt-1 italic">
                  (无内容记录)
                </p>
              )}
            </div>
          </li>
        );
      })}
    </ol>
  );
}
