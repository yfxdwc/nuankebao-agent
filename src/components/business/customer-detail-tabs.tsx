"use client";

import { useState } from "react";
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { Section } from "@/components/ui/section";
import { Phone, Pencil, Heart, MessageCircle, Plus } from "lucide-react";
import { formatDate } from "@/lib/utils";
import { cn } from "@/lib/utils";

/**
 * 暖客宝 客户详情 Tabs (W16)
 *
 * 移动端: 顶部 3 tab 切换, 内容区只有当前 tab (避免长页滚动)
 * 桌面端: 也用 tab, 但每个 tab 内是 1-2 列
 *
 * B3 设计原则:
 *   - sticky tab 头, 滚动不丢
 *   - active 态走 brand 色 (border-b-2 + text-brand)
 *   - 触摸 ≥44px
 *   - 同质列表 (养生 / 联系) 用 divide-y 分隔线, 不画 Card (原则 4)
 */

type Gender = "F" | "M" | "U" | null | undefined;

/**
 * 归属五态 (Phase C §3.4 / 客户标识体系 v1) — 与 list 同一口径.
 *   mine        : 静默 (不出标签, 不与"我的客户"同色铺满)
 *   subordinate : 别人的客户 (我的下层 user 归属; 详情页 Phase D 后才有 ownerName)
 *   upline      : 上级推送的客户 (Phase D 落地)
 *   none        : 无归属
 *   other       : 他人客户 (scope 漏检告警)
 */
type Ownership = "mine" | "subordinate" | "upline" | "other" | "none";

/** 客户来源 (Phase A migration 0026; Phase C §1 维度 6). */
type AcquireSource = "friend" | "referral" | "cold_visit" | "ground_promo" | null;

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
  /**
   * ★ 归属五态 (Phase C); 老后端不返回 → 详情页 ownerName 兜底 "" 不显示 .
   *   单一真相源 = src/lib/customer/identity.ts.
   */
  ownership?: Ownership;
  /**
   * ★ 客户来源 (Phase C §1 维度 6 + §4.2 L4, D6).
   *   null / undefined = 未填写 → 显示"未填写".
   *   referral 时 referrerName 必填 (后端 zod refine 校验, §5 M3).
   */
  source?: { kind: AcquireSource; referrerName: string | null };
}

/**
 * 归属 badge 文案 (Phase C §4.2, 详情页用 — 与列表同一口径)
 *   mine       → null (静默)
 *   subordinate → "下级的客户 · X"
 *   upline     → "上级推送 · X"
 *   none       → "无归属"
 *   other      → "他人客户"
 */
function ownershipBadgeLabel(
  o: Ownership | undefined,
  ownerName?: string | null
): { label: string; className: string } | null {
  switch (o) {
    case "mine":
    case undefined:
      return null;
    case "subordinate":
      return {
        label: ownerName ? `下级的客户 · ${ownerName}` : "下级的客户",
        className: "bg-info-light text-info",
      };
    case "upline":
      return {
        label: ownerName ? `上级推送 · ${ownerName}` : "上级推送",
        className: "bg-brand-light text-brand",
      };
    case "none":
      return {
        label: "无归属",
        className: "bg-surface-subtle text-content-secondary",
      };
    case "other":
      return {
        label: "他人客户",
        className: "bg-warning-light text-warning",
      };
  }
}

/** 来源短词 (Phase C §1 维度 6); null → 未填写. */
const ACQUIRE_SOURCE_LABELS: Record<Exclude<AcquireSource, null>, string> = {
  friend: "亲友",
  referral: "转介绍",
  cold_visit: "陌生拜访",
  ground_promo: "地推",
};

function acquireSourceLabel(s: AcquireSource | undefined): string {
  if (!s) return "未填写";
  return ACQUIRE_SOURCE_LABELS[s];
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
    <div className="space-y-section-y">
      {/* Tab 头 (sticky) */}
      <div className="sticky top-12 z-20 -mx-3 md:mx-0 bg-background border-b border-divider">
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
                  "flex-1 md:flex-none md:px-6 flex items-center justify-center gap-1.5 py-3 min-h-tap-compact text-body-lg font-medium border-b-2 transition-colors",
                  isActive
                    ? "border-brand text-brand"
                    : "border-transparent text-content-secondary hover:text-content-primary"
                )}
              >
                <Icon className="h-4 w-4" />
                {t.label}
                <span
                  className={cn(
                    "ml-1 inline-flex items-center justify-center min-w-badge h-4 px-1 rounded-full text-micro font-semibold tabular-nums",
                    isActive ? "bg-brand-surface text-brand" : "bg-surface-subtle text-content-secondary"
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
  // ★ 归属 badge (Phase C §4.2 L2 五态, 与列表同口径)
  //   详情页 = 老板视角: "她的客户归谁管"比列表更重要 —— 总是显示 (mine 也加个静默标也行,
  //   但设计拍"默认静默、异常态显形", mine 也按静默, 避免同色铺满).
  //   详情页现不传 ownerName (Phase D 后端 src/view/[id] 接入 identity.ts 后带).
  const own = ownershipBadgeLabel(customer.ownership);
  // ★ 来源 (Phase C §1 维度 6 + D6): 仅在详情页"档案/管理区"显示,
  //   列表**不**显示 (D6 硬约束); referral 时展开介绍人 (zod refine 校验)
  const src = customer.source;
  const sourceKind = src?.kind ?? null;
  const referrerName = src?.referrerName ?? null;
  return (
    <div className="space-y-section-y">
      {/* 基本信息 (Section, 无 Card 边框) */}
      <Section title="基本信息">
        <div className="flex items-start gap-3">
          <div className="h-12 w-12 rounded-full bg-brand-surface text-brand flex items-center justify-center text-title-sm font-semibold shrink-0">
            {customer.name.slice(0, 1)}
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap">
              <span className="text-title-sm font-semibold text-content-primary">
                {customer.name}
              </span>
              <span className="text-caption text-content-tertiary">
                {customer.gender === "F" ? "女" : customer.gender === "M" ? "男" : "-"}
              </span>
              {/* 归属 badge (五态; mine 静默) */}
              {own && (
                <span
                  data-testid="ownership-badge"
                  className={`inline-flex items-center rounded-full px-2 py-0.5 text-caption font-medium shrink-0 ${own.className}`}
                >
                  {own.label}
                </span>
              )}
            </div>
            <p className="text-caption text-content-secondary mt-0.5 tabular-nums">
              注册于 {formatDate(customer.createdAt)}
            </p>
          </div>
        </div>
        <div className="grid gap-2 sm:grid-cols-2 pt-section-y border-t border-divider">
          <div className="flex items-center gap-2 text-body-lg">
            <Phone className="h-3.5 w-3.5 text-content-secondary" />
            <a href={`tel:${customer.phone}`} className="text-brand tabular-nums">
              {customer.phone}
            </a>
          </div>
          {customer.birthYear && (
            <div className="text-body-lg">
              <span className="text-content-secondary">出生年: </span>
              <span className="tabular-nums">{customer.birthYear}</span>
            </div>
          )}
        </div>
        {/* ★ 客户来源行 (Phase C §4.2 L4, D6).
            详情页"档案/管理区"显示; 列表不显示.
            referral 时展开"介绍人: XXX". */}
        <div className="grid gap-2 sm:grid-cols-2 pt-section-y border-t border-divider">
          <div className="text-body-lg">
            <span className="text-content-secondary">客户来源: </span>
            <span className="text-content-primary">{acquireSourceLabel(sourceKind)}</span>
          </div>
          {sourceKind === "referral" && (
            <div className="text-body-lg">
              <span className="text-content-secondary">介绍人: </span>
              <span className="text-content-primary">
                {referrerName?.trim() ? referrerName : "—"}
              </span>
            </div>
          )}
        </div>
      </Section>

      {/* 健康标签 */}
      {customer.healthTags.length > 0 && (
        <Section title="健康标签">
          <div className="flex flex-wrap gap-1.5">
            {customer.healthTags.map((tag) => (
              <span
                key={tag}
                className="text-caption text-content-secondary bg-surface-subtle px-2 py-1 rounded"
              >
                {tag}
              </span>
            ))}
          </div>
        </Section>
      )}

      {/* 既往病史 */}
      {customer.diseaseHistory && (
        <Section title="既往病史 / 过敏">
          <p className="text-body-lg text-content-primary whitespace-pre-wrap">
            {customer.diseaseHistory}
          </p>
        </Section>
      )}

      {/* 备注 */}
      {customer.notes && (
        <Section title="备注">
          <p className="text-body-lg text-content-primary whitespace-pre-wrap">
            {customer.notes}
          </p>
        </Section>
      )}

      {/* 编辑按钮 */}
      <div className="pt-2">
        <Button asChild>
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
    <div className="space-y-section-y">
      {records.items.length === 0 ? (
        <div className="py-10 text-center text-body text-content-secondary">
          暂无养生记录
        </div>
      ) : (
        // B3: 同质列表 = divide-y 分隔线, 无 Card 边框
        <ul className="divide-y divide-divider">
          {records.items.map((r) => (
            <li key={r.id}>
              <Link
                href={`/admin/wellness-records/${r.id}`}
                className="block px-1 py-3 hover:bg-surface-subtle transition-colors active:bg-surface-sunken min-h-control-lg"
              >
                <div className="flex items-baseline justify-between gap-2">
                  <span className="text-body-lg font-medium text-content-primary">
                    {formatDate(r.serviceDate)}
                  </span>
                  <span className="text-caption text-content-tertiary tabular-nums shrink-0">
                    {serviceMap[r.serviceItemId] ?? `项目 ${r.serviceItemId}`}
                  </span>
                </div>
                {r.bodyPartIds.length > 0 && (
                  <div className="flex flex-wrap gap-1 mt-1.5">
                    {r.bodyPartIds.map((id) => (
                      <span
                        key={id}
                        className="text-caption text-content-secondary bg-surface-subtle px-1.5 py-0.5 rounded"
                      >
                        {bodyPartMap[id] ?? `#${id}`}
                      </span>
                    ))}
                  </div>
                )}
                {r.customerFeedback && (
                  <p className="text-caption text-content-tertiary line-clamp-2 mt-1 italic">
                    &ldquo;{r.customerFeedback}&rdquo;
                  </p>
                )}
              </Link>
            </li>
          ))}
        </ul>
      )}

      <Button asChild className="bg-danger hover:bg-danger">
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
      <div className="py-10 text-center text-body text-content-secondary">
        暂无联系记录
      </div>
    );
  }
  return (
    // B3: 同质列表用 divide-y 分隔线, 不要再套 bg-card border (反 SaaS 观感)
    <ol className="relative ml-3 md:ml-4">
      {/* 时间线竖线 (绝对定位) */}
      <div
        className="absolute left-2.5 md:left-3 top-3 bottom-3 w-px bg-divider"
        aria-hidden="true"
      />
      {interactions.map((i) => {
        const time = new Date(i.createdAt)
          .toISOString()
          .split("T")[1]
          ?.slice(0, 5);
        return (
          <li key={i.id} className="relative pl-8 md:pl-10 py-3 first:pt-0 last:pb-0">
            <div className="absolute left-0 top-3 h-5 w-5 md:h-6 md:w-6 rounded-full bg-brand-surface text-brand flex items-center justify-center ring-2 ring-background">
              <MessageCircle className="h-3 w-3" />
            </div>
            <div className="flex items-center justify-between gap-2">
              <span className="text-body-lg text-content-primary">
                {TYPE_LABELS[i.type] ?? i.type}
              </span>
              <span className="text-caption text-content-tertiary tabular-nums">
                {formatDate(i.createdAt)} {time}
              </span>
            </div>
            {i.summary ? (
              <p className="text-body text-content-primary mt-1">{i.summary}</p>
            ) : (
              <p className="text-caption text-content-tertiary mt-1 italic">
                (无内容记录)
              </p>
            )}
          </li>
        );
      })}
    </ol>
  );
}