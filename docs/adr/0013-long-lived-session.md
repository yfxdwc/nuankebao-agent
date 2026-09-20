# ADR-0013: 同设备长期登录 (会话 10 年 + 滚动续期)

> **状态**: ✅ Accepted (主人 2026-09-20 拍: 「同一个设备需要能够长期记住登录状态，不限时长」)
> **日期**: 2026-09-20
> **影响范围**: Auth.js 会话配置 (`src/lib/auth/config.ts`) + dev 登录端点 (`/api/auth/flutter-login`) +
> Flutter 凭证存储 (`core/http/api_client.dart` / `session_token.dart`) + 「我的 → 网络自检」
> **相关**: [ADR-0008 APK/WEB 双域](./0008-apk-web-domain-spec.md) · [login-failure-triage §2.B R12](../login-failure-triage.md) · CHARTER §3.2

---

## 1. 背景与根因

主人反馈: 「当前 app 退出后又要重新登录。在同一个设备需要能够长期记住登录状态，不限时长」

查出来的根因 (代码事实):

| 位置 | 之前 | 后果 |
|---|---|---|
| `src/lib/auth/config.ts` | `session: { strategy: "jwt" }` —— **没写 maxAge** → Auth.js 默认 **30 天** | 30 天后 JWT 失效 → API 401 → 用户重新登录 |
| `src/app/api/auth/flutter-login/route.ts` | 自己写死 `30 * 24 * 60 * 60` | 与 Auth.js 侧**两处各写一份** → 改一处忘一处 |
| Flutter `flutter_secure_storage` 读取 | 直接 `await storage.read(...)`, 异常会冒泡 | 安卓 keystore 失效 (系统升级/恢复备份/换锁屏密码) 时**抛异常** → 用户"莫名被登出"且看不到原因 |

> 销售员的手机就是工作设备。CRM 类 App 每天开几十次, 隔三差五要求重新登录是不可接受的。
> 微信/钉钉/大多数国内 CRM 的做法都是「装上就一直登着」。

---

## 2. 决策

| 项 | 值 | 理由 |
|---|---|---|
| `session.maxAge` | **10 年** (315360000s) | JWT 必须有 `exp`; 10 年在实践上 = "永不掉线", 同时保留服务端可拒绝的空间 |
| `session.updateAge` | **7 天** (滚动续期) | 只要 7 天内用过一次, JWT 重新签发 → 到期时间顺延; 真正常用的设备**永不掉线** |
| 唯一真相 | `src/lib/auth/session.ts` | Auth.js 侧与 dev 端点共用 (以前两边各写 30 天就是坑) |
| 运维手闸 | 环境变量 `SESSION_MAX_AGE_DAYS` (1-3650) | 想统一缩短/延长不用改代码; 非法值一律回退默认 |
| 凭证存储 | 安卓 `flutter_secure_storage` 读写**全部 try/catch** | keystore 偶发失效不该表现为"莫名被登出" (读失败=当作没登录, 但**不删**数据) |
| 自检可见 | 「我的 → 网络自检」显示**登录状态 + 有效期** | 主人/客服能一眼看到"会不会又要登录"; JWE 解不开时说实话"由服务器校验" |

---

## 3. 为什么不是"真无限" / 为什么不引入 refresh token

| 方案 | 取舍 |
|---|---|
| ✅ **10 年 JWT + 滚动续期** (本 ADR) | 实现零成本 (只改两个常量); 满足"不限时长"的用户体验 |
| ❌ JWT 不带 exp | 等于永不失效的凭证; 任何泄露都永久有效, 且无法表达"过期"概念 |
| ⏳ refresh token + 短期 access token | 更标准、可吊销, 但要新增 token 表 + 轮换 + 并发刷新处理 —— **Phase 3 (SaaS) 再评估** |

**撤销能力 (现状说明, 必须知道)**:
- 客户端「退出登录」= 清本地凭证; **服务端那份 JWT 在 10 年内仍然有效**(纯 JWT 无法单点吊销)
- 设备丢失要作废凭证: ① 停用账号 (`user.is_active=false` → 下次登录被拒; 现有 JWT 仍能用直到过期)
  ② 换 `AUTH_SECRET` (**全体用户**失效, 需要重新登录)
- 真要"单设备踢下线", 需要 token 版本号/黑名单表 → 记入 Phase 3 待办

---

## 4. 验证

```bash
# 服务端认这个 token 的到期时间 (实测 = 10 年)
curl -s -H "Cookie: authjs.session-token=$TOKEN" http://127.0.0.1:3003/api/auth/session
# → {"expires":"2036-09-17T05:45:39.757Z", ...}

# 登录下发的 cookie
curl -sD - -o /dev/null -X POST .../api/auth/flutter-login -d '{...}' | grep -i set-cookie
# → Max-Age=315360000 (10 年)
```

- `tests/auth-session-ttl.test.ts` **5 pass**: 默认 10 年 / 滚动 7 天 / **Auth.js 配置真的接上了这两个值** /
  手闸 1-3650 天生效 / 非法值回退
- `flutter_app/test/session_token_test.dart` **5 pass**: JWS 解 exp / JWE 解不开不报错 /
  脏数据不误判过期 / 三种文案 / JWE 时说实话"由服务器校验"
- 手工: 登录 → 杀进程 → 重开 → 仍是登录态 (APK 真机由主人验收)

---

## 5. 后果

**正面**: 常用设备永不掉线; 配置只有一个真相, 不会再出现两侧漂移; 故障可自检 (网络自检里能看到登录态与有效期)。

**代价**:
- 长期凭证的安全面变大 → 手机丢失时要走"停用账号 / 换 secret"流程 (已写入本文档)
- 10 年 JWT 里携带的 `phone` 等声明不会随账号变化更新 (改手机号需重新登录才能刷新) —— 目前可接受
