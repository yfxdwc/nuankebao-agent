// force-dynamic for build (sandbox EAGAIN on static prerender)
import { LoginForm } from "@/components/auth/login-form";

export const dynamic = "force-dynamic";

export default function LoginPage() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/40 p-4">
      <div className="w-full max-w-md space-y-6">
        <div className="text-center space-y-2">
          <h1 className="text-3xl font-bold tracking-tight text-primary">
            暖客宝
          </h1>
          <p className="text-sm text-muted-foreground">
            大健康销售 CRM · 登录
          </p>
        </div>
        <LoginForm />
        <p className="text-center text-xs text-muted-foreground">
          v0.1 · Phase 1 W1 · 项目骨架
        </p>
      </div>
    </div>
  );
}