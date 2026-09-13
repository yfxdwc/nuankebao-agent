# ADR-0007: 底座 + 模块化插件架构 (BASE + MODULAR PLUGINS)

**日期**: 2026-09-13
**状态**: ✅ Accepted (主人 ask_user 拍板)
**决策者**: 主人 (虾王)
**影响范围**: APK 域目录结构 + WEB 域模块清单 + 客户/加盟关系模块接口 + 后续模块迁移节奏
**对应元宪法**: [`CHARTER.md`](../CHARTER.md) §4 (待更新 v0.1.3) + §10.2 变更记录

## 上下文

本决策对应元宪法:

- [`CHARTER.md`](../CHARTER.md) **§2 原则 7** (小步快跑 > 一次大跃) — 一次只挪一个模块
- [`CHARTER.md`](../CHARTER.md) **§4** (域划分) — 现有"五大业务域"边界偏软, 域内模块组织方式不规范
- [`CHARTER.md`](../CHARTER.md) **§5.1 决策等级** — 架构变更属 L1 战略决策, 必须 ask_user 拍板

---

## 问题

W2-3 阶段 Flutter 移动端开发过程中, 项目暴露了三大结构性问题 (2026-09-13 主人 feedback):

### 1. APK 域模块边界缺失

`flutter_app/lib/screens/` 目录平铺 12 个 screen, 包括:

- `franchise_tree_page.dart` / `add_franchisee_page.dart` / `franchisee_detail_page.dart` (加盟关系)
- `customers_page.dart` / `wellness_record_detail_page.dart` / `wellness_record_form_page.dart` (客户/养生)
- `auth/login_screen.dart` (登录)
- `profile_page.dart` (个人中心)

这些 screen 分属不同业务线, 但**没有任何模块边界**. 改进一个模块 (e.g. 图谱可视化) 时容易影响其他模块, 缺乏"独立优化 / 独立替换"的可能性.

### 2. 客户/加盟关系耦合在 customer 业务中

当前 `franchisee_*` 三个 screen 与 customer 业务直接耦合, **没有抽象为可替换的关系系统**. 主人原话:

> "客户/加盟关系独立模块, 以后如果换成其他公司的不同节点关系系统方便修改或切换"

暗示: 加盟关系只是其中一种可能的节点关系系统, 未来可能换成分销关系 / 会员等级 / 上下级 / 师徒等其他关系系统. 当前架构**没有为此预留切换接口**.

### 3. WEB 域职责不清

WEB 端同时是产品 (`src/app/admin/`, freeze) 和脚手架 (`src/app/preview/` + `src/app/app-preview/`), 但作为脚手架的"开发域模块"散落在:

| 模块 | 物理位置 |
|---|---|
| 任务快照 | `scripts/task-snapshot.sh` + `.pi/extensions/auto-task-snapshot.ts` |
| 同类项目借鉴关注 | `docs/references.md` |
| UI 方案 | `src/components/ui/` + `tailwind.config.ts` |
| 项目 Skill | `AGENTS.md` + `.pi/settings.json` + `.muse/skills/` |
| 架构图 | `docs/CHARTER.md` §4 (文字描述, 无图) |
| APK 预览脚手架 | `src/app/preview/` + `src/app/app-preview/` + `src/components/preview/` |
| 部署脚本 | `tools/` + `deploy/` |

**没有"WEB 开发域的模块清单"**, 新人/agent 不知道这些模块的存在 + 职责 + 怎么扩展.

---

## 决策

### 主人 2026-09-13 ask_user 四项拍板:

| 边界 | 拍板 | 含义 |
|---|---|---|
| 1. WEB 域模块清单 | **all_7** (全部 7 个模块) | 任务快照 / 借鉴关注 / UI 方案 / 项目 Skill / 架构图 / APK 预览脚手架 / 部署脚本 — 都纳入 WEB 开发域 |
| 2. APK 域模块清单 | **merge_graph_list** | 8 个模块 (auth / customer / wellness / follow_up / presentation(graph+list) / meeting / relation) |
| 3. 客户/加盟关系抽象粒度 | **abstract_now** | 现在就写 `RelationSystem` abstract class + `FranchiseRelationSystem` 默认实现, 改调用点走接口 |
| 4. 实施节奏 | **incremental** | 渐进迁移: 一次只挪一个模块 + 编译跑过 + 单模块 commit |

### 总体架构图

```
┌─────────────────────── APK 域 (主产品) ────────────────────────┐
│                                                                │
│  ┌─ APK 底座 (core/: 不可替换的基建) ────────────────────┐     │
│  │  router / providers / http / theme / models / widgets   │     │
│  └────────────────────────────────────────────────────┘     │
│                              ↑ 复用                            │
│  ┌─ 业务模块 (modules/: 可独立替换/改进) ────────────────┐    │
│  │  • auth      登录                                    │    │
│  │  • customer  客户档案                                │    │
│  │  • wellness  养生记录                                │    │
│  │  • follow_up 跟进任务                                │    │
│  │  • presentation  图谱(graph) + 列表(list) 合并       │    │
│  │  • meeting   会议组织 (占位)                          │    │
│  │  • relation ★ 客户/加盟关系 (接口 + 默认实现)         │    │
│  └────────────────────────────────────────────────────┘     │
│                                                                │
└────────────────────────────────────────────────────────────┘

┌─────────────────────── WEB 域 (脚手架) ────────────────────────┐
│                                                                │
│  ┌─ WEB 底座 (Next.js 15 + shadcn + Tailwind + Route) ───┐    │
│  │  Next.js App Router + shadcn/ui + Tailwind             │    │
│  └─────────────────────────────────────────────────────┘    │
│                              ↑ 服务                            │
│  ┌─ 开发域模块 (dev-modules/: 文档化视图) ──────────────┐    │
│  │  • task-snapshot  任务快照                            │    │
│  │  • references     同类项目借鉴关注                    │    │
│  │  • ui-kit         UI 方案                             │    │
│  │  • project-skill  项目 Skill                          │    │
│  │  • architecture   架构图                              │    │
│  │  • flutter-preview  APK 预览脚手架                    │    │
│  │  • deploy         部署脚本                            │    │
│  └────────────────────────────────────────────────────┘    │
│                                                                │
└────────────────────────────────────────────────────────────┘
                              ↓↑
        ┌──────────────────────────────────────────┐
        │  共享基础设施 (后端 API + DB)              │
        │  src/lib/ + src/app/api/ + Drizzle schema │
        │  + 字段加密 + 审计 + 认证                 │
        └──────────────────────────────────────────┘
```

---

## 候选评估

### APK 域目录方案

| 候选 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| A. 维持 screens/ 平铺, 不动 | 零改动 | 模块边界依然缺失, 主人不满 | ❌ 排除 |
| B. 物理迁移到 `flutter_app/lib/modules/<name>/` | 真正的物理模块, Flutter 包结构惯例 | 大规模 git mv, import 路径全改 | ⭐⭐⭐⭐ **采纳** |
| C. 软链接视图 (类似 WEB 域方案) | 改动小 | Flutter 包结构不鼓励软链接, IDE 跳转不便 | ❌ 排除 |
| D. 命名空间分层 `flutter_app/lib/<feature>/<screens,widgets>/` | 改动小 | 没有 "modules" 概念, 后续提取/替换不便 | ⚠️ 备选 |

**采纳 B**: Flutter 官方包结构鼓励按 feature/modules 组织, IDE 重构工具支持批量改 import, 风险可控.

### WEB 域目录方案

| 候选 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| A. 物理迁移到 `src/dev-modules/<name>/` | 真正的物理模块 | 破坏现有约定 (scripts/ + docs/ + tools/), 大量 mv | ⚠️ 风险高 |
| B. 文档化视图 `docs/dev-modules/*.md` | 不破坏现有约定, 渐进友好 | 视图是软约束, 需主人 review | ⭐⭐⭐⭐ **采纳** |
| C. 不文档化, 维持现状 | 零改动 | 没有模块清单, 主人原话已指出问题 | ❌ 排除 |

**采纳 B**: 现有约定 (scripts/ + docs/ + tools/ + deploy/) 已经稳定 (deploy/ README, tools/check-port.sh, .pi/settings.json 都已就位), 物理迁移风险大于收益. 文档化视图能清晰表达"WEB 域有哪些开发模块", 又不破坏现有约定.

### RelationSystem 抽象粒度

| 候选 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| A. abstract_now (现在抽接口) | 一次写好, 未来换零成本 | 现在花的功夫多 | ⭐⭐⭐⭐ **采纳** |
| B. YAGNI (先不抽, 等真要换时再抽) | 现在花的功夫少 | 未来换时改一大堆 | ❌ 主人已否定 |
| C. interface_only (只抽接口, inline 默认实现) | 中间方案 | 半成品, 仍然要后续补 | ⚠️ 折中但不如 A |

**采纳 A**: 主人原话强调"以后换方便", 明确指向**接口 + 默认实现**的 Hexagonal Architecture 风格.

### 实施节奏

| 候选 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| A. incremental (渐进迁移) | 一步一回滚, 编译跑过再移下一个, 风险低 | 时间长 (1-2 周) | ⭐⭐⭐⭐⭐ **采纳** |
| B. big_bang (一次性大重构) | 节奏紧凑 | 风险高, 一次堆 10 文件 | ❌ 违反原则 7 |
| C. doc_first_code_later (先文档后代码) | 文档先到位 | 仍是 incremental 的子集, 不如直接 incremental | ⚠️ 折中 |

**采纳 A**: 主人直接拍 incremental. 流程 = "文档先就位 (Phase 0) → 模块逐个迁移 (Phase 1-9)".

---

## 详细方案

### 1. APK 域目录最终结构

```
flutter_app/lib/
├── app.dart / main.dart                ← 入口
├── core/                                ← ★ APK 底座 (不可替换)
│   ├── router/                          ← go_router 配置 + 全局 redirect
│   ├── providers/                       ← 共享 Riverpod providers
│   │   ├── auth_provider.dart           ← 当前登录用户状态
│   │   └── service_providers.dart       ← 共享 service provider (api_client 等)
│   ├── http/                            ← dio + 拦截器 + 错误处理
│   │   └── api_client.dart              ← 含自动 cookie / 重试 / 错误映射
│   ├── theme/                           ← Material 3 养生绿主题
│   ├── models/                          ← 共享 freezed models (跨模块)
│   │   ├── customer.dart                ← 客户基础模型
│   │   ├── wellness_record.dart         ← 养生记录
│   │   ├── follow_up.dart               ← 跟进任务
│   │   └── dictionary.dart              ← 字典 (部位/状态/用料/效果)
│   └── widgets/                         ← 共享 widgets
│       ├── stat_card.dart
│       └── photo_picker.dart
│
└── modules/                             ← ★ 业务模块 (可独立替换/改进)
    ├── auth/
    │   ├── screens/
    │   │   └── login_screen.dart
    │   ├── providers/
    │   │   └── login_form_provider.dart
    │   └── README.md                    ← 模块说明 (入口/依赖/扩展指南)
    │
    ├── customer/
    │   ├── screens/
    │   │   ├── customers_page.dart
    │   │   ├── customer_detail_page.dart
    │   │   └── customer_form_page.dart
    │   ├── providers/
    │   └── README.md
    │
    ├── wellness/
    │   ├── screens/
    │   │   ├── wellness_records_page.dart
    │   │   ├── wellness_record_detail_page.dart
    │   │   └── wellness_record_form_page.dart
    │   ├── providers/
    │   ├── widgets/
    │   │   └── structured_form.dart     ← 模块私有 widget
    │   └── README.md
    │
    ├── follow_up/
    │   ├── screens/
    │   │   └── follow_ups_page.dart
    │   ├── providers/
    │   ├── widgets/
    │   │   └── swipeable_card.dart      ← 从原 components/business/follow-up-swipeable-card.tsx 移植
    │   └── README.md
    │
    ├── presentation/                    ← ★ graph + list 合并
    │   ├── graph/
    │   │   ├── screens/
    │   │   │   ├── franchise_tree_page.dart
    │   │   │   ├── franchisee_detail_page.dart
    │   │   │   └── add_franchisee_page.dart
    │   │   └── providers/
    │   ├── list/                        ← 跨模块复用的列表组件
    │   │   ├── widgets/
    │   │   │   ├── infinite_scroll_list.dart
    │   │   │   ├── search_bar.dart
    │   │   │   └── filter_chip.dart
    │   │   └── providers/
    │   └── README.md                    ← 说明 graph/list 合并的理由
    │
    ├── relation/                        ← ★ 客户/加盟关系 (重点)
    │   ├── lib/
    │   │   ├── relation_system.dart     ← abstract class RelationSystem
    │   │   ├── relation_node.dart       ← RelationNode / RelationType / RelationPath
    │   │   └── franchise_relation.dart  ← FranchiseRelationSystem 默认实现
    │   ├── screens/                     ← 调用方, 通过 RelationSystem 接口
    │   │   ├── franchise_tree_view.dart ← 内部调用 relationSystem.getGraph()
    │   │   ├── franchisee_detail_view.dart
    │   │   └── add_franchisee_view.dart
    │   ├── providers/
    │   │   └── relation_system_provider.dart  ← 默认注入 FranchiseRelationSystem
    │   └── README.md                    ← 重点说明: 切换关系系统时改这里
    │
    └── meeting/                         ← 会议组织 (占位)
        ├── README.md                    ← "TBD - 待启动时规划"
        └── .gitkeep
```

**模块内部推荐结构** (不强求):

```
modules/<module>/
├── screens/                  ← 页面
├── providers/                ← Riverpod providers
├── widgets/                  ← 模块私有 widgets (可选)
├── services/                 ← 模块私有 services (可选)
└── README.md                 ← 模块说明 (入口 / 依赖 / 扩展指南)
```

### 2. RelationSystem 接口设计 (★ 重点)

**核心抽象** (`flutter_app/lib/modules/relation/lib/relation_system.dart`):

```dart
/// 节点关系系统的抽象接口
///
/// 客户/加盟关系只是其中一种实现 (FranchiseRelationSystem).
/// 未来想换「分销」「会员等级」「上下级」等其他关系系统时, 只需实现本接口.
abstract class RelationSystem {
  /// 系统名 (e.g. "franchise", "distribution")
  String get name;

  /// 获取节点的完整关系图 (含所有关联节点)
  Future<List<RelationNode>> getGraph(String rootId);

  /// 添加关系
  Future<void> addRelation({
    required String fromId,
    required String toId,
    required RelationType type,
  });

  /// 删除关系
  Future<void> removeRelation({
    required String fromId,
    required String toId,
  });

  /// 查找两个节点间的路径
  Future<List<RelationPath>> findPaths({
    required String fromId,
    required String toId,
  });

  /// 获取节点详情
  Future<RelationNode?> getNode(String nodeId);

  /// 获取直接关联的子节点
  Future<List<RelationNode>> getChildren(String parentId);
}
```

**数据类** (`flutter_app/lib/modules/relation/lib/relation_node.dart`):

```dart
enum RelationType {
  parent,    // 上级 (加盟主)
  child,     // 下级 (加盟商)
  peer,      // 同级
  manager,   // 管理 (店长-店员)
  referral,  // 引荐 (分销)
}

class RelationNode {
  final String id;
  final String name;
  final String? avatarUrl;
  final Map<String, dynamic> metadata;
  // e.g. {"joinedAt": "2026-01-01", "storeId": "store-123", "level": 1}

  const RelationNode({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.metadata = const {},
  });
}

class RelationPath {
  final List<RelationNode> nodes;
  final List<RelationType> edges;
  // e.g. A(parent) -> B(child) -> C(child)

  const RelationPath({required this.nodes, required this.edges});
}
```

**默认实现** (`flutter_app/lib/modules/relation/lib/franchise_relation.dart`):

```dart
class FranchiseRelationSystem implements RelationSystem {
  final FranchiseRelationApi _api;  // dio 注入

  FranchiseRelationSystem(this._api);

  @override
  String get name => 'franchise';

  @override
  Future<List<RelationNode>> getGraph(String rootId) async {
    final res = await _api.getFranchiseGraph(rootId);
    return res.nodes.map(_toRelationNode).toList();
  }

  @override
  Future<void> addRelation({
    required String fromId,
    required String toId,
    required RelationType type,
  }) async {
    await _api.addFranchiseRelation(
      fromId: fromId,
      toId: toId,
      type: _toBackendType(type),
    );
  }

  // ... 其他方法类似
}
```

**调用方改造** (`flutter_app/lib/modules/relation/screens/franchise_tree_view.dart`):

```dart
// ❌ 旧: 直接耦合 API
final api = ref.read(franchiseApiProvider);
final graph = await api.getFranchiseGraph(rootId);

// ✅ 新: 走接口
final relationSystem = ref.read(relationSystemProvider);
final graph = await relationSystem.getGraph(rootId);
```

**未来替换**: 主人想换「分销关系」时, 新建 `DistributionRelationSystem implements RelationSystem`, 改 `relationSystemProvider` 默认值, **调用方零改动**.

### 3. WEB 域文档化视图

```
docs/dev-modules/
├── README.md              ← 总入口 + 按功能分类的模块清单
├── task-snapshot.md       ← 指向 scripts/task-snapshot.sh + .pi/extensions/auto-task-snapshot.ts
├── references.md          ← 指向 docs/references.md + 外部项目监控 SOP
├── ui-kit.md              ← 指向 src/components/ui/ + tailwind.config.ts + theme
├── project-skill.md       ← 指向 AGENTS.md + .pi/settings.json + .muse/skills/
├── architecture.md        ← 指向 CHARTER §4 + 架构图生成脚本
├── flutter-preview.md     ← 指向 src/app/{app-preview,preview}/ + src/components/preview/
└── deploy.md              ← 指向 tools/ + deploy/ + systemd
```

**每个模块 README 模板**:

```markdown
# <模块名>

**职责**: <一句话>
**物理位置**: <文件路径>
**入口**: <主要脚本/类/页面>

## 当前实现
- <关键文件 1>: <作用>
- <关键文件 2>: <作用>

## 扩展指南
<如何添加新功能 / 替换实现>

## 相关 SOP
<链接到 docs/ 下其他 SOP>
```

### 4. 实施路线图 (incremental)

| Phase | 内容 | 时间 | 验证 |
|---|---|---|---|
| Phase 0 | 架构基线文档 (本 ADR + CHARTER §4 + AGENTS §4 + CHANGELOG [0.5.0]) | 0.5 天 | 主人 review |
| Phase 1 | modules/auth/ 迁移 (最简单, 无依赖) | 0.5 天 | flutter build apk 跑过 + 登录功能正常 |
| Phase 2 | modules/customer/ 迁移 | 1 天 | flutter build apk + 真机验证 (列表 + 详情 + 表单) |
| Phase 3 | modules/wellness/ 迁移 | 1 天 | flutter build apk + 真机验证 (结构化表单 + 拍照) |
| Phase 4 | modules/follow_up/ 迁移 | 0.5 天 | flutter build apk + 真机验证 |
| Phase 5 | modules/presentation/ (graph + list 合并) | 1 天 | flutter build apk + 真机验证 (图谱 + 列表) |
| **Phase 6** | **modules/relation/ ★ (抽接口 + 默认实现)** | **1.5 天** | **flutter build apk + 真机 + 单测 (RelationSystem 抽象)** |
| Phase 7 | modules/meeting/ (占位目录 + README) | 0.1 天 | 仅 README |
| Phase 8 | docs/dev-modules/ WEB 域文档化视图 | 1 天 | 主人 review |
| Phase 9 | CHARTER §4 / AGENTS §4 实地更新 | 0.5 天 | 主人 review + git history |

**原则**:
- 一次只挪一个模块 (Phase 1-7)
- 每步 git commit (单模块粒度, 标题: `refactor(apk): migrate <module> to modules/<name>/`)
- 保留回滚能力 (`git mv` 历史 + 单步可回滚)
- 不影响现有 APK 运行 (逐步迁移, 编译跑过再移下一个)
- Phase 6 (RelationSystem 抽象) 是重点, 必须加单测验证接口契约

### 5. 风险与缓解

| 风险 | 缓解 |
|---|---|
| **大规模目录重构引入 bug** | 一次只挪一个模块 + 编译跑过再移下一个 + 单模块 commit |
| **RelationSystem 抽象可能过度** | 抽象前先明确接口边界 (本 ADR 已列 7 个方法), 不做"可能用到"的功能 |
| **现有 Flutter imports 大量需改** | 用 IDE 重构工具批量改 import + 编译验证 (预计 Phase 1 摸清工作量) |
| **WEB 域文档化视图可能滞后** | 文档化视图是"软约束", 主人 review 时检查 + Phase 9 同步落地 |
| **git 历史可读性变差** | `git log --follow` 仍然能追到旧路径, 每个模块用 `refactor(apk): migrate xxx` 标题 |
| **关系系统抽象后没真实替换场景** | 接受 YAGNI 反例 — 主人明确拍 abstract_now, 即使暂时只有一个实现也抽接口 |

---

## 后续行动

### 立即 (本 ADR 通过后)

- [ ] 本 ADR 入库 (`docs/adr/0007-modular-architecture.md`)
- [ ] 升 `docs/CHARTER.md` 到 v0.1.3 (§4 域边界重新设计)
- [ ] 改 `AGENTS.md` §4 文件组织 (新增 modules/ + dev-modules/ 章节)
- [ ] `CHANGELOG.md` [0.5.0] 条目 (架构重构基线)

### Phase 1-7 (渐进迁移, 1-2 周)

- [ ] Phase 1: modules/auth/
- [ ] Phase 2: modules/customer/
- [ ] Phase 3: modules/wellness/
- [ ] Phase 4: modules/follow_up/
- [ ] Phase 5: modules/presentation/ (graph + list 合并)
- [ ] Phase 6: modules/relation/ ★ 抽接口 + 默认实现
- [ ] Phase 7: modules/meeting/ 占位

### Phase 8-9 (文档化视图 + 落地)

- [ ] Phase 8: docs/dev-modules/ WEB 域文档化视图
- [ ] Phase 9: CHARTER §4 / AGENTS §4 实地更新 + 验证

### 验证标准

每 Phase 完成的 DoD (Definition of Done):

- [ ] `git mv` 历史可追 (`git log --follow <file>` 能查到旧路径)
- [ ] `flutter build apk` 成功
- [ ] 真机验证核心功能 (主人 + 1-2 个测试场景)
- [ ] 单测通过 (Vitest / Dart test, Phase 6 必须有 RelationSystem 单测)
- [ ] commit message 标注 phase 编号 (`refactor(apk): migrate auth to modules/auth/ (Phase 1)`)

---

## 参考

- [`docs/CHARTER.md`](../CHARTER.md) §4 域划分 (本 ADR 元宪法落地, 待 v0.1.3)
- [`docs/adr/0005-mobile-only-phase.md`](0005-mobile-only-phase.md) (web 冻结 + flutter-only-sync, 本 ADR 同步执行)
- [`docs/adr/0003-flutter-dev-workflow.md`](0003-flutter-dev-workflow.md) (Flutter 开发流, 本 ADR 演进)
- AGENTS.md §3 协作规则 (小步快跑原则 7)
- AGENTS.md §4 文件组织 (待更新)
- Flutter 官方包结构惯例: 按 feature / module 组织 `lib/<feature>/...`
- Hexagonal Architecture (Ports and Adapters) — RelationSystem 抽象的灵感来源

## 变更记录

- 2026-09-13: 创建 (W2-3 架构重构决策, 主人 4 项 ask_user 拍板)
