# 使用数据采集模块 (usage analytics, v0.1.5)

> **拍板**: 主人 2026-09-22 —— 「需要有对真实用户的完整全面的使用数据收集模块」
> ① 同意模式 = **内部工具强制开启** ② 原始事件 **180 天**后删 ③ 范围 = 4 片全做
> ④ web admin 解冻, 新模块接入 web admin
>
> **关联**: [CHARTER §4.4.5 用量红线](../CHARTER.md) · [ADR-0017](../adr/0017-web-admin-unfreeze.md) ·
> [api.md §17](./api.md) · 后端 `src/lib/usage/` · 前端 `flutter_app/lib/core/telemetry/`

---

## 1. 这模块回答什么问题

| 层 | 指标 | 位置 |
|---|---|---|
| 留存 | 活跃用户 / 活跃天 / DAU 趋势 | /admin/usage |
| 功能 | 事件排行 / 页面排行 | /admin/usage |
| **AI** | 四张卡片各自的点击 / 成功 / 失败 / 重生成 / 耗时 | /admin/usage |
| 漏斗 | 客户详情 → AI 生成 → 建跟进 → 完成跟进 | /admin/usage |
| 用户 | 谁在用 / 谁几天没用了 / 各人用了哪些功能 | /admin/usage「按用户」 |
| 失败 | API 错误 Top (按 path/状态码) | /admin/usage「报错 Top」 |

CLI 版: `npx tsx scripts/usage-report.ts 30 --events=20`

## 2. 红线 (不可协商)

- ❌ 不采姓名 / 手机号 / 疾病史 / 养生内容 / 自由文本 —— props 只允许 ID、枚举、计数、时长
- ❌ 不接第三方 (Firebase / GA / Sentry) —— 数据只落自有 PG (CHARTER §2)
- ❌ 不在 dev / web preview 采集 —— 只有 **release APK** 上报 (`NUANKEBAO_TELEMETRY` 可临时覆盖)
- ✅ 服务端双层防御: 词表校验 + props 白名单 + slug 正则 + 手机号 regex 兜底
- ✅ 保留期 180 天 (`USAGE_RETENTION_DAYS`), 每日 04:30 systemd timer 清理

## 3. 数据流

```
Flutter release APK
  core/telemetry/usage_service.dart
    队列 (shared_preferences, ≤500) ──60s / 切后台 / 满 20 条──▶ POST /api/usage/events
                                                                      │ 清洗 (src/lib/usage/sanitize.ts)
                                                                      ▼
                                                               usage_event 表 (append-only)
                                                                      │ 聚合 (queries/usage.ts)
                                       ┌──────────────────────────────┼───────────────────────────┐
                                       ▼                              ▼                           ▼
                              /admin/usage (SSR 页)          GET /api/admin/usage/*        scripts/usage-report.ts
```

- 幂等: 每条事件带客户端随机 `event_id`, 服务端唯一索引 + `ON CONFLICT DO NOTHING` (重传安全)
- 表**不挂审计触发器**: 它自身就是行为留痕 (挂上 = 双倍写入)
- 服务端 `server_ts` 为准; 客户端时间戳偏离 > 7 天丢弃

## 4. 加一个新事件 (双端契约, 必须同步)

1. **服务端词表**: `src/lib/usage/catalog.ts` 加 `NAME: { category, props: [...] }`
2. **客户端词表**: `flutter_app/lib/core/telemetry/usage_events.dart` 同步加同一条
3. **埋点**: Flutter 侧 `ref.read(usageServiceProvider).track('NAME', ...)` (有 props 时只传白名单键)
4. **测试**: `tests/usage-events.test.ts` 补一条 (可选但推荐)
5. 改完跑: `npx tsx scripts/smoke-usage-events.ts` (需 dev server) + `flutter test`

> ⚠ 服务端**拒绝**词表外事件 (rejected+1) —— 只改一端 = 数据静默丢失。
> Flutter debug 构建下词表外事件会触发断言提醒 (`usage_service.dart`)。

## 5. 运维

| 事项 | 操作 |
|---|---|
| 看数据 | web: `/admin/usage`; CLI: `npx tsx scripts/usage-report.ts [天数] [--events=N]` |
| 保留期演练 | `npx tsx scripts/usage-retention.ts --dry-run` |
| 立即清理 | `bash deploy/run-usage-retention.sh` (优先生产库, 退回 dev) |
| 定时清理 | `deploy/systemd/nuankebao-usage-retention.{service,timer}` (每日 04:30, Persistent) |
| 生产库清理路径 | compose `migrate` 镜像跑 (只有它带 tsx + 完整源码; 见 `deploy/run-usage-retention.sh`) |

## 6. 已知边界 / 后续可选

- `props` 里不放自由文本 → AI 生成内容质量类分析做不了 (需要另一套"抽样文本 + 脱敏"决策, 当前不做)
- 会话时长 = 同 session 首末事件间隔 (切后台不断会话, 长挂设备会高估) —— 当前 1-2 用户量级够用
- 长期趋势 (>180 天) 需要 `usage_daily` 汇总表 (当前不做)
- OS 版本 / 设备型号当前为 null (避免新增 `device_info_plus` 依赖); 需要时再加
