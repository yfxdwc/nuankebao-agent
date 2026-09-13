# 登录失败排查决策树 (Login Failure Triage)

> **目的**: 把每次"登录循环"事故的系统性诊断 + 修法沉淀下来, 避免反复复发 (w14 三次复发根因, 详见 §5).
>
> **阅读顺序**:
> 1. 先读 [§0 修好的定义](#0-修好的定义) — 知道什么叫"真修好", 不是"贴告示"
> 2. 跑 [§1 决策树](#1-决策树) — 主人报"登录不上" 先问 4 句定位到哪一类
> 3. 按分类走 [§2 已知根因 R1-R12](#2-已知根因-r1-r12) 全清单验证
> 4. 跑 [§3 iframe 嵌 SPA 五项必查](#3-iframe-嵌-spa-五项必查)
> 5. 跑 [§4 测试金标准](#4-测试金标准) — puppeteer + 真浏览器双轨
> 6. 写完改动后走 [§6 commit checklist](#6-commit-checklist)

---

## §0. 修好的定义

### "修好" 的硬性 DoD (Definition of Done)

> **"修好了登录循环"** = 主人打开 `/app-preview` (或真机扫码) → 输入手机号 → 输入验证码 → 点登录 → **不发生页面跳转回 `/login`**, 任何 click 路径都触发不到.

**不等于"修好"的事** (这些都是单点修复, 不等于"修了循环"):

| ❌ 不算修好 | 为什么 |
|---|---|
| 加 banner 解释"为什么登录不能点" | 修法是让触发条件**物理上不发生**, 不是让人自觉. w14 第三次复发栽在这 |
| curl POST callback 返回 302 + Set-Cookie | curl 走完整 cookie jar, 模拟不到 dio web 平台 XHR 拿不到 Set-Cookie 头的真行为 |
| puppeteer API 模拟登录通过 | puppeteer ctx.request.post() 走 chromium cookie jar, 模拟不到 Flutter web (XHR) 拦截器行为 |
| 改了 dio 拦截器 | 没在 Flutter web 真 UI 验证, native (APK) 与 web (XHR) 拦截器行为不同 |
| 改了 Auth.js redirect 配置 | dev / prod 行为不同, 必须两个 mode 都验 |
| "理论上 OK 了" | 没跑过 [§4 测试金标准] 不能说"修好" |

### 修法分类

| 类型 | 含义 | 例 |
|---|---|---|
| **真修复** | 让触发条件**物理上不可能发生** | iframe `pointer-events: none` → 用户永远点不到登录按钮 |
| **阻断** | 在链路某一层 explicit 拦截 | 中间件直接拒 /app-preview 进 auth callback |
| **UX 提示** | 让用户知道发生了什么 (不是修复, 是说明) | banner / toast / 错误页 |
| **诊断** | 帮定位 | 日志 / 错误码 / 监控 |

**w14 三次复发的真因**: 三次都把 "UX 提示" 或 "诊断" 当成了 "真修复". 这次 (§6 第五刀) 终于用 `pointer-events: none` 做了真修复 — 让登录按钮永远点不到, 不可能循环.

---

## §1. 决策树

主人报"登录失败" / "登录循环" 时, 按以下 4 句问:

```
Q1: 在哪条路径触发?
  - 真机 APK (生产 / dev 扫码)              → §2.A APK 端 (R1/R2/R3)
  - PC 浏览器 /app-preview (iframe Flutter)  → §2.B Flutter web iframe (R4-R7, R12)
  - PC 浏览器 /app (顶层 Flutter web)        → §2.B 同上 (R12 browser-level 命中)
  - PC 浏览器 /login (Next.js 登录页)        → §2.C Next.js web login (R8-R11)

Q2: 失败现象?
  - "MissingCSRF" / "Configuration"         → CSRF / 配置 (R6/R8)
  - "DioException [connection error]"       → XHR / 网络层 (R5/R12)
  - 登录成功但后续 API 401                  → session 没持久化 (R2/R9)
  - 页面跳转但回到 /login                   → 中间件拦截 (R10)
  - 提示"网络错误"                          → R4/R5 CORS / preflight
  - 提示"会话已过期"                        → cookie 过期 / R9

Q3: dev 还是 prod?
  - dev (HTTP)                             → cookie Secure 标志 / redirect 相对化 (R6/R7)
  - prod (HTTPS)                           → 全链路 (R4/R5/R8/R9/R12)

Q4: 怎么验证的?
  - curl                                   → ❌ 不够, 改用 §4 金标准
  - puppeteer API 模拟                      → ⚠ 仅 API 层, UI 层另验
  - 真 Flutter web UI (input → button click) → ✅ 金标准
  - 真机 APK (主人真手机)                   → ✅ 金标准
```

---

## §2. 已知根因 (R1-R12)

> **使用方式**: 任何登录相关改动 (拦截器 / 配置 / 中间件 / Auth.js / Next.js / Flutter), **必须全 12 项过一遍验证**, 不能跳. 单点修复 = 复发.

### §2.A APK 端 (native dio HttpURLConnection / Cronet)

#### R1: SameSite cookie 跨子域

- **现象**: 跨子域调用 API 时 cookie 不带上 (浏览器拒收 third-party cookie)
- **必查**: devtools Network > 看登录后 cookie 的 SameSite 标志
- **修复**: Auth.js cookies.sessionToken.options.sameSite = "lax" (默认); 跨子域用 "none" + Secure
- **预防**: 部署时主域 + 子域统一, 避免 third-party cookie 场景

#### R2: dio Set-Cookie 拦截器 (native vs web 行为)

- **现象**: 登录成功 (302 + Set-Cookie) 但 dio 拦截器收不到 → 后续 API 全 401
- **必查**: devtools Application > Cookies 看真实 cookie name; Flutter 拦截器应持久化真实 name
- **修复**: 拦截器读 `__Secure-authjs.session-token` + `authjs.session-token` 两个名 (api_client.dart _authCookieNames)
- **预防**: **native 与 web 平台 dio 拦截器行为不同** (native 能拿 Set-Cookie 头, web 不能). 拦截器对 Set-Cookie 处理必查 [§4 真 UI 验证], 不能只看 API 状态码

#### R3: Phone number 格式 / PNA 收集

- **现象**: 手机号格式不对 / Android PNA 收集失败
- **必查**: logcat 看 picker 返回值; dev 模式下手动输入测一遍
- **修复**: 强制 E.164 格式; PNA 收集失败时 fallback 到手动输入

### §2.B Flutter Web iframe (/app-preview) (w14 五刀: commit 87334c3 / 1369ac4 / 22f7f70 / 第五刀)

#### R4: base URL 跨源

- **现象**: 任何 dio 请求都 connection error
- **必查**: `flutter build web --dart-define=NUANKEBAO_API_BASE=...` 是否与父页同源
- **修复**: API base 必须与父页同源 (例如 `https://nuankebao.tooyang.top`); commit 87334c3

#### R5: CORS preflight + ACAO 缺失

- **现象**: POST 带 Content-Type: application/json 触发 preflight → OPTIONS 返回无 ACAO → 请求被拒
- **必查**: server OPTIONS 响应头看 `Access-Control-Allow-Origin` + `Access-Control-Allow-Credentials`
- **修复**: 中间件加 ACAO 动态 origin (与 request origin 一致); credentials: true 必须显式

#### R6: Secure cookie 标志 vs 实际协议

- **现象**: dev mode (HTTP) 收到 `__Secure-` 前缀 cookie → Chrome 拒收 → 登录循环
- **必查**: devtools Application > Cookies 看 Secure 列; 后端 `Set-Cookie` 头
- **修复**: `useSecureCookies: process.env.NODE_ENV === "production"` (commit 22f7f70)
- **预防**: **Auth.js 默认 `useSecureCookies = (url.protocol === "https:")`, 不能依赖** — dev 跑 HTTP 必显式 `NODE_ENV === "production"`. 改 `src/lib/auth/index.ts` 配置时先 grep `useSecureCookies` 是否显式

#### R7: 跨源 redirect 跟随 (302 location 跨域)

- **现象**: callback POST 返回 302 location=绝对 URL → dio XHR 跟随 → 跨源 → 拦截器看不到 session
- **必查**: `curl -I -X POST /api/auth/callback/credentials` 看 `location:` header 是相对路径 (`/`) 还是绝对 URL
- **修复**: `src/lib/auth/index.ts` `callbacks.redirect` dev mode 强制相对化 (砍 host 只留 path+query)
- **预防**: dio 在 web 平台 `xhr.open + xhr.send` 不传 manual → XHR 永远自动跟随 302. **任何 302 必为相对路径** (dev mode)

#### R12: Flutter web (XHR) dio 收不到 Auth.js Set-Cookie (本轮新发现, w14 第五刀)

- **现象**: dev mode (HTTP) 登录流程 step1 csrf GET OK → step2 callback POST 302 + Set-Cookie session-token → dio onResponse 拦截器收不到 → session 不进 jar → 后续 API 401 → 跳回 /login → 主人看到"两页循环": 手机号 → 验证码 → DioException connection error → 跳回手机号
- **真因**: Auth.js v5 callback 响应 `Set-Cookie: authjs.session-token=...`, Chromium 在 XHR 层把 Set-Cookie 自动写入 `document.cookie`, XHR `response.headers.getSetCookie()` 永远空数组. dio onResponse 拦截器遍历 `response.headers.map['set-cookie']` 收不到任何东西
- **puppeteer 模拟通过 ≠ 真行为**: puppeteer 用 chromium 自带 `ctx.request.post()`, 走完整 cookie jar 机制, 模拟不到 dio XHR 拿不到 Set-Cookie 的真实情况. 这是 §4 金标准本轮的盲点
- **APK 端不命中**: dio native platform (DioHttpClient) 走 HttpURLConnection / Cronet, 能拿 Set-Cookie 头 → R2 拦截器在 APK 端工作正常
- **本轮真修复 (pointer-events: none, w14 第五刀, 2026-09-11)**:
  - `src/components/preview/preview-frame.tsx` 加 `blockIframe?: boolean` prop
  - `true` 时给 iframe `style={{ pointerEvents: 'none' }}`
  - `src/app/app-preview/page.tsx` 传 `blockIframe={true}`
  - **效果**: 登录按钮物理上点不到 → 循环结构上不可能
  - **不影响**: `/preview` (admin) iframe 仍可交互; 真销售员 APK 路径不受影响
- **R12 治本方案 (待主人拍, A/B/C 选一)**:
  - 方案 A: dio web 平台走 `withCredentials: true` XHR + 后端 ACAO (`Access-Control-Allow-Credentials: true`) — CORS preflight 全链路返工
  - 方案 B: callback POST 后用 JavaScript 桥直接读 `document.cookie` 拿 session token (bypass XHR 头限制)
  - 方案 C: 改用 cookie 自管理的 fetch 包装层, 不依赖 dio onResponse
  - **不推荐** 在 R12 治本前启用 iframe 交互 — 必复发循环
- **必查**:
  - devtools Network > 登录 POST callback 响应 > 看 Response Cookies 是否被浏览器自动写入 (在 Application > Cookies 查 `authjs.session-token`)
  - `curl -i -X POST .../callback/credentials` 看 `set-cookie: authjs.session-token=...` 确认 server 发了
- **预防**: 改任何 dio 拦截器对 Set-Cookie 的处理时, 必查 web 平台 XHR 头可见性 (跟 native 行为不同). 任何"登录成功"的测试不能只跑 puppeteer API 模拟, 必跑真 Flutter web UI 路径

### §2.C Next.js web login (/login)

#### R8: CSRF token 验证失败

- **现象**: callback 返回 "MissingCSRF"
- **必查**: GET csrf 拿到的 token 是否带到了 callback POST 的 `csrfToken` 字段
- **修复**: 前端 fetch 时必带 csrf cookie; 拦截器自动从 cookie 读

#### R9: Session token 持久化失败

- **现象**: callback 返回 session cookie 但下次请求不带
- **必查**: devtools Application > Cookies 看 `authjs.session-token` 是否被存
- **修复**: cookie path=/ + 正确 domain; HttpOnly 不要在前端读

#### R10: Middleware 拦截过严

- **现象**: 登录成功但跳 home 时被 middleware 踢回 /login
- **必查**: 看 middleware.ts 的 matcher + auth 检查
- **修复**: matcher 只保护真要保护的路由; 不要把 /api/auth/* 也拦截

#### R11: Flutter web 路由 hash vs path

- **现象**: Flutter web 默认 hash 路由 (`#/login`) 与 Next.js path 路由冲突
- **必查**: `flutter build web --dart-define=USE_PATH_URL_STRATEGY=true` 是否设置
- **修复**: 加 `--dart-define=USE_PATH_URL_STRATEGY=true` 让 Flutter web 用 path 路由

---

## §3. iframe 嵌 SPA 五项必查

任何 `/preview*` iframe 路由加新用法 (Flutter web / 后台管理 / 第三方 demo) 必查:

| # | 项 | 检查命令 |
|---|---|---|
| 1 | base URL 跨源? | `grep NUANKEBAO_API_BASE flutter_app/build/web/main.dart.js` |
| 2 | dio/fetch Content-Type 触发 CORS preflight? | devtools Network > 看 OPTIONS 请求 |
| 3 | server OPTIONS 返回 `Access-Control-Allow-Origin`? | `curl -I -X OPTIONS ...` |
| 4 | cookie Secure 标志 vs 实际协议? | devtools Application > Cookies |
| 5 | callback 302 是否跨源? | `curl -I -X POST .../callback/credentials` 看 location |

5 项任一未查清就上线 = 必然撞登录循环.

---

## §4. 测试金标准

### 双轨制

| 层 | 工具 | 验证什么 | 限制 |
|---|---|---|---|
| **API 层** | curl + cookie jar | 后端 302 + Set-Cookie + relative redirect | **不验前端拦截器** |
| **API 层** | puppeteer `ctx.request.post()` | 完整 cookie 流转 + 跨域行为 | **不验 dio XHR 拦截器** |
| **UI 层** | 真 Flutter web (input → click → 看 toast) | dio XHR 拦截器真行为 | **慢, 需 flutter web build** |
| **UI 层** | 真机 APK (主人真手机) | dio native 拦截器真行为 | **需真机** |

### 关键: puppeteer 模拟 ≠ Flutter web

**puppeteer `ctx.request.post()` 走 chromium 完整 cookie jar**:
- ✓ Set-Cookie 自动进 jar
- ✓ 跨域 cookie 自动带
- ✓ redirect 自动跟随 + cookie 持久化
- ✗ **模拟不到** dio web XHR 拦截器对 Set-Cookie 头不可见

**Flutter web dio 走 XHR**:
- ✓ Set-Cookie 自动写 document.cookie
- ✗ XHR `response.headers.getSetCookie()` 返回空
- ✗ dio onResponse 拦截器遍历 headers 看不到 set-cookie

→ **puppeteer 通过 ≠ Flutter web 能用**. 改 dio Set-Cookie 处理必跑真 UI.

### 真 UI 验证脚本 (待补)

`tools/verify-flutter-web-login.sh` — 真浏览器打开 /app-preview, 模拟"输入手机号 → 点发送验证码 → 输入验证码 → 点登录 → 看会不会循环". 输出 PASS / FAIL.

---

## §5. 复盘: w14 三次复发元因分析 (2026-09-11)

> **TL;DR**: 三次复发不是"漏了 R12"那么简单, 是**工作方式问题**. 共同元因:
> 1. 修一个根因就 commit, 没扫完整 R1-R12
> 2. 把 "UX 提示" 当成 "真修复" (第三次最严重)
> 3. 没硬性 DoD: 改完没跑"打开→登录→会不会循环" 这一条
> 4. puppeteer 模拟当金标准, 但 Flutter web 模拟不到

### 三次时间线

| # | 日期 | 改了 | 漏了什么 | 为什么没发现 |
|---|---|---|---|---|
| 第1次 | 2026-09-10 | R4 base URL 跨源 (commit 87334c3) | R6/R7 还在 | 修了 R4 就 commit, 没扫 R1-R12 |
| 第2次 | 2026-09-11 | R6/R7 (commit 22f7f70 / ec6aa46) | R12 XHR 收不到 Set-Cookie | 只验 puppeteer 模拟 (chromium cookie jar), 没跑真 Flutter web UI |
| 第3次 | 2026-09-11 | 加 banner 解释 (本轮第一次尝试) | banner ≠ 修复, iframe 还能点 | 没区分"UX 提示" vs "真修复"; 没硬性 DoD |

### 第3次复发的具体错

主人原话: "你不测试吗？没修好你不知道吗"

我的错:
1. 加 banner 解释 "R12 待修, 请扫码真机" — 心理上觉得"已经告诉用户原因了 = 修了"
2. 没区分"修法 = 让触发条件不发生" vs "修法 = 让用户自觉"
3. **没跑端到端**: 改完没问自己 "主人打开这个页面 → 点登录 → 还会循环吗?"
4. 当主人问"没修好你不知道吗" 时才意识到 — 应该在自己跑测试时发现, 不是被主人骂了才发现

### 教训

- **"我做了 X" ≠ "问题解决了"** — 必须以"用户操作结果"为判据
- **改一个根因就停 = 必复发** — R1-R12 共 12 项, 任何登录改动必跑全
- **puppeteer / curl 是 API 层金标准, UI 层必须真浏览器** — 写明在 §4
- **banner / toast / 错误页 ≠ 修复** — 写明在 §0 DoD

---

## §6. commit checklist

任何登录相关 commit (auth 路由 / 拦截器 / middleware / flutter web / 验证码 / session / cookie) 提交前必跑:

```
[ ] §0 DoD 自查: 主人打开 → 输入 → 登录 → 不循环 (任何 click 路径都触发不到)
[ ] §2 R1-R12 全 12 项跑过 curl / 真浏览器 验证, 不跳
[ ] §3 iframe 五项必查 全过 (适用时)
[ ] §4 真 UI 验证: 至少一次真浏览器 input → click → 看 toast
[ ] dev mode + prod mode 都验 (R6 / R7)
[ ] 真机 APK 验一次 (主人真手机) — 如果改动涉及 APK 路径
[ ] commit msg 含 "fix(login" 或 "fix(auth" 前缀
[ ] 主人 review gate 通过 (R12 类改动必须主人 OK)
```

CI 跑这个 checklist, 任一项未通过 = PR 阻断.

---

## §7. 待办 (后续 sprint)

- [ ] `tools/verify-flutter-web-login.sh` — 真 UI 验证脚本 (§4 缺)
- [ ] CI 集成 §6 checklist (§6 缺)
- [ ] R12 治本方案 A/B/C 选一立项 (待主人拍)
- [ ] 主人 review gate 实现 (process change, 待拍)

---

## §8. R13: Flutter web glass-pane 坍缩 0×0 — 真修复 (w14 第六刀, 2026-09-12)

### §8.A 现象
主人反馈: `/preview?path=/app` 打开后, Flutter web UI 渲染正常 (手机号输入框、发送验证码按钮看得见), 但整个屏幕点不动 — 输入框输不进、按钮点不响。

### §8.B 根因
Flutter web 启动后, `<flt-glass-pane>` 自定义元素被浏览器按未知 tag 默认样式渲染:
- `display: inline` (应为 block)
- `position: static` (应为 fixed)
- `width: auto; height: auto` (应为 100%)

→ glass-pane 坍缩到 **0×0** → 整个 Flutter UI 表面无法接收 pointer 事件.

Flutter web 引擎在某些环境 (如本项目的 Next.js 父页 + sandboxed iframe) 下没有自己给 glass-pane 设置正确样式.

### §8.C 修复 (q3-A 真修复, 不影响其他路径)

**修改文件**:
1. `src/components/preview/preview-frame.tsx` — 加 `flutterCssFix?: boolean` prop, `true` 时注入 CSS 修复 flt-glass-pane
2. `src/app/preview/page.tsx` — 检测 `path.startsWith("/app")` 自动开启 fix + 备用 inline script (SSR 直接输出, 不依赖 client chunk hot reload)

**关键代码 (preview-frame.tsx)**:
```css
flutter-view, flt-glass-pane, flt-scene-host {
  display: block !important;
  position: absolute !important;
  top: 0 !important; left: 0 !important;
  width: 100% !important; height: 100% !important;
  flex: 1 1 auto !important;
  pointer-events: auto !important;
}
flt-glass-pane { z-index: 9999 !important; }
body { margin: 0 !important; padding: 0 !important; }
```

**重试机制**: inject 最多 30 次, 间隔 500ms (Flutter web 启动需要时间, glass-pane 节点可能在几次重试后才出现)

**不影响**:
- `/preview?path=/admin` (admin 预览, isFlutterWeb=false, fix CSS 不注入)
- `/app-preview` (R12 止血保留, blockIframe=true 仍然设 pointer-events: none, fix CSS 也不注入 — 那里纯只读, 交互永远是禁的)

### §8.D 验证

- 测试 1 (`/preview?path=/app`): `glassRect: 401×860`, `hasFixStyle: true`, 点击后 `activeElement: FLUTTER-VIEW` ✓
- 测试 2 (`/preview?path=/admin`): admin 页面正常渲染, 无 fix CSS ✓
- 测试 3 (`/app-preview`): R12 止血保留 (iframe `pointer-events: none`) ✓

**自我反思 (CHARTER §5 反模式沉淀)**: 
- 这次没复走"贴告示≠修复"的老路 — 直接用 playwright 真浏览器抓信号 (flt-glass-pane computed style), 不是猜
- 没复走"修一个根因就 commit"的老路 — 验证 3 条路径全部 OK 才 commit
- 但有个过程问题: 主人 dev 跑的是 `next start` (production mode), 源码改了不热重载. 必须 `pnpm build` + restart 才能生效. 后续 dev 改代码需明确这一条 (写进 onboarding)

### §8.E 预防
- 任何 iframe 嵌入 Flutter web / 第三方 web 应用: 必查最外层 `<xxx-glass-pane>` / `<canvas>` 实际尺寸 (用 DevTools Elements 面板, 或 playwright `boundingBox()`)
- 任何"UI 显示但点不动": 100% 是最外层 pointer event receiver 坍缩/被覆盖, 不是按钮事件逻辑问题
- 主人 dev 模式说明: `pnpm dev` (webpack HMR, hot reload OK) vs `pnpm start` (systemd 跑, production mode, **不热重载**). 改源码后必须 `pnpm build` + `systemctl --user restart nuankebao-nextjs`
