# modules/meeting/ — 会议组织模块 (占位)

> **架构定位** (per [ADR-0007](../../../docs/adr/0007-modular-architecture.md)): 暖客宝 APK 域的**会议组织模块** (占位, 未实施).
> 未来扩展: 销售员组织客户沙龙 / 健康讲座 / 团建活动 / 客户答谢会等场景的会议管理功能.

## 当前状态: 占位 (Phase 7 创建空目录)

**当前代码现状** (2026-09-13):
- ❌ 无任何会议相关代码
- ❌ 无 model (在 core/models/)
- ❌ 无 service (在 core/services/api.dart)
- ❌ 无 screen
- ❌ app_router.dart 无 /meetings route

## 占位目录

```
modules/meeting/
├── README.md          ← 本文件
├── screens/           ← 空 (.gitkeep)
├── widgets/           ← 空
└── providers/         ← 空
```

## 实施计划 (W4+ 启动时拍板)

未来要做会议组织功能时:

1. **schema**: 加 `meetings` 表 (`title` / `startAt` / `location` / `customerIds` / `notes`)
   - ⚠ Schema 演进红线 (CHARTER §3.5): 加表本身 OK, 但加 NOT NULL 列必须 DEFAULT
2. **model**: `core/models/meeting.dart` (shared, 跨模块)
3. **service**: `core/services/api.dart` 加 `MeetingService` (CRUD + 参与者管理)
4. **screens**: `modules/meeting/screens/` (列表 / 详情 / 新增)
5. **route**: app_router.dart 加 `/meetings` + Bottom Nav 第 3 tab (从 2 tab 变 3 tab)
6. **跨模块**: customer 模块的 detail page 加"该客户参加的会议"时间线

## 为什么不立即实施

- W4 启动时 (内测前) 才决定是否做 (业务优先级)
- 当前 1-2 销售内测场景, 会议功能 ROI 不明确
- 占位目录保留扩展点, 不影响现有 APK 编译

## 关联文档

- [ADR-0007 §实施路线图](../../../docs/adr/0007-modular-architecture.md#实施路线图-incremental)
- AGENTS §4.5 模块化约束
- W4 启动时拍板: 立即做 vs 推迟到 Phase 2 (AI Copilot 之后)
