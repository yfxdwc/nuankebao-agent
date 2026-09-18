# modules/salon/ — 沙龙模块 (v0.1.5 Phase 7, 已实施)

> **架构定位** (per [ADR-0007](../../../docs/adr/0007-modular-architecture.md)): 暖客宝 APK 域的**沙龙模块**。
> 场景: 销售员 / 公司主理的 **聚会 / 沙龙 / 健康讲座 / 客户答谢会 / 团建** —— 邀约客户参加, 也可被邀约。
> 命名沿革: 占位期叫 `modules/meeting/` (会议组织); 主人 2026-09-18 拍板一级页面名 = **沙龙**
> (行业气质贴合 + 覆盖 沙龙/讲座/品鉴/答谢/团建/培训 + 避免 meeting 的商务例会歧义), 模块随之改名。

## 角色与核心机制

| 角色 | 说明 | 能做什么 |
|---|---|---|
| **主理人** (organizer) | 创建沙龙的人 (`salon.organizer_user_id`) | 编辑全部信息 / 邀请 / 分配带约任务 / 看聚合 / 核销到场 / 取消 |
| **会务** (staff) | 主持人 / 讲师 / 摄影 / 后勤 (`invitation.role_in_salon='staff'`) | 邀请 / 分配任务 / 看聚合 / 发公告 |
| **受邀者** (attendee) | 被邀的客户 / 潜在客户 / 同事 | RSVP (接受/待定/婉拒) / 填**预计能邀约到的人数** / 留言提问 / 登记自己带来的二级客人 |

**带约机制 (主人 2026-09-18 拍: 简单版)**: 受邀者自报「预计带约人数」(`expected_guest_count`),
主理人手动核对 (事后补 `actual_guest_count`)。不做全链追踪 / 不做自动分账。
主理人可给受邀者分配带约任务 (`salon_quota`), 进度 = `max(自报数, 已登记二级客人数)` (粗口径, 供主理人看一眼)。

**非 app 用户**: 受邀者 / 二级客人可以是没装 app 的人 (只存姓名 + 手机号, 手机号走应用层加密 + hash 去重)。
手机号仅 **主理人 / 会务 / 本人** 可见; 受邀者之间互相看不到手机号。

## 目录结构

```
modules/salon/
├── README.md              ← 本文件
├── screens/
│   ├── salon_list_page.dart     列表 (2 tab: 我受邀的 / 我主理的) + 创建入口
│   ├── salon_detail_page.dart   详情 (按角色显示不同区块 + RSVP + 我带来的人)
│   ├── salon_form_page.dart     创建/编辑 (4 步向导: 基础 → 时间地点 → 服务安排 → 会务日程发布)
│   ├── salon_manage_page.dart   主理人管理 (报名情况 / 邀请名单 / 带约任务 / 到场核销)
│   └── salon_guests_page.dart   二级客人管理 (按带约人分组 + 状态/到场)
├── providers/salon_providers.dart  全部 provider + invalidateSalon(ref, salonId)
└── widgets/
    ├── salon_card.dart          列表卡片
    ├── salon_status_chip.dart   状态胶囊
    ├── salon_section.dart       详情区块 / 信息行
    └── salon_rsvp_sheet.dart    RSVP 弹层 (接受/待定/婉拒 + 预计带约人数 + 留言)
```

## 路由

| 路径 | 页面 | 入口 |
|---|---|---|
| `/salons` | 沙龙列表 (Bottom Nav 第 2 tab) | 底部导航 |
| `/salons/:id` | 沙龙详情 | 列表卡片 |
| `/salons/new` | 创建沙龙 | 列表 FAB |
| `/salons/:id/edit` | 编辑沙龙 (仅主理人) | 详情 AppBar |
| `/salons/:id/manage` | 管理 (主理人/会务) | 详情 AppBar |
| `/salons/:id/guests` | 二级客人管理 | 管理页 |

## 数据模型 (后端, `src/lib/db/schema.ts`)

| 表 | 作用 |
|---|---|
| `salon` | 沙龙主表: 基础/时间/地点/交通/餐饮/住宿/着装/费用/人数/日程 jsonb/报名表单 schema/可见性 |
| `salon_invitation` | 邀请 (受邀者 + 会务): 手机号加密 + hash (同沙龙唯一), RSVP 状态, 自报带约数, 留言 |
| `salon_quota` | 带约任务: 主理人/会务 → 受邀者, `is_active` 唯一 (同人同沙龙 1 条) |
| `salon_guest` | 二级客人 (非 app 用户): 谁带来的 + 关系 + 状态 + 实到 |
| `salon_activity` | 动态: 系统消息 / 公告 / 留言 / 提问 + 可见性 |
| `salon_attachment` | 资料: 名称 + URL (走 `/api/photos` 产物) + 可见性 |

Migration: `drizzle/0008_rich_ink.sql` (+ `drizzle/down/0008_rich_ink.down.sql`)。
审计触发器: `salon` / `salon_invitation` / `salon_guest` / `salon_quota` (见 `drizzle/audit_trigger.sql`)。

## API (`src/app/api/salons/**`, 共 14 个 route)

```
GET/POST   /api/salons                      列表 (role=organizing|invited|all) / 创建
GET/PATCH/DELETE /api/salons/:id            详情 / 编辑 / 软删
POST       /api/salons/:id/cancel           取消 (status=cancelled)
GET/POST   /api/salons/:id/invitations      邀请名单 / 添加邀请 (重复手机号→409)
PATCH/DELETE /api/salons/:id/invitations/:invId  改状态/角色 / 移除 (标记 cancelled)
POST       /api/salons/:id/rsvp             RSVP (status + expectedGuestCount + notes)
GET/POST   /api/salons/:id/quotas           带约任务 / 分配 (upsert)
DELETE     /api/salons/:id/quotas/:quotaId  取消任务
GET/POST   /api/salons/:id/guests           二级客人 / 登记 (重复→409)
PATCH/DELETE /api/salons/:id/guests/:guestId 改状态/到场 / 删除
GET/POST   /api/salons/:id/activities       动态 / 发公告(主理人/会务)或留言
GET/POST   /api/salons/:id/attachments      资料 / 登记
DELETE     /api/salons/:id/attachments/:attId 删除资料
GET        /api/salons/:id/aggregates       聚合统计 (主理人/会务; 受邀者 404)
```

## 可见性规则 (后端 enforce, 前端只是渲染)

| 数据 | 主理人 | 会务 | 受邀者 |
|---|---|---|---|
| 沙龙详情 (草稿) | ✅ | ❌ (看不到) | ❌ (看不到) |
| 受邀名单 | ✅ 全部 | ✅ 全部 | 按 `visibility_settings.attendeeList` |
| 受邀者手机号 | ✅ | ✅ | 仅自己 (会务电话按 `staffContact`) |
| 受邀者留言 | ✅ | ✅ | 仅自己 |
| 二级客人列表 | ✅ 全部 | ✅ 全部 | 仅自己带来的 |
| 聚合统计 | ✅ | ✅ | ❌ 404 |
| 公告 (visibility=staff) | ✅ | ✅ | ❌ |

## 关联文档

- [CHARTER §4 域划分](../../../docs/CHARTER.md) + [ADR-0007 模块化架构](../../../docs/adr/0007-modular-architecture.md)
- 后端 queries: `src/lib/db/queries/salon.ts` + 校验 `src/lib/salon/validation.ts`
- 单测: `tests/salon.test.ts` (18 例: 权限负例 / RSVP / 带约 / 二级客人 / 可见性)
