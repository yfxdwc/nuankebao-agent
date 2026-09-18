# 「我的」页 (个人资料 + 系统设置) 设计与落地

> **主人要** (2026-09-18): 「'我的'页中。丰富个人和系统设置信息。我没有具体要求，你根据当前项目情况做工业级完善」
>
> **一句话**: 「我的」页从「头像占位 + 3 个数字 + 加盟入口 + 退出」扩成
> **个人资料 / 加盟身份 / 数据概览 / 显示与存储 / 账号与安全 / 关于与帮助** 六块,
> 每一块都接真数据、真有行为, 不放假开关。

---

## 1. 落地原则

| 原则 | 具体表现 |
|---|---|
| **真有效果** | 字号真改 (全 App 立即变)、版本真查 (服务器 pubspec 真源)、网络真测 (`/api/health`)、缓存真清 (`flutter_cache_manager`)、资料真改 (`PATCH /api/franchisees/:id` + 审计) |
| **空态是合法状态** | 未加盟 / 统计缺失 / 账号资料不全 / 无 session —— 四种情况都渲染成「解释 + 下一步」, 不是错误页、不是空白 |
| **口径要和别的页对得上** | 数据概览跟客户列表同口径; 跟列表不一致的数字 = 页面自己打自己脸 (见 §4) |
| **中老年优先** | 行高 ≥ 64、字号 18/16、触摸区 ≥ 44、文案是大白话 (「看不清楚就调大」而不是「文字缩放」) |
| **不编造** | 没有通知能力就不放「提醒开关」; 没有法务文本就不写「隐私政策」, 只讲事实 (数据存哪/怎么加密/谁能看) |

---

## 2. 页面结构 (从上到下)

| 区块 | 内容 | 数据源 |
|---|---|---|
| 个人资料 | 真实姓名 (加盟名优先) + 账号名 alias + 角色 + 门店 + 手机号 (默认打码 / 点 👁 看全号 / 📋 复制) + 「编辑我的资料」 | `GET /api/me` |
| 我的加盟身份 | 编号 / 位置 (A线·B线) / 层级 / 路径 / 我的上级 (可点进 `/franchisees/:id`) / 加入时间 / 状态 / 我的下线 N 人 (A线 x · B线 y) / 备注 | `GET /api/me` |
| 数据概览 | 客户 / 待办跟进 / 本月拜访 / 本月新增客户 + 累计互动 + 「我的加盟网络」入口 | `GET /api/me` |
| 显示与存储 | 字号 标准·大·特大 (立即生效) + 清理图片缓存 | 本机 `shared_preferences` |
| 账号与安全 | 登录手机号 (只读 + 复制) / 30 天登录有效期 / 账号编号 | `GET /api/me` |
| 关于与帮助 | 当前版本 / 检查更新 (服务器版本 + 安装包时间·大小 + 下载 + 扫码) / 使用帮助·数据安全页 (`/profile/about`) / 网络自检 / 服务地址 (debug) | `GET /api/app-version` + `GET /api/health` |
| 退出登录 | 危险操作, 二次确认 (数据不受影响) | — |

### 文件位置 (都在 `flutter_app/lib/screens/`, **不是** `modules/`)

| 文件 | 职责 |
|---|---|
| `profile_page.dart` | 主页面 (六个分区) |
| `profile_widgets.dart` | 分区卡 / 条目 / 信息行 / 数字框 (统一行高与字号) |
| `profile_sheets.dart` | 三个弹层: 编辑资料 / 检查更新 / 网络自检 (+ `buildDiagnosticText`) |
| `about_page.dart` | 使用帮助 6 条 + 数据安全 5 条 + 遇到问题 (路由 `/profile/about`) |

> 为什么不建 `modules/profile/`: AGENTS §4.5 明确「profile 是 web admin 扩展页, 不是 APK 模块;
> 新建模块需主人 ask_user 拍板」。所以同伴文件放在 `lib/screens/` 同层, 不新开模块。

---

## 3. 后端契约

两个新端点 (完整字段见 [`docs/api.md §13`](./api.md)):

| 端点 | 作用 | 备注 |
|---|---|---|
| `GET /api/me` | 账号 + 加盟身份 (含上级、下线计数) + 门店 + 数据概览 | **一次拉完** —— 客户端拼 4 个请求 = 4 个 loading 状态; 服务端一次给一份快照 |
| `GET /api/app-version` | 服务器版本 (pubspec 真源) + 安装包元数据 (时间/大小/md5/下载 URL) | 客户端跟 `package_info_plus` 的本机版本比 → 服务器新的才提示 |

新增查询函数:

- `src/lib/db/queries/dashboard.ts` → `getStatsOverview(ctx | null)` (带本月新增客户)
- `src/lib/db/queries/franchisee.ts` → `countDirectDownline()` (一次 `GROUP BY placement_side`, 不递归)
- `src/lib/utils.ts` → `maskPhone()`; `src/lib/apk.ts` → `parseAppVersionSpec()`

---

## 4. 两个容易踩的口径坑 (本次明确拍板)

### 4.1 数据概览 = 客户列表口径 (不是「只看我建的」)

`GET /api/customers` **目前没有传 `rbacCtx`** —— 销售员看到的是全库非软删客户。
所以「数据概览」也传 `getStatsOverview(null)`, 两块数字必须一致。

> 反面教材: 如果这里用 `getStatsOverview(rbacCtx)` (只看 `created_by = 我`),
> 测试账号会显示「客户 6」而客户列表显示「47 条」—— 主人一眼就会认为是 bug。
>
> 升级路径: 客户列表接行级过滤那天, 把 `ctx` 传进来即切换 (SQL 已经写好, 注释在函数头)。

### 4.2 手机号: full + masked 都给, 默认只显示 masked

页面经常被同事/客户瞄一眼 → 默认 `138****8000`; 点 👁 才显示全号。
后端同时返回两串 (`phone.full` / `phone.masked`), 客户端不做字符串截断 (避免中英混排/分机号出怪)。

---

## 5. 本机设置: 字号 (唯一一个「系统设置」里的偏好项)

```
core/providers/settings_provider.dart
  AppFontSize.standard = 1.0 / large = 1.15 / xlarge = 1.3   (上限 1.3: 再大固定高度按钮会挤破)
  存 key: settings.font_size (shared_preferences, 设备本地, 不跟账号走)
  main() 先 await SharedPreferences.getInstance() 再 runApp
    → 否则首帧按标准字号画、随后跳成特大, 老人看到界面闪一下
  app.dart builder: textScaler = clamp(用户档位 × 系统字号, 0.9, 1.6)
    → 尊重手机系统「超大字体」设置, 但不允许叠出不可用的界面
```

放 `MediaQuery.textScaler` 而不是 `ThemeData.textTheme` 的原因: 页面里写死的
`TextStyle(fontSize: AppTheme.fontMd)` 不跟 theme 变, 而 textScaler 对**所有**文字生效。

---

## 6. 明确不做 (以及为什么)

| 不做 | 原因 |
|---|---|
| 暗色模式开关 | AGENTS §1 反 vibe + 全局 `themeMode: light` 已锁 |
| 「生日提醒开关」等通知设置 | App 里没有本地通知/推送能力 (`flutter_local_notifications` 未接) —— 放了就是假开关。生日提醒目前是**客户维度**字段 (客户表单里填提前几天) |
| 「默认视图/默认首页」 | 要改客户列表与路由初始态, 会跟并发改 `customers_page.dart` 的改动打架; 且改字号时路由重建会把用户弹回首页 |
| 自助改手机号 | 手机号 = 登录账号, 换号要重新验证新旧号 (W3 阿里云短信没接完) → 页面写「换号找管理员」 |
| 金额 / 业绩 / 佣金 | ADR-0006 边界: 纯展示, 不算钱 |
| 「隐私政策」全文 | 没有法务文本。只写**事实** (自建服务器 / 字段加密 / 权限 / 审计 / 备份) |
| 强制升级 | 服务业场景不该在客人面前弹「必须升级」; 只提示 + 给下载入口 |

---

## 7. 验收清单

```bash
# 后端
npx tsc --noEmit
npx vitest run tests/profile-utils.test.ts            # maskPhone / parseAppVersionSpec
curl -s http://127.0.0.1:3003/api/me | python3 -m json.tool
curl -s http://127.0.0.1:3003/api/app-version | python3 -m json.tool

# Flutter
cd flutter_app
flutter analyze lib/screens lib/core lib/app.dart lib/main.dart
flutter test test/me_model_test.dart test/settings_provider_test.dart
flutter test test/profile_page_test.dart               # 四块内容 + 3 种空态 + 字号真改 + 窄屏不溢出
flutter test                                            # 全量回归 (含 widget_test smoke)
```

人工/浏览器验证 (每次改 UI 必做, AGENTS §3):

- [ ] 我的 → 显示与存储 → 点「特大」→ 整个 App 字变大, 返回客户页仍然大
- [ ] 我的 → 关于与帮助 → 检查更新 → 显示本机版本 vs 服务器版本, 无包时不报错
- [ ] 我的 → 关于与帮助 → 网络自检 → 显示「服务器正常 + 响应 xx 毫秒」
- [ ] 我的 → 编辑我的资料 → 改名保存 → 头部与加盟网络里的名字同步变
- [ ] 拉掉手机网络 → 我的页显示「网络不太好 + 重试」, 不是白屏
- [ ] 320 窄屏 + 特大字号: 无黄黑条纹 (overflow)

---

## 8. 后续可做 (要做先拍板)

1. **通知设置** —— 先有本地通知能力 (跟进到期 / 生日), 再放开关; 否则又是假开关
2. **默认视图 / 默认首页** —— 等 `customers_page.dart` 的并发改动落地, 且路由不因设置重建
3. **头像上传** —— 需要存储策略 (现在照片走 `/api/photos`), 且要考虑「设备本地 vs 账号同步」
4. **客户端上传诊断日志** —— 现在只支持「复制诊断信息发给管理员」, 未来可一键上报
5. **W3 真实短信** —— 自助换号/找回登录的一环
