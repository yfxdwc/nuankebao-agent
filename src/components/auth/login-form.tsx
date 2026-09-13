"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { signIn } from "next-auth/react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent } from "@/components/ui/card";

// ============================================
// W1 登录表单 (开发期 mock 验证码 123456)
//
// W2 完整接入:
//   - 发送验证码走 /api/auth/send-code (阿里云 SMS 网关)
//   - 60s 倒计时
//   - 限流 (同手机号 5 次/小时, 同 IP 10 次/小时)
//
// W3 接入真实 Auth.js 验证 + Drizzle 查询
// ============================================

export function LoginForm() {
  const router = useRouter();
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [step, setStep] = useState<"phone" | "code">("phone");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSendCode() {
    setLoading(true);
    setError(null);
    // W1 占位: 模拟发送, 实际 W2 走阿里云 SMS
    await new Promise((r) => setTimeout(r, 500));
    setStep("code");
    setLoading(false);
  }

  async function handleLogin(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError(null);

    const result = await signIn("credentials", {
      phone,
      code,
      redirect: false,
    });

    if (result?.error) {
      setError("验证码错误,请重试");
      setLoading(false);
      return;
    }

    router.push("/admin");
    router.refresh();
  }

  if (step === "phone") {
    return (
      <Card>
        <CardContent className="pt-6 space-y-4">
          <div className="space-y-2">
            <Label htmlFor="phone">手机号</Label>
            <Input
              id="phone"
              type="tel"
              placeholder="请输入手机号"
              value={phone}
              onChange={(e) => setPhone(e.target.value.replace(/\D/g, ""))}
              maxLength={11}
              autoFocus
            />
          </div>
          <Button
            onClick={handleSendCode}
            disabled={loading || phone.length !== 11}
            className="w-full"
          >
            {loading ? "发送中..." : "发送验证码"}
          </Button>
          {error && (
            <p className="text-sm text-destructive text-center">{error}</p>
          )}
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardContent className="pt-6 space-y-4">
        <form onSubmit={handleLogin} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="code">验证码</Label>
            <Input
              id="code"
              type="text"
              placeholder="6 位验证码"
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ""))}
              maxLength={6}
              autoFocus
            />
            <p className="text-xs text-muted-foreground">
              已发送至 +86 {phone.slice(0, 3)}****{phone.slice(7)}
              <br />
              <span className="text-primary">开发期验证码: 123456</span>
            </p>
          </div>
          {error && (
            <p className="text-sm text-destructive text-center">{error}</p>
          )}
          <div className="flex gap-2">
            <Button
              type="button"
              variant="outline"
              onClick={() => {
                setStep("phone");
                setCode("");
                setError(null);
              }}
              className="flex-1"
            >
              返回
            </Button>
            <Button
              type="submit"
              disabled={loading || code.length !== 6}
              className="flex-1"
            >
              {loading ? "登录中..." : "登录"}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}