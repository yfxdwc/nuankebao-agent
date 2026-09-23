import { notFound } from "next/navigation";
import Link from "next/link";
import {
  getWellnessRecordById,
} from "@/lib/db/queries/wellness-record";
import { getCustomerById } from "@/lib/db/queries/customer";
import { listAllDictionaries } from "@/lib/db/queries/dictionary";
import { PageHeader } from "@/components/ui/page-header";
import { Section } from "@/components/ui/section";
import { StatGroup, StatRow } from "@/components/ui/stat-row";
import { Button } from "@/components/ui/button";
import { ArrowLeft, Pencil } from "lucide-react";

export const dynamic = "force-dynamic";

export default async function WellnessRecordDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const record = await getWellnessRecordById(BigInt(id));
  if (!record) notFound();

  const [customer, dict] = await Promise.all([
    getCustomerById(BigInt(record.customerId)),
    listAllDictionaries(),
  ]);

  const serviceName =
    dict.serviceItems.find((s) => s.id === record.serviceItemId)?.name ?? `项目 ${record.serviceItemId}`;

  return (
    <div className="space-y-section-y max-w-3xl">
      <PageHeader
        title={record.serviceDate}
        description={serviceName}
        actions={
          <Button asChild variant="outline">
            <Link href={`/admin/wellness-records/${record.id}/edit`}>
              <Pencil className="h-4 w-4 mr-2" />
              编辑
            </Link>
          </Button>
        }
      >
        {/* 返回按钮 (放在 PageHeader children 区, 不在主标题区抢位) */}
        <Button variant="ghost" size="sm" asChild className="-ml-3">
          <Link href="/admin/wellness-records">
            <ArrowLeft className="h-4 w-4 mr-1" />
            返回列表
          </Link>
        </Button>
      </PageHeader>

      {customer && (
        <Section title="客户">
          <Link
            href={`/admin/customers/${customer.id}`}
            className="text-body-lg text-brand hover:underline"
          >
            {customer.name} · {customer.phone}
          </Link>
        </Section>
      )}

      {record.bodyPartIds.length > 0 && (
        <Section title="身体部位">
          <div className="flex flex-wrap gap-1.5">
            {record.bodyPartIds.map((id) => (
              <span
                key={id}
                className="text-caption text-content-secondary bg-surface-subtle px-2 py-1 rounded"
              >
                {dict.bodyParts.find((b) => b.id === id)?.name ?? `#${id}`}
              </span>
            ))}
          </div>
        </Section>
      )}

      {record.productUsages.length > 0 && (
        <Section title="使用耗材">
          <ul className="divide-y divide-divider">
            {record.productUsages.map((p, idx) => {
              const product = dict.products.find((prod) => prod.id === p.productId);
              return (
                <li key={idx} className="py-2 flex items-center justify-between gap-2">
                  <span className="text-body-lg text-content-primary">
                    {product?.name ?? `#${p.productId}`}
                  </span>
                  <span className="text-caption text-content-tertiary tabular-nums shrink-0">
                    用量 {p.quantity ?? "-"} {product?.unit}
                  </span>
                </li>
              );
            })}
          </ul>
        </Section>
      )}

      {/* 状态对比: StatGroup (左 label / 右 value; 字段多时不挤) */}
      <Section title="状态对比">
        <div className="grid gap-section-y sm:grid-cols-2">
          <StatGroup title="理疗前">
            {Object.keys(record.preCondition).length === 0 ? (
              <StatRow label="—" value="无" />
            ) : (
              Object.entries(record.preCondition).map(([k, v]) => (
                <StatRow key={k} label={k} value={String(v)} />
              ))
            )}
          </StatGroup>
          <StatGroup title="理疗后">
            {Object.keys(record.postCondition).length === 0 ? (
              <StatRow label="—" value="无" />
            ) : (
              Object.entries(record.postCondition).map(([k, v]) => (
                <StatRow key={k} label={k} value={String(v)} />
              ))
            )}
          </StatGroup>
        </div>
      </Section>

      {record.processNote && (
        <Section title="理疗过程">
          <p className="text-body-lg text-content-primary whitespace-pre-wrap">
            {record.processNote}
          </p>
        </Section>
      )}

      {record.customerFeedback && (
        <Section title="客户反馈">
          <p className="text-body-lg text-content-primary whitespace-pre-wrap">
            {record.customerFeedback}
          </p>
        </Section>
      )}

      {record.nextAdviceDate && (
        <Section title="下次建议">
          <StatRow label="建议下次到店" value={record.nextAdviceDate} tone="brand" />
        </Section>
      )}
    </div>
  );
}