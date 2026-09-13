# core/ — APK 底座 (不可替换的基建)

> **架构定位** (per [ADR-0007](../../docs/adr/0007-modular-architecture.md)): 暖客宝 APK 域的**底座**, 包含跨业务模块共享的基建. 任何修改都应保持**接口稳定**, 以免影响 `modules/` 下的所有业务模块.

## 目录结构

```
core/
├── router/                 ← go_router 配置 + 全局 redirect
│   └── app_router.dart
├── providers/              ← 共享 Riverpod providers
│   ├── auth_provider.dart        ← 当前登录用户状态
│   └── service_providers.dart    ← 共享 service provider (api_client / api)
├── http/                   ← dio + 拦截器 + 错误处理
│   └── api_client.dart
├── services/               ← 共享 services (供 modules 调用)
│   └── api.dart                  ← 所有后端 API 入口
├── theme/                  ← Material 3 养生绿主题
│   └── app_theme.dart
├── models/                 ← 共享 freezed models (跨模块)
│   ├── customer.dart
│   ├── wellness_record.dart
│   ├── follow_up.dart
│   ├── dictionaries.dart
│   ├── dashboard.dart
│   └── franchisee.dart
└── widgets/                ← 共享 widgets (跨模块)
    ├── big_button.dart
    ├── big_fab.dart
    ├── customer_graph_view.dart
    ├── customer_row.dart
    ├── empty_state.dart
    ├── franchise_chip.dart
    ├── franchise_node_sheet.dart
    ├── franchise_tree_painter.dart
    ├── rating_slider.dart
    └── wellness_photo_uploader.dart
```

## 规则 (per AGENTS §4.5)

- ✅ **必须稳定**: 这里的接口 (`authProvider` / `apiClientProvider` / `AppTheme` 等) 一旦被 `modules/` 引用, 不能轻易改签名
- ❌ **禁止业务逻辑**: 不放业务代码, 只放基建 (e.g. `api_client.dart` 只做 dio 配置, 不做 API 调用)
- ❌ **禁止反向依赖**: `core/` 绝不能 `import 'modules/...'`. 只能 `import 'package:...'` 或 `core/` 内部

## 扩展指南

**新增共享 widget** (e.g. 通用 loading indicator):
1. 在 `core/widgets/` 下新建 `.dart` 文件
2. 在模块中通过 `import 'package:nuankebao/core/widgets/loading.dart'` 引用

**新增共享 service** (e.g. 文件上传):
1. 在 `core/services/` 下新建 `.dart` 文件, 注入 `apiClientProvider`
2. 在 `core/providers/service_providers.dart` 中导出 provider

**新增共享 provider** (e.g. 全局计数器):
1. 在 `core/providers/` 下新建 `.dart` 文件
2. 业务模块通过 `ref.watch(globalCounterProvider)` 引用
