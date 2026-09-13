# modules/customer/ — 客户模块

> **架构定位** (per [ADR-0007](../../../docs/adr/0007-modular-architecture.md)): 暖客宝 APK 域的核心业务模块 — **客户档案管理**.
> 大健康销售日常 80% 时间在这个模块: 查客户 / 录客户 / 看客户的所有历史.

## 入口

| 入口 | 文件 | 说明 |
|---|---|---|
| **客户列表** | `screens/customers_page.dart` | `CustomersPage` — 列表 + 搜索 + 客户图谱入口 |
| **新增养生记录 sheet** | `screens/add_record_sheet.dart` | `AddRecordSheet` — 客户详情中的快捷录入 |

## 模块私有 widget

| Widget | 文件 | 用途 |
|---|---|---|
| `BigFab` | `widgets/big_fab.dart` | 客户列表底部"+ 新增" 大按钮 (中年女性友好) |
| `CustomerGraphView` | `widgets/customer_graph_view.dart` | 客户图谱视图 (关系 + 互动时间线) |
| `CustomerRow` | `widgets/customer_row.dart` | 客户列表行 (头像 + 姓名 + 标签) |

## 依赖 (走 core/ 底座)

- `core/providers/service_providers.dart` — `customerApiProvider` (调 `api.dart` 客户域 API)
- `core/models/customer.dart` — `Customer` freezed model
- `core/models/wellness_record.dart` — `WellnessRecord` freezed model
- `core/theme/app_theme.dart` — 配色
- `core/widgets/big_button.dart` — 通用大按钮 (其他模块共用)
- `core/widgets/empty_state.dart` — 通用空状态 (其他模块共用)
- `core/widgets/franchise_chip.dart` — 加盟关系标签 (其他模块共用)

## 路由

- `/customers` — `CustomersPage` (在 `core/router/app_router.dart` 注册)

## 扩展指南

**新增"客户标签管理"功能**:
1. 在 `screens/` 下新建 `customer_tags_page.dart`
2. 在 `core/router/app_router.dart` 加 `/customers/tags` 路由
3. 在 `core/services/api.dart` 加 `getCustomerTags` / `updateCustomerTags` API 方法
4. 模块私有 widget (如 tag chip) 放 `widgets/tag_chip.dart`

**改进列表性能**:
- `widgets/customer_row.dart` 加 lazy build
- `screens/customers_page.dart` 加 debounce 搜索

## 关联模块

- **modules/wellness/** — 养生记录 (客户详情时间线的一部分)
- **modules/follow_up/** — 跟进任务 (客户详情时间线的一部分)
- **modules/presentation/** — 图谱 + 列表 (将来从 customer 模块拆出)

## 关联文档

- [CHARTER §4.3 模块化规则](../../../docs/CHARTER.md#43-模块化规则-v013-新增)
- [ADR-0007 §详细方案](../../../docs/adr/0007-modular-architecture.md)
