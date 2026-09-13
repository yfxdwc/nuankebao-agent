import Link from "next/link";
import { Button } from "@/components/ui/button";
import { ArrowLeft } from "lucide-react";

export default function ApkLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="space-y-4">
      <Button asChild variant="ghost" size="sm">
        <Link href="/admin">
          <ArrowLeft className="h-4 w-4 mr-2" />
          返回 admin
        </Link>
      </Button>
      {children}
    </div>
  );
}