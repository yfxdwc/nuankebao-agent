// force-dynamic for build (sandbox EAGAIN on static prerender)
import { redirect } from "next/navigation";

export const dynamic = "force-dynamic";

export default function RootPage() {
  // 根路径直接重定向到 /admin
  // middleware 会根据登录态决定是否进一步重定向到 /login
  redirect("/admin");
}