import { redirect } from "next/navigation";

// v0.1.4 Phase 9 重定向: /preview 已并入 /app-preview
// 历史: /preview 是 W19 早期版本, /app-preview 是 v0.1.3 重构后的完整版
// 行为: 任何 /preview 访问自动 307 → /app-preview
export default function PreviewRedirect() {
  redirect("/app-preview");
}
