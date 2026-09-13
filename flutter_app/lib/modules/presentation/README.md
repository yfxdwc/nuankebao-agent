# modules/presentation/ — 展示层 (graph + list)

> **架构定位** (per [ADR-0007](../../../docs/adr/0007-modular-architecture.md)): 暖客宝 APK 域的**展示层模块**.
> 不同于其他 modules 是"业务模块", presentation 是**渲染抽象层** —— 把"图谱"和"列表"两种通用展示方式抽出来, 跨业务模块复用.

## 设计原则

**业务模块 (customer / wellness / relation) 提供数据**, presentation 模块**提供渲染 widget**.
调用模式: 业务 screen 拿到数据 → 调用 presentation widget → 渲染.

## 子模块

### graph/ — 图谱渲染 (Phase 5 已实施)

| 入口 | 文件 | 用途 |
|---|---|---|
| **节点 sheet** | `widgets/franchise_node_sheet.dart` | 点击图谱节点弹出节点详情 |
| **树 painter** | `widgets/franchise_tree_painter.dart` | CustomPainter 画加盟树 (中老年大字节点) |

**注意**: `core/widgets/franchise_chip.dart` 是 4 模块共用的通用 chip widget, **不**在本模块 (留 core/).

### list/ — 列表组件 (Phase 5 占位)

| 入口 | 文件 | 用途 |
|---|---|---|
| (空) | `widgets/.gitkeep` | 占位, 等 list widget 抽出来 |

**当前状态**: 列表组件分散在 customer/wellness 模块内部 (如 `modules/customer/widgets/customer_row.dart`).
**未来**: 跨模块共用的列表组件 (debounce / infinite scroll / filter chip) 放这里.

## 跨模块调用规则

业务模块**可以**调用 presentation widget (presentation 是"服务"角色):

```dart
// ✅ modules/relation/screens/franchise_tree_page.dart
import '../../../modules/presentation/graph/widgets/franchise_tree_painter.dart';
import '../../../core/models/franchisee.dart';

// 拿到数据 (RelationNode 列表)
final graph = await ref.read(relationSystemProvider).getGraph(rootId);

// 用 presentation widget 渲染
CustomPaint(painter: FranchiseTreePainter(nodes: graph, ...))
```

❌ **禁止反向**: presentation **不能** import 任何业务模块 (如 `modules/customer/...`).

## 扩展指南

**新增"饼图"渲染** (Phase 2 报表用):
1. 在 `widgets/` 下新建 `pie_chart_painter.dart`
2. 业务模块 (e.g. dashboard) 调用此 painter

**抽通用 list widget** (Phase X):
1. 从 `modules/customer/widgets/customer_row.dart` 抽象出 `presentation/list/widgets/data_row.dart`
2. customer / wellness / franchise 都改用 `DataRow`

## 关联文档

- [CHARTER §4.3 模块化规则](../../../docs/CHARTER.md#43-模块化规则-v013-新增)
- [ADR-0007 §1. APK 域目录最终结构](../../../docs/adr/0007-modular-architecture.md)
