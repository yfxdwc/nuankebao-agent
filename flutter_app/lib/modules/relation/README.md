# modules/relation/ — 客户/加盟关系模块 ★ v0.1.3 重点

> **架构定位** (per [ADR-0007](../../../docs/adr/0007-modular-architecture.md)): 暖客宝 APK 域的**客户/加盟关系模块**.
> 这是 v0.1.3 架构重构的 ★ 重点模块 —— 把"关系系统"抽成可替换的接口, 未来想换「分销」「会员等级」「上下级」等其他关系系统时**零改动调用方**.

## ★ 核心抽象: RelationSystem 接口

**接口定义** (`lib/relation_system.dart`):

```dart
abstract class RelationSystem {
  String get name;
  Future<List<RelationNode>> getGraph(String rootId);
  Future<RelationNode?> getNode(String nodeId);
  Future<List<RelationNode>> getChildren(String parentId);
  Future<void> addRelation({required String fromId, required String toId, required RelationType type});
  Future<void> removeRelation({required String fromId, required String toId});
  Future<List<RelationPath>> findPaths({required String fromId, required String toId});
}
```

7 个方法契约, 任何关系系统 (加盟 / 分销 / 会员 / 上下级) 都必须实现.

**数据契约** (`lib/relation_node.dart`):

```dart
enum RelationType { parent, child, peer, manager, referral }

class RelationNode {
  final String id;
  final String name;
  final String? avatarUrl;
  final Map<String, dynamic> metadata; // 业务字段
}

class RelationPath {
  final List<RelationNode> nodes;
  final List<RelationType> edges;
}
```

## 入口

| 入口 | 文件 | 说明 |
|---|---|---|
| **加盟网络图谱** | `screens/franchise_tree_page.dart` | `FranchiseTreePage` — 我的二叉树视图 |
| **加盟商详情** | `screens/franchisee_detail_page.dart` | `FranchiseeDetailPage` — 单个加盟商详情 |
| **新增加盟商** | `screens/add_franchisee_page.dart` | `AddFranchiseePage` — 新增 (强绑 parentId) |

## lib/ 接口实现

| 文件 | 职责 |
|---|---|
| `lib/relation_system.dart` | abstract class RelationSystem (★ 接口) |
| `lib/relation_node.dart` | RelationNode / RelationType / RelationPath 数据类 |
| `lib/franchise_relation.dart` | FranchiseRelationSystem implements RelationSystem (★ 默认实现) |
| `lib/relation_system_provider.dart` | `relationSystemProvider` (★ 切换点) |
| `lib/relation_graph_provider.dart` | `myRelationGraphProvider` (Phase 6 后续: 调用方重构后用) |

## 默认实现: FranchiseRelationSystem

`FranchiseRelationSystem` 内部**包装** `FranchiseeService` (在 `core/services/api.dart`), 把 Franchisee/FranchiseeTreeNode 适配成 RelationNode.

```dart
class FranchiseRelationSystem implements RelationSystem {
  final FranchiseeService _service;
  FranchiseRelationSystem(this._service);

  @override String get name => 'franchise';

  @override
  Future<List<RelationNode>> getGraph(String rootId) async {
    final tree = await _service.getMyTree(depth: 3);
    return _flattenTree(tree); // FranchiseeTreeNode → List<RelationNode>
  }
  // ... 其他 6 个方法类似
}
```

## ★ 切换关系系统的步骤 (零调用方改动)

**示例**: 主人想从「加盟关系」换成「分销关系」:

1. 新建 `lib/distribution_relation.dart`:
   ```dart
   class DistributionRelationSystem implements RelationSystem {
     final DistributionService _service;
     DistributionRelationSystem(this._service);
     @override String get name => 'distribution';
     // ... 7 个方法实现 (调 DistributionService 包装返回 RelationNode)
   }
   ```

2. 改 `lib/relation_system_provider.dart` 一行:
   ```dart
   final relationSystemProvider = Provider<RelationSystem>((ref) {
     final svc = ref.watch(distributionServiceProvider); // ← 改注入
     return DistributionRelationSystem(svc); // ← 改实现
   });
   ```

3. 调用方 (`franchise_tree_page.dart` 等)**零改动** —— 自动拿到 DistributionRelationSystem.

## 路由

| 路径 | 名称 | 说明 |
|---|---|---|
| `/franchise-tree` | `franchise-tree` | 我的加盟网络 (图谱) |
| `/franchisees/:id` | `franchisee-detail` | 加盟商详情 |
| `/franchisees/new?parentId=X` | `franchisee-new` | 新增加盟商 (强绑 parent) |

## 依赖 (走 core/ 底座)

- `core/providers/service_providers.dart` — `franchiseeServiceProvider` (★ 通过 relationSystemProvider 间接注入)
- `core/models/franchisee.dart` — Franchisee/FranchiseeTreeNode (后端数据形状)
- `core/services/api.dart` — FranchiseeService (★ v0.1.3 不删, FranchiseRelationSystem 适配层依赖)
- `core/theme/app_theme.dart` — 配色
- `core/widgets/franchise_chip.dart` — 通用 chip (4 模块共用, 留在 core/)
- `../presentation/graph/widgets/franchise_node_sheet.dart` — 节点 sheet (跨模块调用 presentation)
- `../presentation/graph/widgets/franchise_tree_painter.dart` — 树 painter (跨模块调用 presentation)

## ⚠ Phase 6 简化说明

**当前状态** (Phase 6 完成):
- ✅ RelationSystem 接口契约完整
- ✅ FranchiseRelationSystem 默认实现完整
- ✅ relationSystemProvider 注入点就位
- ✅ 3 个 screen 迁到 modules/relation/screens/
- ⚠ **调用方 (3 个 screen) 仍用 `myFranchiseeTreeProvider` (旧), 没走 RelationSystem**

**Phase 6.5+ 工作**:
1. 改造 `franchise_tree_page.dart` 用 `myRelationGraphProvider` 拿 `List<RelationNode>`, 重新渲染
2. 改造 `franchisee_detail_page.dart` 用 `relationSystemProvider.getNode(id)` 替代 `franchiseeServiceProvider.getById(id)`
3. 改造 `add_franchisee_page.dart` 用 `relationSystemProvider.addRelation(...)` 替代 `franchiseeServiceProvider.create(...)`
4. 删 `core/providers/service_providers.dart` 里的 `myFranchiseeTreeProvider` (改为 relation 模块内)

为什么 Phase 6 简化:
- 调用方改造涉及 UI 重构 (List<RelationNode> vs FranchiseeTreeNode 渲染逻辑不同)
- Phase 6 优先把"接口契约 + 默认实现 + 切换点"建好, 这是架构的核心
- 后续 phase 增量改造调用方, 风险小, 易回滚

## 扩展指南

**新增"推荐人关系"维度** (Phase X):
1. 改 `core/models/franchisee.dart` 加 `referralChain` 字段
2. ⚠ Schema 演进红线 (CHARTER §3.5): 加列必须 DEFAULT 或 nullable
3. FranchiseRelationSystem 在 `getGraph` 时把 referralChain 塞进 RelationNode.metadata
4. UI 渲染读 metadata.referralChain

## 关联文档

- [CHARTER §4.3 客户/加盟关系模块 ★](../../../docs/CHARTER.md#43-模块化规则-v013-新增)
- [ADR-0007 §详细方案 + RelationSystem 接口设计](../../../docs/adr/0007-modular-architecture.md)
- [Hexagonal Architecture (Ports and Adapters)](https://alistair.cockburn.us/hexagonal-architecture/) — RelationSystem 抽象的灵感来源
