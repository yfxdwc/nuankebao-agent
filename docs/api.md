# 暖客宝 API 文档 (v0.1.0)

> 16 个 REST API 端点
> Base URL: `http://127.0.0.1:3003/api` (开发) / `https://nuankebao.tooyang.top/api` (生产)
> 认证: Auth.js v5 session cookie (`authjs.session-token`)

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
登录 (form-urlencoded)。

**Body**:
```
csrfToken: string
phone: string (11 位)
code: string (6 位, 开发期 123456)
callbackUrl: string
```

**响应**: `302` + Set-Cookie `authjs.session-token`

### `POST /api/auth/signout`
登出。

---

## 3. 客户

### `GET /api/customers`
客户列表 (分页 + 搜索)。

**Query**:
- `search` (可选): 按姓名/手机号搜索
- `limit` (默认 20)
- `offset` (默认 0)

**响应**:
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
      "updatedAt": "2026-09-03T..."
    }
  ],
  "total": 1
}
```

### `GET /api/customers/[id]`
客户详情。

**响应**: `CustomerView` (同 list 项)

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
    "hasUserRecord": true
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