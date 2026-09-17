// ============================================
// 暖客宝 客户页 (Plan F2 极简版)
// 单文件 3 widget: 列表 + 详情 + 表单
// 中老年易用: 字号 18pt+ / 按钮 64pt+ / FAB 80pt / 行高 80pt
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/customer.dart';
// fix-graph-zoom-pan (2026-09-16): auto-fit initial scale, user can see whole tree on open
import 'dart:math' as math;
import '../../../core/models/franchisee.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/big_button.dart';
import '../widgets/big_fab.dart';
import '../widgets/customer_row.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/franchise_chip.dart';
import '../../presentation/graph/widgets/franchise_tree_painter.dart';
import 'add_record_sheet.dart';

/// 客户页视图模式: 列表 / 图谱
enum _CustomerViewMode { list, graph }

// ============================================
// CustomersListPage (主页: 客户列表 / 图谱)
// ============================================

enum _CustomerFilter { all, franchisee, normal, seed }

class CustomersListPage extends ConsumerStatefulWidget {
  const CustomersListPage({super.key});

  @override
  ConsumerState<CustomersListPage> createState() => _CustomersListPageState();
}

class _CustomersListPageState extends ConsumerState<CustomersListPage> {
  final _searchController = TextEditingController();
  String _search = '';
  _CustomerFilter _filter = _CustomerFilter.all;

  /// 视图模式: 默认列表; 但可以从 URL ?view=graph 进入 (路由 /franchise-tree 重定向过来)
  _CustomerViewMode _viewMode = _CustomerViewMode.list;

  /// 是否已从 URL 读取初始 view 参数 (避免 build 期间 setState + 重复读)
  bool _viewModeInitialized = false;

  /// fix-graph-zoom-pan (2026-09-16): InteractiveViewer 的 TransformationController
  ///   - 初始值设为 fit-to-viewport (auto-fit), user 进图谱页面就能看全树
  ///   - user 可双指缩放 / 单指拖动改 controller.value, 后续不需要重置 (persist across zoom/pan)
  final TransformationController _graphTransformController = TransformationController();

  /// 图谱视图状态 (LayoutBuilder 每次 layout 更新, 供「回到我」/「全景」按钮复用)
  /// fix-graph-ui-v3 (2026-09-17): 替换 v2 的 outer Transform 方案 —
  ///   旧方案把 InteractiveViewer 的 viewport 整体缩放, 画布反被 constraints 压成
  ///   viewport 大小, 图谱缩在左上角一小块 (主人截图就是这个)
  Size? _graphViewport;
  Size? _graphCanvasSize;
  Offset? _graphRootCenter;
  bool _graphViewInitialized = false;

  /// 单击选中的节点 id (选中后突显它 + 高亮 它→「我」整条线 + 其余淡化)
  /// fix-graph-spine (2026-09-17 主人拍): 单击 = 看线, 长按 = 跳详情
  String? _selectedNodeId;
  Set<String> _graphPathIds = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // URL ?view=graph → 默认进入图谱 tab (供 /franchise-tree redirect 使用)
    if (!_viewModeInitialized) {
      final viewParam = GoRouterState.of(context).uri.queryParameters['view'];
      if (viewParam == 'graph') {
        _viewMode = _CustomerViewMode.graph;
      }
      _viewModeInitialized = true;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _graphTransformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncCustomers = ref.watch(customersProvider(_search.isEmpty ? null : _search));
    // 图谱 tab 数据源: 加盟客户的 2 线图谱 (复用 franchisee/me/tree)
    // 普通 / 种子客户不参与图谱, 由 type 字段 + 后端过滤保证 (待补)
    final asyncTree = ref.watch(myFranchiseeTreeProvider(3));

    return Scaffold(
      appBar: AppBar(
        title: const Text('客户'),
        toolbarHeight: 64,
        actions: [
          // 列表/图谱 切换 (Material 3 SegmentedButton)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SegmentedButton<_CustomerViewMode>(
              // fix-graph-ui-v3 (2026-09-17): 去 icon + 去掉 compact/shrinkWrap
              //   旧版 (icon 20 + label 14 + compact) 每个 segment 只有 63pt 宽,
              //   "列表"/"图谱" 被挤到竖排 2 行 (字号小=图标宽度), 主人截图里就是歪的
              //   现在纯文字 15pt + 默认密度: segment ≈54pt, 文字单行, 点击区 40pt
              segments: const [
                ButtonSegment(
                  value: _CustomerViewMode.list,
                  label: Text('列表', style: TextStyle(fontSize: 15)),
                ),
                ButtonSegment(
                  value: _CustomerViewMode.graph,
                  label: Text('图谱', style: TextStyle(fontSize: 15)),
                ),
              ],
              selected: {_viewMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _viewMode = s.first),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框 (始终可见; 列表视图下走 list 过滤, 图谱视图下高亮匹配节点)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: InputDecoration(
                hintText: _viewMode == _CustomerViewMode.graph
                    ? '搜索客户姓名 (高亮匹配节点)'
                    : '搜索 姓名 或 手机号',
                prefixIcon: const Icon(Icons.search, size: 28),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 22),
                        tooltip: '清除',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        },
                      ),
              ),
              onChanged: (v) {
                setState(() => _search = v);
                // 图谱默认只显示局部, 搜索命中节点往往在屏外 → 自动挪到屏幕中心
                if (_viewMode == _CustomerViewMode.graph) _focusOnSearchMatch(v);
              },
            ),
          ),
          // 过滤 chip (列表视图下; 图谱视图不需要 — 搜索已可定位)
          if (_viewMode == _CustomerViewMode.list)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildChip(_CustomerFilter.all, '全部'),
                  const SizedBox(width: 8),
                  _buildChip(_CustomerFilter.franchisee, '🟣 加盟'),
                  const SizedBox(width: 8),
                  _buildChip(_CustomerFilter.normal, '🟢 普通'),
                  const SizedBox(width: 8),
                  _buildChip(_CustomerFilter.seed, '🌱 种子'),
                ],
              ),
            ),

          // 主体: 列表 / 图谱
          Expanded(
            child: _viewMode == _CustomerViewMode.list
                ? _buildListView(asyncCustomers)
                : _buildGraphView(asyncTree),
          ),
        ],
      ),
      // fix-graph-ui (2026-09-17): graph 视图下隐藏 FAB (FAB 会遮右子节点;
      //   graph 主要用来查看关系, 添加客户走列表视图 FAB 更顺手)
      floatingActionButton: _viewMode == _CustomerViewMode.list
          ? BigFab(
              onPressed: () => context.push('/customers/new'),
              tooltip: '添加客户',
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildListView(AsyncValue<List<dynamic>> asyncCustomers) {
    return asyncCustomers.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(customersProvider)),
      data: (rawCustomers) {
        final customers = rawCustomers.cast<Customer>();
        final filtered = _applyFilter(customers);
        if (filtered.isEmpty) {
          return EmptyState(
            icon: Icons.people_outline,
            title: _search.isNotEmpty ? '没找到客户' : '还没有客户',
            hint: _search.isNotEmpty ? '换个名字试试' : '点击右下角 + 添加第一位客户',
            onAction: () => context.push('/customers/new'),
            actionLabel: '+ 添加客户',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(customersProvider),
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final c = filtered[i];
              return CustomerRow(
                customer: c,
                isFranchisee: false,
                pendingCount: 0,
                onTap: () => context.push('/customers/${c.id}'),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildGraphView(AsyncValue<dynamic> asyncTree) {
    return asyncTree.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(myFranchiseeTreeProvider),
      ),
      data: (raw) {
        // myFranchiseeTreeProvider 返回 dynamic (兼容关系接口迁移期), 这里 cast
        final tree = raw as FranchiseeTreeNode?;

        // ★ 业务空状态 (非错误, 不走 ErrorState):
        //   - tree == null: 后端 404 真错误 (franchiseeId 存在但记录被删)
        //   - id == "0" / name == "未加盟": user 没加盟关系 (dev mode / 普通用户)
        //   - _countDescendants(tree) <= 1: 只有自己没下线 (加盟了但没发展)
        if (tree == null ||
            tree.id == '0' ||
            tree.name == '未加盟' ||
            _countDescendants(tree) <= 1) {
          final isUnaffiliated =
              tree == null || tree.id == '0' || tree.name == '未加盟';
          return EmptyState(
            icon: Icons.account_tree_outlined,
            title: isUnaffiliated
                ? '还不是加盟商, 没有加盟网络'
                : '还没有加盟客户, 无法生成图谱',
            hint: isUnaffiliated
                ? '当前账号未关联加盟关系, 无法查看加盟图谱'
                : '普通 / 种子客户不参与图谱, 加入加盟后才显示',
            onAction: () => context.push('/customers/new'),
            actionLabel: '+ 添加客户',
          );
        }
        // 预算搜索匹配数 (全树 O(n) 走一遍)
        final searchQuery = _search.trim();
        final matchCount = searchQuery.isEmpty
            ? 0
            : _countMatches(tree, searchQuery.toLowerCase());

        // 双主线「对碰」布局: 两条主线平行直下, 侧枝往外侧展开
        const depth = 3;
        final layout = TreeLayout.compute(tree, maxDepth: depth);
        final canvasSize = layout.canvasSize;
        final positions = layout.positions;
        final searchMatchedIds = searchQuery.isEmpty
            ? null
            : _collectMatches(tree, searchQuery.toLowerCase());

        return Column(
          children: [
            // 顶部提示条: 默认指引 + 搜索结果数
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: searchQuery.isNotEmpty
                  ? (matchCount > 0
                      ? AppTheme.primaryLight.withOpacity(0.5)
                      : AppTheme.danger.withOpacity(0.08))
                  : AppTheme.primaryLight.withOpacity(0.3),
              child: Row(
                children: [
                  Icon(
                    searchQuery.isNotEmpty ? Icons.search : Icons.touch_app_outlined,
                    size: 20,
                    color: searchQuery.isNotEmpty && matchCount == 0
                        ? AppTheme.danger
                        : AppTheme.primaryDark,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      searchQuery.isEmpty
                          ? '单击看线 · 长按进详情'
                          : (matchCount > 0
                              ? '匹配 $matchCount 位加盟客户 · 其余淡化'
                              : '没有匹配「$searchQuery」'),
                      style: TextStyle(
                        fontSize: AppTheme.fontSm,
                        color: searchQuery.isNotEmpty && matchCount == 0
                            ? AppTheme.danger
                            : AppTheme.primaryDark,
                      ),
                    ),
                  ),
                  Text(
                    // 减 1: 根节点是「我」, 不算加盟客户
                    '${_countDescendants(tree) - 1} 位加盟客户',
                    style: const TextStyle(
                      fontSize: AppTheme.fontSm,
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // 图谱本体 (复用 modules/presentation/graph 的 painter)
            // fix-graph-ui-v3 (2026-09-17, 主人反馈「ui一堆错误」): 重写初始视图方案
            //   v2 两个致命 bug:
            //     1) InteractiveViewer 默认 constrained:true → SizedBox(1760x696) 被父级 tight
            //        constraints 压成 viewport 大小, 画布只剩左上角一小块, 根节点直接看不见
            //     2) 外层 Transform 缩放的是 InteractiveViewer 的 viewport (已被裁到 393x571),
            //        不是画布 → 图谱变成左上角一团 (节点约 19px, 名字根本看不清)
            //   本版:
            //     - constrained:false → 画布保持原始尺寸, InteractiveViewer 当取景框
            //     - 初始视图 = 「回到我」: 根节点 (我) 顶部居中 + 1:1 (中老年看得清名字)
            //     - 右下角「回到我」/「全景」两个按钮, user 随时找回
            //     - boundaryMargin = infinity: 让 minScale 生效 (finite margin 会算出一个
            //       约 0.56 的下限, 全景 0.2x 会被 gesture 强行弹回)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                  final rootCenter = positions[tree.id] ??
                      Offset(canvasSize.width / 2,
                          TreeLayout.padding + TreeLayout.nodeRadius);
                  _graphViewport = viewport;
                  _graphRootCenter = rootCenter;

                  // 树结构变了 (画布尺寸变) → 重算初始视图
                  final treeChanged =
                      _graphCanvasSize != null && _graphCanvasSize != canvasSize;
                  _graphCanvasSize = canvasSize;
                  if (!_graphViewInitialized || treeChanged) {
                    _graphViewInitialized = true;
                    _selectedNodeId = null; // 树变了 → 清选中 (路径可能已失效)
                    _graphPathIds = const {};
                    final matrix =
                        _focusRootMatrix(viewport, canvasSize, rootCenter);
                    if (treeChanged) {
                      // InteractiveViewer 已挂载, build 期间不能动 controller → 下一帧设
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        _graphTransformController.value = matrix;
                      });
                    } else {
                      // 首次 layout: InteractiveViewer 还没建 (无 listener), 同步设
                      _graphTransformController.value = matrix;
                    }
                  }

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Container(
                          color: AppTheme.bgWarm,
                          child: InteractiveViewer(
                            // ★ 关键: 不让父级 tight constraints 把画布压成 viewport 大小
                            constrained: false,
                            transformationController: _graphTransformController,
                            panEnabled: true,
                            scaleEnabled: true,
                            minScale: _fitScale(viewport, canvasSize) * 0.9,
                            maxScale: 3.0,
                            boundaryMargin: const EdgeInsets.all(double.infinity),
                            child: SizedBox(
                              width: canvasSize.width,
                              height: canvasSize.height,
                              child: Stack(
                                children: [
                                  // 点空白处 = 取消选中 (点节点时 hit area 在上层, 先拿到事件)
                                  GestureDetector(
                                    onTap: _clearSelection,
                                    behavior: HitTestBehavior.opaque,
                                    child: CustomPaint(
                                      size: canvasSize,
                                      painter: FranchiseTreePainter(
                                        root: tree,
                                        positions: positions,
                                        searchMatchedIds: searchMatchedIds,
                                        currentUserId: tree.id,
                                        selectedNodeId: _selectedNodeId,
                                        pathIds: _graphPathIds,
                                        spineIds: layout.spineIds,
                                      ),
                                    ),
                                  ),
                                  ..._buildHitareas(tree, tree, positions),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 右下角: 「回到我」(根节点居中 1:1) / 「全景」(整树 fit)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Row(
                          children: [
                            _graphControlButton(
                              icon: Icons.my_location,
                              label: '回到我',
                              onTap: _focusGraphView,
                            ),
                            const SizedBox(width: 8),
                            _graphControlButton(
                              icon: Icons.zoom_out_map,
                              label: '全景',
                              onTap: _fitGraphView,
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  /// 递归统计全树节点数 (含根)
  int _countDescendants(FranchiseeTreeNode node) {
    var c = 1;
    for (final child in node.children) {
      c += _countDescendants(child);
    }
    return c;
  }

  /// 名字 contains(query) 的节点数
  int _countMatches(FranchiseeTreeNode node, String lowerQuery) {
    var c = node.name.toLowerCase().contains(lowerQuery) ? 1 : 0;
    for (final child in node.children) {
      c += _countMatches(child, lowerQuery);
    }
    return c;
  }

  /// 名字 contains(query) 的节点 id 集合
  Set<String> _collectMatches(FranchiseeTreeNode node, String lowerQuery) {
    final result = <String>{};
    if (node.name.toLowerCase().contains(lowerQuery)) result.add(node.id);
    for (final child in node.children) {
      result.addAll(_collectMatches(child, lowerQuery));
    }
    return result;
  }

  /// 「回到我」视图: 根节点 (我) 顶部居中 + 1:1 缩放 (中老年看得清名字)
  Matrix4 _focusRootMatrix(Size viewport, Size canvasSize, Offset rootCenter) {
    const scale = 1.0;
    final dx = viewport.width / 2 - rootCenter.dx * scale;
    // 根节点圆顶部留 24px (够悬浮, 又不浪费屏幕)
    final dy = 24 - (rootCenter.dy - TreeLayout.nodeRadius) * scale;
    return Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  /// 「全景」视图: 整棵树 fit 进 viewport (居中)
  Matrix4 _fitTreeMatrix(Size viewport, Size canvasSize) {
    final scale = _fitScale(viewport, canvasSize);
    final dx = (viewport.width - canvasSize.width * scale) / 2;
    final dy = (viewport.height - canvasSize.height * scale) / 2;
    return Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  /// 整棵树 fit 进 viewport 的缩放比 (含 4% 边距, 下限 0.05 防除零)
  double _fitScale(Size viewport, Size canvasSize) {
    final sx = viewport.width / canvasSize.width;
    final sy = viewport.height / canvasSize.height;
    return math.max(0.05, math.min(sx, sy) * 0.96);
  }

  /// 深度优先找第一个名字命中 query 的节点
  FranchiseeTreeNode? _firstMatchNode(FranchiseeTreeNode node, String lowerQuery) {
    if (node.name.toLowerCase().contains(lowerQuery)) return node;
    for (final child in node.children) {
      final hit = _firstMatchNode(child, lowerQuery);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 搜索时把第一个命中节点挪到屏幕中心 (1:1) — 否则高亮节点在屏外, user 看不到
  void _focusOnSearchMatch(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) return;
    final viewport = _graphViewport;
    final canvasSize = _graphCanvasSize;
    if (viewport == null || canvasSize == null) return;
    final tree = ref.read(myFranchiseeTreeProvider(3)).valueOrNull as FranchiseeTreeNode?;
    if (tree == null) return;
    final hit = _firstMatchNode(tree, lower);
    if (hit == null) return;
    final center = TreeLayout.compute(tree, maxDepth: 3).positions[hit.id];
    if (center == null) return;
    setState(() {
      _graphTransformController.value = Matrix4.identity()
        ..translate(viewport.width / 2 - center.dx, viewport.height / 2 - center.dy)
        ..scale(1.0);
    });
  }

  /// 回到「我」(初始可读视图)
  void _focusGraphView() {
    final viewport = _graphViewport;
    final canvasSize = _graphCanvasSize;
    final rootCenter = _graphRootCenter;
    if (viewport == null || canvasSize == null || rootCenter == null) return;
    setState(() {
      _graphTransformController.value =
          _focusRootMatrix(viewport, canvasSize, rootCenter);
    });
  }

  /// 缩到全景 (整棵树可见)
  void _fitGraphView() {
    final viewport = _graphViewport;
    final canvasSize = _graphCanvasSize;
    if (viewport == null || canvasSize == null) return;
    setState(() {
      _graphTransformController.value =
          _fitTreeMatrix(viewport, canvasSize);
    });
  }

  /// 图谱右下角控制按钮 (回到我 / 全景)
  Widget _graphControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppTheme.primary.withOpacity(0.4), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppTheme.primaryDark),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.primaryDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 节点 hit area
  /// - 单击: 突显该节点 + 高亮 它 → 「我」整条线 (再点一下取消)
  /// - 长按: 跳加盟商详情
  List<Widget> _buildHitareas(
    FranchiseeTreeNode root,
    FranchiseeTreeNode node,
    Map<String, Offset> positions,
  ) {
    final widgets = <Widget>[];
    final pos = positions[node.id];
    if (pos == null) return widgets;
    widgets.add(
      Positioned(
        left: pos.dx - TreeLayout.nodeRadius,
        top: pos.dy - TreeLayout.nodeRadius,
        width: TreeLayout.nodeSize,
        // 圆下方到名字/左线右线标签都算可点 (中老年手指粗, 别只让圆圈可点)
        height: TreeLayout.nodeSize + 44,
        child: GestureDetector(
          onTap: () => _selectNode(root, node),
          onLongPress: () => context.push('/franchisees/${node.id}'),
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
      ),
    );
    for (final child in node.children) {
      widgets.addAll(_buildHitareas(root, child, positions));
    }
    return widgets;
  }

  /// 单击节点: 选中 (再点一下取消选中)
  void _selectNode(FranchiseeTreeNode root, FranchiseeTreeNode node) {
    setState(() {
      if (_selectedNodeId == node.id) {
        _selectedNodeId = null;
        _graphPathIds = const {};
      } else {
        _selectedNodeId = node.id;
        _graphPathIds = _pathIdsTo(root, node.id) ?? {node.id};
      }
    });
  }

  /// 取消选中 (点空白画布)
  void _clearSelection() {
    if (_selectedNodeId == null) return;
    setState(() {
      _selectedNodeId = null;
      _graphPathIds = const {};
    });
  }

  /// 根 → 目标节点 的路径 id 集合 (含两端); 找不到返回 null
  Set<String>? _pathIdsTo(FranchiseeTreeNode root, String targetId) {
    final path = <String>[];
    bool dfs(FranchiseeTreeNode n) {
      path.add(n.id);
      if (n.id == targetId) return true;
      for (final c in n.children) {
        if (dfs(c)) return true;
      }
      path.removeLast();
      return false;
    }

    return dfs(root) ? path.toSet() : null;
  }

  Widget _buildChip(_CustomerFilter f, String label) {
    final selected = _filter == f;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: AppTheme.fontSm,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _filter = f),
      selectedColor: AppTheme.primary,
      backgroundColor: Colors.white,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.textPrimary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }

  List<Customer> _applyFilter(List<Customer> all) {
    // TODO: 真实过滤需后端配合 isFranchisee / pendingCount
    return all;
  }
}

// ============================================
// CustomerDetailPage (详情 + 时间线)
// ============================================

class CustomerDetailPage extends ConsumerWidget {
  final String customerId;
  const CustomerDetailPage({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCustomer = ref.watch(customerDetailProvider(customerId));
    final asyncRecords = ref.watch(customerWellnessRecordsProvider(customerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('客户详情'),
        toolbarHeight: 64,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, size: 28),
            tooltip: '编辑',
            onPressed: () => context.push('/customers/$customerId/edit'),
          ),
        ],
      ),
      body: asyncCustomer.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (customer) => _buildBody(context, ref, customer, asyncRecords),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
    AsyncValue<List<dynamic>> asyncRecords,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      children: [
        // 大头像 + 基本信息卡
        _buildHeader(customer),
        const SizedBox(height: 16),

        // 主操作按钮: + 添加记录 (大按钮 64pt)
        BigButton(
          label: '+ 添加记录',
          icon: Icons.add_circle_outline,
          onPressed: () => showAddRecordSheet(context, customerId: customerId),
        ),
        const SizedBox(height: 16),

        // 健康标签
        if (customer.healthTags.isNotEmpty) _buildHealthTags(customer),
        if (customer.healthTags.isNotEmpty) const SizedBox(height: 16),

        // 时间线: 全部记录 (养生 + 后续会加联系 + 跟进)
        _buildSectionTitle('全部记录'),
        asyncRecords.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: LoadingState(),
          ),
          error: (e, _) => Text('加载失败: $e'),
          data: (records) {
            if (records.isEmpty) {
              return _buildEmptyHint('还没有记录', '点击上方"添加记录"开始');
            }
            return Column(
              children: records.map((r) => _buildRecordTile(context, r)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeader(Customer c) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: AppTheme.avatarLg / 2,
              backgroundColor: AppTheme.primaryLight,
              child: Text(
                c.name.isNotEmpty ? c.name[0] : '?',
                style: const TextStyle(
                  fontSize: 36,
                  color: AppTheme.primaryDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              c.name,
              style: const TextStyle(
                fontSize: AppTheme.fontXl,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _maskPhone(c.phone),
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                color: AppTheme.textSecondary,
              ),
            ),
            if (c.gender != null || c.birthYear != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (c.gender != null)
                    Chip(label: Text(c.gender == 'F' ? '女' : c.gender == 'M' ? '男' : '未知')),
                  if (c.birthYear != null)
                    Chip(label: Text('${c.birthYear}年')),
                ],
              ),
            ],
            if (c.diseaseHistory != null && c.diseaseHistory!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '既往病史: ${c.diseaseHistory}',
                  style: const TextStyle(
                    fontSize: AppTheme.fontSm,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHealthTags(Customer c) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '健康标签',
              style: TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: c.healthTags.map((t) => HealthTagChip(label: t)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: AppTheme.fontMd,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildEmptyHint(String title, String hint) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.history, size: 56, color: AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: 4),
            Text(hint, style: const TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordTile(BuildContext context, dynamic r) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.favorite, color: AppTheme.accent, size: 28),
        ),
        title: Text(
          '养生记录',
          style: const TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${dateFmt.format(DateTime.parse(r.serviceDate))}${r.customerFeedback != null ? ' · ${r.customerFeedback}' : ''}',
            style: const TextStyle(fontSize: AppTheme.fontSm),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 28),
        onTap: () => context.push('/wellness-records/${r.id}'),
      ),
    );
  }

  String _maskPhone(String phone) {
    if (phone.length == 11) {
      return '${phone.substring(0, 3)}****${phone.substring(7)}';
    }
    return phone;
  }
}

// ============================================
// CustomerFormPage (新增 / 编辑)
// ============================================

class CustomerFormPage extends ConsumerStatefulWidget {
  final String? customerId;
  const CustomerFormPage({super.key, this.customerId});

  @override
  ConsumerState<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends ConsumerState<CustomerFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _notesController = TextEditingController();
  String? _gender = 'F';
  DateTime? _birthYear;
  final List<String> _healthTags = [];
  /// 客户推荐人 (客户页图谱关系边). null = 无推荐人
  String? _referrerId;
  String? _referrerName;

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.customerId != null) {
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    final c = await ref.read(customerServiceProvider).getById(widget.customerId!);
    if (!mounted) return;
    setState(() {
      _nameController.text = c.name;
      _phoneController.text = c.phone;
      _notesController.text = c.notes ?? '';
      _gender = c.gender;
      _birthYear = c.birthYear != null ? DateTime(c.birthYear!, 1, 1) : null;
      _healthTags.clear();
      _healthTags.addAll(c.healthTags);
      _referrerId = c.referrerId;
      _referrerName = null; // 按需点击选择器时懒加载名字
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final data = <String, dynamic>{
        'name': _nameController.text,
        'phone': _phoneController.text,
        if (_gender != null) 'gender': _gender,
        if (_birthYear != null) 'birthYear': _birthYear!.year,
        'healthTags': _healthTags,
        if (_notesController.text.isNotEmpty) 'notes': _notesController.text,
        // referrerId: 显式发 null 清空, undefined 不变
        'referrerId': _referrerId,
      };
      if (widget.customerId != null) {
        await ref.read(customerServiceProvider).update(widget.customerId!, data);
      } else {
        await ref.read(customerServiceProvider).create(data);
      }
      if (!mounted) return;
      ref.invalidate(customersProvider);
      ref.invalidate(myFranchiseeTreeProvider);
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customerId == null ? '添加客户' : '编辑客户'),
        toolbarHeight: 64,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(labelText: '姓名 *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: '手机号 *'),
              validator: (v) {
                if (v == null || !RegExp(r'^1[3-9]\d{9}$').hasMatch(v)) {
                  return '请输入正确的手机号';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            // 性别 (大按钮组)
            const Text('性别', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: 8),
            Row(
              children: [
                _genderButton('女', 'F'),
                const SizedBox(width: 8),
                _genderButton('男', 'M'),
                const SizedBox(width: 8),
                _genderButton('未知', 'U'),
              ],
            ),
            const SizedBox(height: 16),
            // 出生年 (大按钮)
            OutlinedButton.icon(
              onPressed: () async {
                final year = await showDialog<int>(
                  context: context,
                  builder: (_) => _YearPickerDialog(initial: _birthYear?.year),
                );
                if (year != null) setState(() => _birthYear = DateTime(year, 1, 1));
              },
              icon: const Icon(Icons.cake_outlined, size: 24),
              label: Text(
                _birthYear == null ? '选择出生年份' : '${_birthYear!.year}年',
                style: const TextStyle(fontSize: AppTheme.fontMd),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
            const SizedBox(height: 16),
            // 健康标签
            const Text('健康标签', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _healthTags.map((t) => InputChip(
                label: Text(t),
                onDeleted: () => setState(() => _healthTags.remove(t)),
              )).toList(),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final tag = await showDialog<String>(
                    context: context,
                    builder: (_) => const _TagInputDialog(),
                  );
                  if (tag != null && !_healthTags.contains(tag)) {
                    setState(() => _healthTags.add(tag));
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('添加标签', style: TextStyle(fontSize: AppTheme.fontMd)),
              ),
            ),
            const SizedBox(height: 16),
            // 推荐人 (客户页图谱关系边)
            const Text('推荐人', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: 4),
            const Text(
              '谁介绍这位客户来的? 设置后可以在客户页「图谱」看到推荐链',
              style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickReferrer,
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 24),
                    label: Text(
                      _referrerName ?? (_referrerId == null ? '选择推荐人 (可选)' : '已选 #$_referrerId'),
                      style: const TextStyle(fontSize: AppTheme.fontMd),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
                if (_referrerId != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 24),
                    tooltip: '清除推荐人',
                    onPressed: () => setState(() {
                      _referrerId = null;
                      _referrerName = null;
                    }),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            const SizedBox(height: 32),
            BigButton(
              label: widget.customerId == null ? '保存' : '保存修改',
              icon: Icons.check,
              onPressed: _submit,
              loading: _loading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _genderButton(String label, String value) {
    final selected = _gender == value;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => setState(() => _gender = value),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          backgroundColor: selected ? AppTheme.primary : Colors.white,
          foregroundColor: selected ? Colors.white : AppTheme.primary,
          side: BorderSide(
            color: selected ? AppTheme.primary : AppTheme.primary.withOpacity(0.4),
            width: 2,
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: AppTheme.fontMd)),
      ),
    );
  }

  Future<void> _pickReferrer() async {
    final result = await showDialog<_ReferrerResult>(
      context: context,
      builder: (_) => _ReferrerPickerDialog(excludeId: widget.customerId),
    );
    if (result != null && mounted) {
      setState(() {
        _referrerId = result.id;
        _referrerName = result.name;
      });
    }
  }
}

/// 推荐人选择结果
class _ReferrerResult {
  final String id;
  final String name;
  const _ReferrerResult(this.id, this.name);
}

// ============================================
// 子对话框 (年份选择 / 标签输入)
// ============================================

class _YearPickerDialog extends StatefulWidget {
  final int? initial;
  const _YearPickerDialog({this.initial});

  @override
  State<_YearPickerDialog> createState() => _YearPickerDialogState();
}

class _YearPickerDialogState extends State<_YearPickerDialog> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial ?? 1980;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择出生年份'),
      content: SizedBox(
        height: 200,
        child: ListView.builder(
          itemCount: 100,
          itemBuilder: (context, i) {
            final y = 1940 + i;
            return ListTile(
              title: Text('$y年', style: const TextStyle(fontSize: AppTheme.fontMd)),
              selected: y == _year,
              onTap: () {
                setState(() => _year = y);
                Navigator.of(context).pop(y);
              },
            );
          },
        ),
      ),
    );
  }
}

class _TagInputDialog extends StatefulWidget {
  const _TagInputDialog();

  @override
  State<_TagInputDialog> createState() => _TagInputDialogState();
}

class _TagInputDialogState extends State<_TagInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加健康标签'),
      content: TextField(
        controller: _controller,
        style: const TextStyle(fontSize: AppTheme.fontMd),
        autofocus: true,
        decoration: const InputDecoration(hintText: '如: 肩颈 / 睡眠差 / 体寒'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
        ElevatedButton(
          onPressed: () {
            final v = _controller.text.trim();
            if (v.isNotEmpty) Navigator.of(context).pop(v);
          },
          child: const Text('添加', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      ],
    );
  }
}

// ============================================
// 推荐人选择对话框 (客户页图谱关系录入)
// ============================================

class _ReferrerPickerDialog extends ConsumerStatefulWidget {
  /// 排除的 customer id (不能推荐自己)
  final String? excludeId;
  const _ReferrerPickerDialog({this.excludeId});

  @override
  ConsumerState<_ReferrerPickerDialog> createState() => _ReferrerPickerDialogState();
}

class _ReferrerPickerDialogState extends ConsumerState<_ReferrerPickerDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final asyncCustomers = ref.watch(customersProvider(_search.isEmpty ? null : _search));

    return AlertDialog(
      title: const Text('选择推荐人', style: TextStyle(fontSize: AppTheme.fontLg)),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 480,
        child: Column(
          children: [
            // 搜索框
            TextField(
              style: const TextStyle(fontSize: AppTheme.fontMd),
              autofocus: false,
              decoration: const InputDecoration(
                hintText: '搜索 姓名 或 手机号',
                prefixIcon: Icon(Icons.search, size: 24),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            // 客户列表
            Expanded(
              child: asyncCustomers.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败: $e')),
                data: (rawList) {
                  final list = rawList.cast<Customer>().where((c) => c.id != widget.excludeId).toList();
                  if (list.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('没有可选客户\n请先添加客户', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final c = list[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryLight,
                          radius: 24,
                          child: Text(
                            c.name.isNotEmpty ? c.name[0] : '?',
                            style: const TextStyle(fontSize: 18, color: AppTheme.primaryDark, fontWeight: FontWeight.w600),
                          ),
                        ),
                        title: Text(c.name, style: const TextStyle(fontSize: AppTheme.fontMd, fontWeight: FontWeight.w600)),
                        subtitle: Text(c.phone, style: const TextStyle(fontSize: AppTheme.fontXs)),
                        onTap: () => Navigator.of(context).pop(_ReferrerResult(c.id, c.name)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      ],
    );
  }
}