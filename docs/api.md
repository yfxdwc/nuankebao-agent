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