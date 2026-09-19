"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { signIn } from "next-auth/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent } from "@/components/ui/card";

// ============================================
// 登录表单 (2026-09-19 P2: 账号/手机号 + 密码)
//
// - identifier: 登录名 (如 admin) 或 手机号
// - 邀请制: 账号由管理员开通 (scripts/create-admin.ts / import-users.ts)
// - 后端校验: src/lib/auth/credentials.ts (scrypt + 5 次/分钟限流)
// - 自助改密: Flutter「我的 → 修改密码」/ PATCH /api/me/password
// ============================================

export function LoginForm() {
  const router = useRouter();
  const [identifier, setIdentifier] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);

    const result = await signIn("credentials", {
      identifier: identifier.trim(),
      password,
      redirect: false,
    });

    if (result?.error) {
      setError("账号或密码错误, 或尝试过于频繁");
      setLoading(false);
      return;
    }

    router.push("/admin");
    router.refresh();
  }

  return (
    <Card>
      <CardContent className="pt-6">
        <form onSubmit={handleLogin} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="identifier">账号 / 手机号</Label>
            <Input
              id="identifier"
              type="text"
              placeholder="admin 或 13800138000"
              value={identifier}
              onChange={(e) => setIdentifier(e.target.value)}
              autoComplete="username"
              autoFocus
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">密码</Label>
            <Input
              id="password"
              type="password"
              placeholder="请输入密码"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              autoComplete="current-password"
            />
          </div>
          {error && (
            <p className="text-sm text-destructive text-center">{error}</p>
          )}
          <Button
            type="submit"
            disabled={loading || !identifier.trim() || !password}
            className="w-full"
          >
            {loading ? "登录中..." : "登录"}
          </Button>
          <p className="text-xs text-muted-foreground text-center">
            账号由管理员开通; 忘记密码请联系管理员重置
          </p>
        </form>
      </CardContent>
    </Card>
  );
}
