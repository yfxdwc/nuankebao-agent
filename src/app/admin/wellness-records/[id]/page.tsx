import { notFound } from "next/navigation";
import Link from "next/link";
import {
  getWellnessRecordById,
} from "@/lib/db/queries/wellness-record";
import { getCustomerById } from "@/lib/db/queries/customer";
import { listAllDictionaries } from "@/lib/db/queries/dictionary";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
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
  const bodyPartNames = record.bodyPartIds
    .map((id) => dict.bodyParts.find((b) => b.id === id)?.name ?? `#${id}`)
    .join("、");

  return (
    <div className="space-y-6 max-w-3xl">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Button variant="ghost" size="sm" asChild>
            <Link href="/admin/wellness-records">
              <ArrowLeft className="h-4 w-4" />
            </Link>
          </Button>
          <div>
            <h1 className="text-3xl font-bold tracking-tight">{record.serviceDate}</h1>
            <p className="text-sm text-muted-foreground">
              {serviceName}
            </p>
          </div>
        </div>
        <Button asChild>
          <Link href={`/admin/wellness-records/${record.id}/edit`}>
            <Pencil className="h-4 w-4 mr-2" />
            编辑
          </Link>
        </Button>
      </div>

      {customer && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">客户</CardTitle>
          </CardHeader>
          <CardContent>
            <Link
              href={`/admin/customers/${customer.id}`}
              className="text-primary hover:underline"
            >
              {customer.name} · {customer.phone}
            </Link>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">身体部位</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="flex flex-wrap gap-2">
            {record.bodyPartIds.map((id) => (
              <Badge key={id} variant="secondary">
                {dict.bodyParts.find((b) => b.id === id)?.name ?? `#${id}`}
              </Badge>
            ))}
          </div>
        </CardContent>
      </Card>

      {record.productUsages.length > 0 && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">使用耗材</CardTitle>
          </CardHeader>
          <CardContent>
            <ul className="space-y-1 text-sm">
              {record.productUsages.map((p, idx) => {
                const product = dict.products.find((prod) => prod.id === p.productId);
                return (
                  <li key={idx}>
                    {product?.name ?? `#${p.productId}`} · 用量 {p.quantity ?? "-"}{" "}
                    {product?.unit}
                  </li>
                );
              })}
            </ul>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">状态对比</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="grid gap-3 sm:grid-cols-2 text-sm">
            <div>
              <p className="font-medium text-muted-foreground">理疗前</p>
              <ul className="mt-1 space-y-0.5">
                {Object.entries(record.preCondition).map(([k, v]) => (
                  <li key={k}>
                    {k}: {String(v)}
                  </li>
                ))}
                {Object.keys(record.preCondition).length === 0 && (
                  <li className="text-muted-foreground">无</li>
                )}
              </ul>
            </div>
            <div>
              <p className="font-medium text-muted-foreground">理疗后</p>
              <ul className="mt-1 space-y-0.5">
                {Object.entries(record.postCondition).map(([k, v]) => (
                  <li key={k}>
                    {k}: {String(v)}
                  </li>
                ))}
                {Object.keys(record.postCondition).length === 0 && (
                  <li className="text-muted-foreground">无</li>
                )}
              </ul>
            </div>
          </div>
        </CardContent>
      </Card>

      {record.processNote && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">理疗过程</CardTitle>
          </CardHeader>
          <CardContent className="text-sm whitespace-pre-wrap">
            {record.processNote}
          </CardContent>
        </Card>
      )}

      {record.customerFeedback && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">客户反馈</CardTitle>
          </CardHeader>
          <CardContent className="text-sm whitespace-pre-wrap">
            {record.customerFeedback}
          </CardContent>
        </Card>
      )}

      {record.nextAdviceDate && (
        <Card>
          <CardHeader>
            <CardTitle className="text-base">下次建议</CardTitle>
          </CardHeader>
          <CardContent className="text-sm">
            建议下次到店日期: <strong>{record.nextAdviceDate}</strong>
          </CardContent>
        </Card>
      )}
    </div>
  );
}