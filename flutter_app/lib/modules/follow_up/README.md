# modules/follow_up/ — 跟进任务模块 (占位)

> **架构定位** (per [ADR-0007](../../../docs/adr/0007-modular-architecture.md)): 暖客宝 APK 域的业务模块 — **跟进任务管理**.
> 销售员"下次联系客户"的任务列表 + 提醒 + 完成标记.

## ⚠ 当前状态: 占位 (Phase 4 创建空目录)

**当前代码现状** (2026-09-13):
- `core/models/follow_up.dart` — `FollowUp` freezed model (存在)
- `core/services/api.dart` — `followUpApiProvider` (存在)
- **但没有独立 screen** — 跟进任务 UI 当前集成在 `modules/customer/screens/customers_page.dart` 内部 (按到期时间分组显示)
- `core/router/app_router.dart` 里**没有 `/follow-ups` route**

## 占位目录

```
modules/follow_up/
├── README.md       ← 本文件 (说明当前状态)
├── screens/        ← 空 (Phase 4 + .gitkeep)
├── widgets/        ← 空
└── providers/      ← 空
```

## 实施计划 (后续 Phase)

W4+ 启动时实施跟进模块独立化:

1. **抽 widget**: 把 `customers_page.dart` 里的"跟进时间线" widget 提取到 `modules/follow_up/widgets/follow_up_timeline.dart`
2. **新建独立 screen**: `modules/follow_up/screens/follow_ups_page.dart` (全屏跟进列表)
3. **加 route**: `core/router/app_router.dart` 加 `/follow-ups` + Tab 2 (Bottom Nav 从 2 tab 变 3 tab)
4. **共享 model**: `FollowUp` 仍走 `core/models/follow_up.dart` (跨模块共享, 跟 customer 共用)
5. **跨模块**: customer 模块的 detail page 时间线**调用** `follow_up` 模块的 widget (通过 core/ 共享 model)

## 为什么不立即实施

- 当前 `customers_page.dart` 内部集成跟进 UI, 工作良好 (Plan F2 验证过)
- 拆独立模块需要重新设计 Bottom Navigation (用户已习惯 2 tab), **不是简单抽 widget**
- Phase 4 (占位) + 后续 Phase 增量实施 = 避免一次大重构破坏现有用户体验

## 关联文档

- [ADR-0007 §实施路线图](../../../docs/adr/0007-modular-architecture.md#实施路线图-incremental)
- AGENTS §4.5 模块化约束
- W4 启动时 (内测前) 拍板: 立即抽 follow_up 独立模块 vs 维持集成
