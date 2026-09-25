# 「我的」页 (个人资料 + 系统设置) 设计与落地

> **主人要** (2026-09-18): 「'我的'页中。丰富个人和系统设置信息。我没有具体要求，你根据当前项目情况做工业级完善」
>
> **后续拍板** (2026-09-25): 「我的页过杂 (1432 行 / 3.5 屏 / 11 区块), 中年用户滚到下面焦躁;
> 低频 app 设置下沉二级『设置』页; **字号保留快捷入口**, 设置页也放」。
> 本页为两个页面的设计合并。

---

## 0. 双重架构 (v0.1.5 + 后)

```
「我的」页 (/profile, 主页面, 高频访问, 退出/管理都从这里进入)
  └─ 区块 1‒4 保留: 个人资料 / 我的加盟身份 / 数据概览 / 设置 (字号快速 + 更多设置入口)
  └─ 区块 5: 账号与安全
  └─ 退出登录 (最底)

「设置」页 (/profile/settings, 二级页, 路由 push; 保留返回栈)
  └─ 区块 1: 显示与存储 (字号 4 档 chips + 清理图片缓存)
  └─ 区块 2: 主题配色 (换肤; ThemePickerCard)
  └─ 区块 3: 提醒 (本地通知跟进)
  └─ 区块 4: 关于与帮助 (当前版本 / 使用帮助 / 网络自检 / 管理员工具[仅 admin] / debug 服务地址)
```

**两页共用**: `core/widgets/font_size_picker.dart` —— 4 档 ChoiceChip **Row + Expanded 单行布局**
(间距 `AppSpace.s8`, label 走 `FittedBox(scaleDown) + maxLines:1 + ellipsis` 兜底不裁字,
按档位自己缩放字号保留预览, 中老年触摸区不缩)。一处改两处生效。

---

## 1. 落地原则

| 原则 | 具体表现 |
|---|---|
| **真有效果** | 字号真改 (全 App 立即变)、版本真查 (服务器 pubspec 真源)、网络真测 (`/api/health`)、缓存真清 (`flutter_cache_manager`)、资料真改 (`PATCH /api/franchisees/:id` + 审计) |
| **空态是合法状态** | 未加盟 / 统计缺失 / 账号资料不全 / 无 session —— 四种情况都渲染成「解释 + 下一步」, 不是错误页、不是空白 |
| **口径要和别的页对得上** | 数据概览跟客户列表同口径; 跟列表不一致的数字 = 页面自己打自己脸 (见 §4) |
| **中老年优先** | 行高 ≥ 64、字号 18/16、触摸区 ≥ 44、文案是大白话 (「看不清楚就调大」而不是「文字缩放」) |
| **不编造** | 没有通知能力就不放「提醒开关」; 没有法务文本就不写「隐私政策」, 只讲事实 (数据存哪/怎么加密/谁能看) |
| **高频留主页面, 低频下沉二级** | 个人/加盟/数据/账号 4 块在「我的」; 字号以外的系统设置 (主题/提醒/关于/调试) 进「设置」; 字号两处都给 (中年刚需) |

---

## 2. 页面结构 (从上到下)

### 2.1 「我的」页 (主页面, `profile_page.dart`)

| 区块 | 内容 | 数据源 |
|---|---|---|
| 1 个人资料 | 真实姓名 (加盟名优先) + 账号名 alias + 角色 + 门店 + 手机号 (默认打码 / 点 👁 看全号 / 📋 复制) + **头像 (可点, 换头像)** + 「编辑我的资料」 | `GET /api/me` |
| 2 我的加盟身份 | 编号 / 位置 (A线·B线) / 层级 / 路径 / 我的上级 (可点进 `/franchisees/:id`) / 加入时间 / 状态 / 我的下线 N 人 (A线 x · B线 y) / 备注 | `GET /api/me` |
| 3 数据概览 | 客户 / 待办跟进 / 本月拜访 / 本月新增客户 + 累计互动 + 「我的加盟网络」入口 | `GET /api/me` |
| 4 设置 (快捷) | **字号 4 档 chips (共享 `FontSizePicker`, 中年刚需不淺一层)** + 「更多设置」入口行 (跳 `/profile/settings`) | 本机 `shared_preferences` |
| 5 账号与安全 | 登录手机号 (只读 + 复制) / 30 天登录有效期 / 账号编号 | `GET /api/me` |
| 退出登录 | 危险操作, 二次确认 (数据不受影响) | — |

### 2.2 「设置」页 (二级页, `settings_page.dart`, 路由 `/profile/settings`)

| 区块 | 内容 | 数据源 |
|---|---|---|
| 1 显示与存储 | 字号 4 档 chips (与「我的」共用同一 `FontSizePicker`, 状态同步) + 清理图片缓存 | 本机 `shared_preferences` |
| 2 主题配色 | ThemePickerCard — sage / spring / summer / autumn / winter 5 个配色 (选完立即生效) | 本机主题偏好 |
| 3 提醒 | 每天 08:30 提醒跟进 (需要通知权限 / 不假开关 / 待办数变了重排) | `core/services/notifications/follow_up_reminder.dart` |
| 4 关于与帮助 | 当前版本 + 检查更新 + 使用帮助 / 数据安全 (跳 `/profile/about`) + 网络自检 + 管理员工具 (仅 `role='admin'` 可见, 跳 `/profile/admin`) + debug 服务地址 | `package_info_plus` + `/api/health` + `/api/app-version` |

### 文件位置 (`flutter_app/lib/`, **不是** `modules/`)

| 文件 | 职责 |
|---|---|
| `screens/profile_page.dart` | 「我的」主页面 (5 区块, 2026-09-25 从 11 区块 ×3.5 屏 收到 5 区块 ×2 屏) |
| `screens/settings_page.dart` | 「设置」二级页 (4 区块, 新建于 2026-09-25) |
| `core/widgets/font_size_picker.dart` | 字号档位共享组件 (Row+Expanded 单行, 两页共用, 2026-09-25 新建) |
| `screens/profile_widgets.dart` | 分区卡 / 条目 / 信息行 / 数字框 (统一行高与字号) |
| `screens/profile_sheets.dart` | 多个弹层: 编辑资料 / 检查更新 / 网络自检 / 头像选择 (+ `buildDiagnosticText`) |
| `screens/about_page.dart` | 使用帮助 6 条 + 数据安全 5 条 + 遇到问题 (路由 `/profile/about`) |
| `screens/theme_picker_card.dart` | 主题配色选择卡 (独立 widget,「设置」页面 4 区块 2 用) |

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
  AppFontSize.small = 0.85 / standard = 1.0 / large = 1.15 / xlarge = 1.3
    (2026-09-18 主人要「在标准下再加一档小」; 上限 1.3: 再大固定高度按钮会挤破;
     下限 0.85 ≈ 15.3pt: 再小就低于本项目可读性底线)
  存 key: settings.font_size (shared_preferences, 设备本地, 不跟账号走)
  main() 先 await SharedPreferences.getInstance() 再 runApp
    → 否则首帧按标准字号画、随后跳成特大, 老人看到界面闪一下
  app.dart builder: textScaler = clamp(用户档位 × 系统字号, 0.7, 1.6)
    → 尊重手机系统「超大字体」设置, 但不允许叠出不可用的界面
    → 下限取 0.7 (不是 0.9): 否则系统字号 < 1 时「小」档被夹平、点了没反应
```

放 `MediaQuery.textScaler` 而不是 `ThemeData.textTheme` 的原因: 页面里写死的
`TextStyle(fontSize: AppTheme.fontMd)` 不跟 theme 变, 而 textScaler 对**所有**文字生效。

---

## 5.1 自定义头像 (2026-09-18 主人要)

「用户头像要能够自定义（上传头像），增加几个候选头像供不希望用真人头像的用户选择」

**一句话**: 头像值只存**一个字符串** (`user.avatar_url`), 三种合法形态 ——
默认 / `preset:<id>` / `/uploads/<file>`; 候选头像是客户端本地画的图标, 上传的照片复用
现成的 `POST /api/photos`。

| 决策 | 选择 | 理由 |
|---|---|---|
| 存哪 | **服务器** `user.avatar_url` (migration `0007_user_avatar_url`) | 换手机/重装 App 头像还在; 只存本机的话第一次换手机就"头像没了" |
| 候选头像怎么做 | **图标 + 配色本地画** (8 个: 绿叶/花朵/喝茶/静心/爱心/暖阳/养生/清泉) | 矢量不糊、不增包体、不动 assets; 中老年用户"挑一个颜色好看的花草"比挑卡通人脸容易 |
| 上传走哪 | 复用 `POST /api/photos` (base64 → `public/uploads/`) | 不新增存储设施; 白得体积/格式/限流校验 |
| 白名单在哪 | 服务端 `src/lib/avatar.ts` + 客户端 `core/models/me.dart` 各一份 | 客户端可被反编译, 落库的值必须服务端说了算; 客户端那份只为"不渲染破图" |
| 外链 | **拒** (`http(s)://`) | ① 帮第三方跑统计 ② 对方删图 = 白框, 用户以为 App 坏了 ③ 违背数据自托管 (CHARTER §3.2) |
| 审计 | `user` 表已挂 `user_audit` 触发器 | 改头像自动进审计日志 (谁/何时/改成什么/IP), 满足"任何数据库写都要走 audit log" |

**接口**: `PATCH /api/me { avatarUrl }` (只此一个字段, 多传别的一律 400) ——
详见 [`docs/api.md §13`](./api.md)。上传前的本地压缩: `maxWidth/maxHeight=512`,
`imageQuality=85`, 字节头嗅探真实 mime (web 上 `image_picker` 不改后缀)。

**渲染**: `core/widgets/user_avatar.dart` —— 未知/脏值一律退回首字分支, 永远不出现白框。

---

## 6. 明确不做 (以及为什么)

| 不做 | 原因 |
|---|---|
| 暗色模式开关 | AGENTS §1 反 vibe + 全局 `themeMode: light` 已锁 |
| 把头像存成"只在当前手机" | 换手机就没了, 用户会当成丢数据 (选了服务器侧) |
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
npx vitest run tests/profile-avatar.test.ts        # 头像白名单 (正例 + 负例 + 脏数据兜底)
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
4. **客户端上传诊断日志** —— 现在只支持「复制诊断信息发给管理员」, 未来可一键上报
5. **W3 真实短信** —— 自助换号/找回登录的一环
