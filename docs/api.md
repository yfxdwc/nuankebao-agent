# 暖客宝 API 文档 (v0.1.0)

> REST API 端点 (沙龙模块追加 14 个, 见 §14)
> Base URL: `http://127.0.0.1:3003/api` (开发) / `https://nuankebao.tooyang.top/api` (生产)
> 认证: Auth.js v5 session cookie (dev `authjs.session-token`; 生产加 `__Secure-` 前缀)

## 通用约定

### 认证
除 `/api/health` 外,所有端点需要登录。客户端 (Flutter) 自动带 cookie。

### 响应格式

成功: `200/201` + JSON
失败: `400/401/404/500` + `{ "error": "错误信息", "details": [...] }`

### 时间格式
- ISO 8601: `2026-09-04T10:00:00Z`
- 日期: `2026-09-04` (YYYY-MM-DD)

### 加密字段
API 返回明文 (decryptField)。DB 存密文。

---

## 1. 健康检查

### `GET /api/health`
公开端点, 无需认证。

**响应**:
```json
{
  "status": "healthy",
  "checks": { "db": "ok" },
  "version": "0.1.0",
  "phase": "Phase 1 W1",
  "timestamp": "2026-09-04T10:00:00.000Z"
}
```

**状态码**:
- `200` 健康
- `503` DB 不可用

---

## 2. 认证

### `GET /api/auth/csrf`
拿 CSRF token (Auth.js 需要)。

**响应**:
```json
{ "csrfToken": "abc123..." }
```

### `POST /api/auth/callback/credentials`
登录 (form-urlencoded)。账号密码登录 (2026-09-19 P2):

**Body**:
```
csrfToken: string
identifier: string   # 登录名 (如 admin) 或 手机号
password: string
callbackUrl: string
```

**响应**: `302` + Set-Cookie `__Secure-authjs.session-token` (dev 无前缀)

### `POST /api/auth/signout`
登出。

---

## 3. 客户

### `GET /api/customers`
客户列表 (分页 + 搜索 + 跟进紧急度排序)。

**Query**:
- `search` (可选): 按姓名/手机号搜索
- `type` (可选): `all` / `franchisee` / `seed` / `normal` (非法值 → 400)
- `sort` (默认 `urgency`): `urgency` 跟进紧急度 / `recent` 最近联系 / `new` 最近添加 / `name` 姓名
  (非法值 → 400, 不静默降级)
- `limit` (默认 20) · `offset` (默认 0)

> **跟进紧急度** (主人 2026-09-20 拍: 第一排序规则) 是**会员功能** (`ai.repurchase`):
> 非会员请求 `urgency` → 后端自动降级为 `new` 并在响应里 `urgencyLocked: true`。
> 排序口径只在服务端算一处 (`src/lib/follow-up/urgency.ts`, 纯函数 + 单测), 客户端不自己算分。
> 详见 `docs/follow-up-list-plan.md` §3 / §6。

**响应** (每项多一个 `followUp` 块):
```json
{
  "items": [
    {
      "id": "1",
      "name": "王女士",
      "phone": "13912345678",
      "gender": "F",
      "birthYear": 1985,
      "healthTags": ["肩颈", "睡眠差"],
      "diseaseHistory": null,
      "notes": null,
      "createdAt": "2026-09-03T...",
      "updatedAt": "2026-09-03T...",
      "isMember": false,                 // ★ 会员标识 (同手机号账号是不是会员)
      "followUp": {
        "daysSinceContact": 21,          // null = 从没联系过
        "lastContactAt": "2026-08-29T...",
        "lastContactType": "phone",      // 电话/微信/到店/节日问候
        "daysSinceVisit": 5,
        "lastVisitAt": "2026-09-14T...",
        "openTaskCount": 1,
        "nextDueAt": "2026-09-16T...",
        "tags": [                        // 名字右侧标签, **最多 2 个** (1 动作 + 1 日历)
          { "key": "overdue", "emoji": "🔥", "label": "该回访了",
            "color": "danger", "hint": "跟进任务逾期 3 天", "memberOnly": false }
        ],
        "repurchase": null,              // 会员才有: { windowOpenedAt, expectedAt, avgIntervalDays, confidence }
        "urgency": 87,                   // ↓ 以下 4 个键**仅会员** (非会员为 null)
        "level": "p0",                   // p0 今天必须联系 → p4 休眠池
        "levelLabel": "今天必须联系",
        "reason": "已 21 天没联系 · 跟进任务逾期 3 天"
      }
    }
  ],
  "total": 1,
  "sort": "urgency",                     // 实际生效的排序
  "sortRequested": "urgency",
  "urgencyLocked": false,                // true = 你请求了紧急度但没会员 → 已降级
  "summary": { "dueToday": 3, "overdue": 1, "thisWeek": 5, "hibernating": 12, "total": 55 }
}
```

> `summary` 与 `repurchase` **仅会员**下发 (非会员响应里没有这两个键)。
> 兼容: 老客户端不传 `sort` → 仍是紧急度排序 (新默认); 要旧行为显式传 `sort=new`。
>
> **`isMember`** (2026-09-21 加): 这一**条客户**对应的账号是不是会员 ——
> 口径 = 同 `phone_hash` 的账号 `role='admin'` 或 `membership.member_until > now()`
> (账号=客户, 见 ADR-0013); 没有账号的客户恒 `false`。
> 客户端拿它画头像上的会员标识 (金环 + 👑)。
> **每次查询现算, 不落库** → 充值转会员 / 到期掉会员, 下次拉列表就变 (无需同步任务)。
> 判定口径唯一在 `src/lib/billing/member-flag.ts` (`memberFlagOf` / `memberExistsSql`)。

### `GET /api/customers/[id]/follow-up-analysis`
客户详情页「跟进分析」卡的客观指标 (方案 §7.1)。**全部免费** (方案 §11)。

**响应**:
```json
{
  "contactLast30": 3, "contactLast90": 7, "contactTotal": 11,
  "avgContactIntervalDays": 12,        // 中位数 (抗异常值); null = 联系少于 2 次
  "daysSinceLastContact": 21,
  "trend": "colder",                   // warmer / colder / steady / unknown
  "trendText": "在变冷 (12 → 30 天)",
  "visitCount": 5, "avgVisitIntervalDays": 14,
  "lastVisitAt": "2026-09-14T...", "daysSinceLastVisit": 5,
  "medianRepurchaseIntervalDays": 14,
  "pendingTasks": 1, "overdueTasks": 1, "oldestOverdueDays": 3,
  "headline": "已 21 天没联系 · 平均 12 天联系一次 · 1 条跟进任务逾期 3 天",
  "aiTipAvailable": true                // 会员 → 前端可引导去看 AI 解读
}
```

> AI 解读**不在本端点生成** (会长耗时 + 烧额度): 走既有 `POST /api/ai/follow-up`
> (feature key `ai.follow_up`, 非会员 402)。本端点只回 `aiTipAvailable`。

### `GET /api/customers/[id]`
客户详情。

**响应**: `CustomerView` (同 list 项)

### `GET /api/customers/graph`
客户推荐关系图 (客户页图谱数据源)。节点 `{ id, name, referrerId, member }`, 边由 `referrerId` 派生。

- `referrerId`: 推荐人 `customer.id`, `null` = 根/孤儿
- `member` (2026-09-21 加): 该客户同手机号账号是不是会员 (口径同列表的 `isMember`)
- 手机号 / 健康数据**不返回** (PII 最小化); 上限 1000 节点

### `POST /api/customers`
创建客户。

**Body**:
```json
{
  "name": "王女士",                    // 必填
  "phone": "13912345678",              // 必填, 11 位
  "gender": "F",                       // 可选: M/F/U
  "birthYear": 1985,                   // 可选
  "healthTags": ["肩颈", "睡眠差"],     // 可选
  "diseaseHistory": "无",              // 可选
  "notes": "VIP 客户"                   // 可选
}
```

**响应**: `201` + `CustomerView`

### `PATCH /api/customers/[id]`
更新客户 (部分字段)。

**Body**: 同 POST, 字段可选。

### `DELETE /api/customers/[id]`
软删除 (deleted_at = NOW())。

**响应**: `{ "success": true }`

---

## 4. 养生记录

### `GET /api/wellness-records`
列表 (按 serviceDate 倒序)。

**Query**:
- `customerId` (可选): 按客户筛选
- `limit` / `offset`

**响应**:
```json
{
  "items": [
    {
      "id": "1",
      "customerId": "1",
      "serviceDate": "2026-09-03",
      "serviceItemId": "1",
      "staffId": null,
      "storeId": null,
      "bodyPartIds": ["1", "2"],
      "productUsages": [{ "productId": "1", "quantity": "5.00" }],
      "preCondition": { "pain_level": 8, "sleep_quality": 5 },
      "postCondition": { "pain_level": 4, "sleep_quality": 7 },
      "processNote": "肩颈经络疏通",
      "customerFeedback": "肩膀轻很多",
      "photos": ["/uploads/abc.jpg"],
      "nextAdviceDate": "2026-09-24",
      "createdAt": "2026-09-03T..."
    }
  ],
  "total": 1
}
```

### `GET /api/wellness-records/[id]`
详情 (含关联 bodyPart / product 名称字典映射)。

### `POST /api/wellness-records`
创建。

**Body**:
```json
{
  "customerId": "1",
  "serviceDate": "2026-09-04",
  "serviceItemId": "1",
  "bodyPartIds": ["1", "2"],
  "productUsages": [{ "productId": "1", "quantity": 5 }],
  "preCondition": { "pain_level": 8 },
  "postCondition": { "pain_level": 4 },
  "processNote": "...",
  "customerFeedback": "...",
  "photos": ["/uploads/abc.jpg"],
  "nextAdviceDate": "2026-09-18"
}
```

### `PATCH /api/wellness-records/[id]`
更新 (全字段可选)。

### `DELETE /api/wellness-records/[id]`
硬删除 (级联删 body_part + product 关联)。

---

## 5. 跟进任务

### `GET /api/follow-ups`
列表。

**Query**:
- `status`: pending (默认) / done / cancelled
- `assignedTo` (可选): 按用户筛选
- `limit` / `offset`

### `POST /api/follow-ups`
创建。

**Body**:
```json
{
  "customerId": "1",
  "dueAt": "2026-10-01T10:00:00Z",
  "reason": "复购周期",
  "aiSuggestion": "建议回访",  // 可选
  "assignedTo": "1"              // 可选
}
```

### `PATCH /api/follow-ups/[id]`
完成或取消。

**Body**:
```json
{
  "action": "complete",  // or "cancel"
  "notes": "已联系客户"   // 可选
}
```

---

## 6. 联系记录

### `GET /api/interactions`
按客户查询。

**Query**:
- `customerId` (必填)

### `POST /api/interactions`
创建。

**Body**:
```json
{
  "customerId": "1",
  "type": "phone",  // phone/wechat/visit/holiday_greeting/other
  "summary": "已电话联系",
  "followUpAt": "2026-09-15T10:00:00Z"  // 可选
}
```

---

## 7. 字典

### `GET /api/dictionaries`
所有字典 (9 部位 + 8 服务 + 8 耗材)。

**响应**:
```json
{
  "bodyParts": [{ "id": "1", "name": "肩颈", "description": "..." }],
  "serviceItems": [{ "id": "1", "name": "肩颈经络理疗", "durationMinutes": 60 }],
  "products": [{ "id": "1", "name": "艾草精油", "unit": "ml" }]
}
```

---

## 8. 仪表盘

### `GET /api/dashboard/stats`
4 个统计 + 项目分布。

**响应**:
```json
{
  "stats": {
    "customerCount": 1,
    "thisMonthVisits": 1,
    "pendingFollowUps": 0,
    "totalInteractions": 0
  },
  "distribution": [
    { "serviceItemId": "1", "count": 1 }
  ]
}
```

---

## 9. 报表

### `GET /api/reports/overview`
综合报表 (月度趋势 + 复购周期 + 客户活跃度)。

**响应**:
```json
{
  "monthlyVisits": [
    { "month": "2026-04", "count": 0 },
    { "month": "2026-05", "count": 0 },
    { "month": "2026-09", "count": 1 }
  ],
  "repurchaseIntervals": [
    { "range": "0-30天", "min": 0, "max": 30, "count": 0 },
    { "range": "30-60天", "min": 30, "max": 60, "count": 0 },
    { "range": "60-90天", "min": 60, "max": 90, "count": 0 },
    { "range": "90-180天", "min": 90, "max": 180, "count": 0 },
    { "range": "180天以上", "min": 180, "max": null, "count": 0 }
  ],
  "customerActivity": {
    "newCustomersThis": 1,
    "returningCustomers": 1,
    "totalActiveCustomers": 1
  }
}
```

---

## 10. 照片

### `POST /api/photos`
上传 (base64)。

**Body**:
```json
{
  "base64": "data:image/jpeg;base64,...",
  "mimeType": "image/jpeg"  // 可选, 默认 jpeg
}
```

**响应**:
```json
{
  "filename": "1725436800000-abc123.jpg",
  "url": "/uploads/1725436800000-abc123.jpg",
  "size": 12345
}
```

**限制**: 5MB / 张, 仅 jpeg/png/webp

**GET /uploads/[filename]**: 静态服务

---

## 11. Excel 导入

### `GET /api/import/template`
下载 xlsx 模板 (含示例)。

### `POST /api/import/customers?mode=preview`
multipart/form-data, file=...

**响应**:
```json
{
  "mode": "preview",
  "fileName": "import.xlsx",
  "fileSize": 12345,
  "total": 6,
  "validCount": 4,
  "invalidCount": 2,
  "duplicateCount": 1,
  "results": [
    {
      "rowNumber": 2,
      "data": { "name": "...", "phone": "..." },
      "valid": false,
      "errors": ["手机号格式错误: 12345"],
      "duplicate": false
    }
  ]
}
```

### `POST /api/import/customers?mode=commit`
确认导入 (写 DB + 加密 + 审计)。

**响应**:
```json
{
  "mode": "commit",
  "total": 6,
  "inserted": 4,
  "skipped": 2,
  "errors": [{ "rowNumber": 7, "error": "..." }]
}
```

---

## 12. AI (MiniMax)

### `GET /api/ai/profile/[customerId]`
生成客户画像 (聚合 + AI 总结)。

**响应**:
```json
{
  "customer": { "id": "1", "name": "...", "healthTags": [...] },
  "recentRecords": [...],
  "aiSummary": "...",  // AI 生成的画像
  "aiMock": true,       // true = mock 模式
  "usage": { "promptTokens": 0, "completionTokens": 0, "totalTokens": 0 }
}
```

### `POST /api/ai/follow-up`
生成跟进话术。

**Body**:
```json
{ "customerId": "1", "reason": "复购周期" }
```

**响应**:
```json
{
  "customerId": "1",
  "customerName": "王女士",
  "lastVisit": "2026-09-03",
  "daysSinceLastVisit": 1,
  "avgInterval": null,
  "reason": "复购周期",
  "suggestion": "...",  // AI 话术
  "aiMock": true
}
```

---

## 13. 我的 / 版本 (Flutter 「我的」页)

### `GET /api/me`
当前登录者的完整资料 (账号 + 加盟身份 + 门店 + 数据概览)。
Flutter 「我的」页首屏一次拉完, 只有一个 loading。

**响应**:
```json
{
  "user": {
    "id": "1", "name": "张三", "role": "sales", "roleLabel": "销售员",
    "isActive": true, "createdAt": "2026-09-16T11:37:31.156Z",
    "hasUserRecord": true,
    "avatarUrl": "preset:leaf"
  },
  "phone": { "full": "13800138000", "masked": "138****8000" },
  "store": { "id": "3", "name": "城南店" },
  "franchisee": {
    "id": "75", "name": "宋一鸣",
    "phone": { "full": "13900000175", "masked": "139****0175" },
    "isActive": true, "notes": "A 线负责人",
    "joinedAt": "2026-09-16T11:37:26.315Z",
    "placement": { "side": "left", "sideLabel": "A 线 (左)", "depth": 1, "depthLabel": "第 1 层", "path": "L." },
    "referrer": { "id": "70", "name": "王总", "phone": { "full": "13700000070", "masked": "137****0070" } },
    "downline": { "total": 2, "left": 1, "right": 1, "unknown": 0 }
  },
  "stats": {
    "customerCount": 47, "thisMonthVisits": 13, "pendingFollowUps": 6,
    "totalInteractions": 2, "newCustomersThisMonth": 47
  },
  "dev": { "authSkipped": false, "sessionUserId": "1" }
}
```

**可空块** (客户端必须分块渲染, 不能假设一定有):

| 字段 | null 的含义 |
|---|---|
| `user` | 没查到账号行 (dev mock 登录) |
| `phone` | 账号没绑手机号 |
| `store` | 账号没设默认门店 (多数账号如此) |
| `franchisee` | **未加盟** (合法状态, 不是错误); 软删加盟商也走这支 |
| `stats` | dev 空 session (没有「我」, 不查统计) |

**口径边界**:
- `stats` 跟**客户列表**同一口径 (全库非软删), 不含行级过滤 ——
  客户列表还没接 RBAC, 两块对不上就是页面自己打自己脸。
  切换点在 `src/lib/db/queries/dashboard.ts` 的 `getStatsOverview(ctx)` (传 ctx 即收紧)
- `phone` 同时给 full + masked: masked 给默认展示, full 只在用户点"显示"时用 (自己的号)
- 不返回任何金额/业绩字段 (ADR-0006 边界)

### `PATCH /api/me`
自助改头像 (只此一个字段)。

**Body**:
```json
{ "avatarUrl": "preset:leaf" }
```

| 取值 | 含义 |
|---|---|
| `null` / `""` / 不传 | 恢复默认 (客户端画姓名首字) |
| `"preset:<id>"` | 内置候选头像, id ∈ `leaf blossom tea zen heart sun sprout water` |
| `"/uploads/<file>.jpg"` | 本站上传 (先 `POST /api/photos` 拿 URL), 仅 jpg/png/webp |

**边界**:
- 只接受 `avatarUrl` 一个字段 (多传字段 → 400), 防止客户端顺手改 role/name
- **拒外链** (`http(s)://` / 协议相对): 头像值会变成 `<img src>`, 外链 = 帮第三方跑统计 +
  对方删图就变白框 + 违背数据自托管 (CHARTER §3.2)
- 白名单与归一化在 `src/lib/avatar.ts` (`parseAvatarValue`), 客户端只是提前拦
- 写库走 `user` 表 → `user_audit` 触发器自动写审计日志 (谁/什么时候/改成什么/IP)
- 未登录 → 401 (dev `DEV_SKIP_AUTH` 且无 cookie 时不猜"你是 1 号")

**响应**: `{ "ok": true, "avatarUrl": "preset:leaf" }`

### `PATCH /api/me/password`
自助修改密码 (P2: 首登后改掉初始密码)。

**Body**:
```json
{ "oldPassword": "初始密码", "newPassword": "新密码" }
```

**规则**:
- 新密码至少 8 位, 且同时含字母和数字 (不能与旧密码相同)
- 必须验证旧密码 (错 → 401); 每用户 5 次/分钟限流
- 未设置密码的账号 (老数据) → 400「请联系管理员重置」
- 写库走 `user` 表 → 审计触发器记录 (密码只存 scrypt 哈希)

**响应**: `{ "ok": true }`

> 兼容性: JWT session 策略下改密不会使旧 token 立即失效 (最长 30 天);
> 后续可加 `password_changed_at` 校验 (Phase 2 安全加固)。

### `GET /api/app-version`
服务器版本 + 可下载安装包元数据 (Flutter 「检查更新」)。

**响应**:
```json
{
  "version": "0.2.2",
  "buildNumber": 3,
  "apk": {
    "sizeBytes": 23293494,
    "mtimeLocal": "2026-09-05 05:46:36",
    "md5": "3ae567b7680b78a177e7e4c5d5d3b8a5",
    "downloadPath": "/api/apk-download",
    "downloadUrl": "http://127.0.0.1:3003/api/apk-download"
  }
}
```

- `version` / `buildNumber` 来自 `flutter_app/pubspec.yaml` 的 `version:` (APK versionName 的真源)
- `apk: null` = 服务器上没有可下载的包 (纯 web 部署), 客户端只显示当前版本
- 客户端比对 `package_info_plus` 的本机版本 → 服务器更新才提示 (不做强制升级)

---

## 14. 沙龙 (v0.1.5 Phase 7)

> 场景: 邀约客户参加 聚会/沙龙/健康讲座/答谢会/团建。
> 三种角色: **主理人** (organizer, `salon.organizer_user_id`) / **会务** (staff, `invitation.role_in_salon='staff'`) / **受邀者** (attendee)。
> 手机号仅主理人/会务/本人可见; 受邀者留言仅主理人/会务/本人可见; 草稿沙龙仅主理人可见。

### `GET /api/salons`
我相关的沙龙列表。

**Query**: `role` = `organizing` (我主理的) / `invited` (我受邀的) / `all` (默认); `status` (可选); `includeFinished=0` 只看未结束; `limit`/`offset`
**响应**: `{ items: [SalonView], total }` — 每条含 `viewer` (我的身份/RSVP/带约) + `counts` (统计)。

### `POST /api/salons`
创建沙龙 (创建者 = 主理人)。

**Body** (节选; 全字段见 `src/lib/salon/validation.ts` SalonCreateSchema):
```json
{
  "title": "肩颈调理体验沙龙", "subtitle": "…", "themeTags": ["沙龙","体验"],
  "startAt": "2026-10-01T06:00:00.000Z", "endAt": "…", "registrationDeadlineAt": "…",
  "locationName": "…", "address": "…", "floorRoom": "…", "parkingInfo": "…",
  "transportPublic": "…", "transportDriving": "…", "transportPickup": "…",
  "capacityTotal": 20, "capacityReserved": 0,
  "cateringMealType": "dinner", "cateringCuisine": "…", "cateringDietary": "…",
  "lodgingHotelName": "…", "lodgingContactPhone": "13800138000",
  "feeType": "free", "feeAmountCents": null,
  "agenda": [{ "start": "14:00", "title": "开场" }],
  "registrationFormSchema": [{ "key": "health", "label": "健康状况", "type": "text" }],
  "visibilitySettings": { "attendeeList": "all", "staffContact": "all" },
  "staff":   [{ "name": "会务小张", "phone": "139…", "staffRole": "主持" }],
  "invitees":[{ "name": "客户李", "phone": "138…", "expectedGuestCount": 2 }]
}
```
> 首批 `staff` / `invitees` 可为空; 手机号命中已有 app 用户时自动关联 `inviteeUserId`。

### `GET /api/salons/[id]`
详情 (非参与者 404; 草稿仅主理人可见)。

### `PATCH /api/salons/[id]` / `DELETE /api/salons/[id]` / `POST /api/salons/[id]/cancel`
编辑 (仅主理人) / 软删 / 取消 (status=cancelled, 数据保留)。

### `GET|POST /api/salons/[id]/invitations`
邀请名单 / 添加邀请 (姓名+手机号+身份, 手机号重复 → 409)。

### `PATCH|DELETE /api/salons/[id]/invitations/[invId]`
改状态 (`pending|accepted|tentative|declined|waitlist|attended|absent`) / 实际带约数 / 角色; 移除 = 标记 `cancelled`。

### `POST /api/salons/[id]/rsvp`
受邀者回复。

**Body**: `{ "status": "accepted|declined|tentative", "expectedGuestCount": 3, "notes": "…", "registrationData": {} }`
> `expectedGuestCount` = ★ 受邀者自报「预计能邀约到的人数」; 主理人在管理页手动核对。

### `GET|POST /api/salons/[id]/quotas` + `DELETE /api/salons/[id]/quotas/[quotaId]`
带约任务: 主理人/会务分配 (`assignedToUserId` + `quotaValue` + 可选 `deadlineAt`/`note`; 同人同沙龙 active 唯一, 重复分配 = 更新) / 取消。
**响应含** `expectedGuestCount` (自报) + `guestCount` (已登记二级客人) + `progress = max(两者)`。

### `GET|POST /api/salons/[id]/guests` + `PATCH|DELETE /api/salons/[id]/guests/[guestId]`
二级客人 (非 app 用户): 登记 (关系: client/friend/family/colleague/other; 同沙龙手机号唯一 → 409) / 改状态+实到 / 删除。
> 受邀者只看自己带来的 (`mine=1` 可显式指定); 主理人/会务看全部。

### `GET|POST /api/salons/[id]/activities`
动态流 / 发动态: 主理人+会务可发 `announcement` (公告) 并可指定可见性 (`all|staff|organizer`); 受邀者只能发 `comment`/`question` (visibility 强制 all)。

### `GET|POST /api/salons/[id]/attachments` + `DELETE /api/salons/[id]/attachments/[attId]`
沙龙资料 (先 `POST /api/photos` 拿 URL 再登记) / 删除; 可见性同上。

### `GET /api/salons/[id]/aggregates`
聚合统计 (主理人/会务; 受邀者 404): 报名状态分布 + 预计带约总人数 + 已登记客人 + 名额剩余 + 带约任务总额 (`quotaAssignees`/`quotaTotal`/`quotaExpectedTotal`/`quotaGuestTotal`)。

---

## 15. 用户管理 (管理员, 主人 2026-09-21 拍)

> 入口: APK「我的」→ 关于与帮助 → **用户管理** (仅 `role=admin` 可见; 客户端隐藏只是体验)。
> 为什么做在 APK 不做在 web admin: web admin 冻结中 (ADR-0005), 而建根/看人主人在手机上要做。

### `GET /api/admin/users`

全部注册账号 + 全部加盟节点 (一次拉全, 前端切列表/图谱两种视图)。

```jsonc
{
  "users": [{
    "id": "8", "name": "管理员", "username": null, "role": "admin",
    "isActive": true, "avatarUrl": null,
    "phoneMasked": "199****7866",      // ⚠ 只回打码, 明文不出服务端
    "referralCode": "NP3P3M",
    "member": { "isMember": true, "permanent": true, "until": null },
    "franchiseeId": null,               // null = 未加盟 = 图谱里的独立节点
    "createdAt": "2026-09-19T..."
  }],
  "nodes": [{
    "fid": "75", "name": "杨望", "accountName": "SeedTest-dev用户",
    "parentFid": null, "side": null, "depth": 0, "isRoot": true,
    "userId": "1",                       // null = 历史/脚本造的无账号节点
    "avatarUrl": null, "member": true
  }],
  "summary": {
    "total": 7, "joined": 3, "notJoined": 4, "members": 3,
    "roots": 1, "nodesWithoutAccount": 29
  }
}
```

- 403 = 非管理员 (`code=FORBIDDEN`)
- `member` 现算不落库 (`src/lib/billing/member-flag.ts`): `role='admin'` 或 `member_until > NOW()`
- 节点必须连着**无账号**的一起回: dev 库 32 个节点里 29 个没账号, 只回有账号的 = 图谱断成孤岛
- `nodes[].parentFid` = `franchisee.referrer_id` (父节点 id), **不是**用 `placement_path` 推导。
  多棵树时每个根的 `placement_path` 都是 `''`, 按 path 连父会让 depth=1 的节点同时挂到每个根上
  (实测行数翻倍) → 详见 `docs/backlog.md ⑤` (多根架构问题, 待拍板)

### `POST /api/admin/users/[id]/root` — 建根

主人拍板: 「建根 = 先有账号。admin 能建根, 但要用户先注册」。

```jsonc
// body
{ "note": "杭州西湖店 店长" }   // 必填 2-200 字, 审计留痕
// 201
{ "franchiseeId": "138", "userId": "9", "name": "小王", "rootCount": 2 }
```

**为什么不复用 `POST /api/franchisees` / 三方确认**:

三方确认 = 设置者 + 本人 + **父节点**; 根没有父节点 → 三方里有一方物理不存在,
0 节点时更是两方都不存在。硬塞进状态机会开一条「零确认即执行」的分支 (最容易被后续改动滥用)。
所以建根走 **admin 单方 + 审计**, 与「管理员落位免多方确认」(`§6.5`) 同一条原则;
根一旦存在, 后续节点照旧三方确认 (本接口不碰 `placement_requests`)。

**不变量** (任一条不满足 → 400):

| 条件 | 结果 |
|---|---|
| `note` 空 / 超 200 字 | 400 建根必须填写原因 |
| 目标账号不存在 | 400 目标账号不存在 |
| 目标账号 `is_active=false` | 400 目标账号已停用 |
| 目标账号已有 `franchisee_id` | 400 该账号已经在加盟树里了 (一人一节点) |

**副作用**: `INSERT franchisee (path='', depth=0)` + `UPDATE user.franchisee_id`。
账号侧留痕走 `user` 表的审计触发器 (`audit_log`), `note` 加密存进 `franchisee.notes_encrypted`。

**冒烟**: `npx tsx scripts/smoke-bootstrap-root.ts` (13 项, 含非管理员 403; 幂等自清理)

---

## 错误码

| 状态 | 含义 |
|---|---|
| 200 | 成功 |
| 201 | 创建成功 |
| 302 | 重定向 (Auth.js) |
| 400 | 输入验证失败 (Zod 报错) |
| 401 | 未登录 |
| 404 | 资源不存在 |
| 500 | 服务器内部错误 |

---

## 限流

当前 v0.1.0 **未限流**。Phase 2 加入 (Upstash Redis)。