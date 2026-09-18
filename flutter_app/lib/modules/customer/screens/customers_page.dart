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

/// 图谱快捷筛选 (图例即筛选 chips; none = 全部)
enum _GraphFilter { none, direct, downline, upline, aLine, bLine }

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
  /// 图谱请求/布局深度 (ADR-0010 硬上限 4) — 跟列表「加盟」胶囊口径保持同一个数
  static const int _graphDepth = 4;

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

  /// 底部给「回到我 / 全景」按钮预留的高度 (图区 viewport 要扣掉, 否则 fit/居中会偏)
  static const double _graphBottomControlsHeight = 56;

  /// 图谱视图状态 (LayoutBuilder 每次 layout 更新, 供「回到我」/「全景」按钮复用)
  /// fix-graph-ui-v3 (2026-09-17): 替换 v2 的 outer Transform 方案 —
  ///   旧方案把 InteractiveViewer 的 viewport 整体缩放, 画布反被 constraints 压成
  ///   viewport 大小, 图谱缩在左上角一小块 (主人截图就是这个)
  Size? _graphViewport;
  Size? _graphCanvasSize;
  double? _graphContentHeight;
  Offset? _graphRootCenter;
  bool _graphViewInitialized = false;

  /// 单击选中的节点 id (选中后突显它 + 高亮 它→「我」整条线 + 其余淡化)
  /// fix-graph-spine (2026-09-17 主人拍): 单击 = 看线, 长按 = 跳详情
  String? _selectedNodeId;
  Set<String> _graphPathIds = const {};

  /// 图谱快捷筛选 (全部 / 直推 / 下级引荐 / 上级引荐 / A线 / B线)
  _GraphFilter _graphFilter = _GraphFilter.none;

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
    final query = CustomerListQuery(
      search: _search.isEmpty ? null : _search,
      // 'all' 不发给后端 (省一次白筛); 其余是真过滤 (加盟派生 / 种子 is_seed)
      type: _filter == _CustomerFilter.all ? null : _filterToApi,
    );
    final asyncCustomers = ref.watch(customersProvider(query));
    // 胶囊数量 (跟当前搜索词联动; 加载中 = 不显示数字, 不闪 0)
    final typeCounts = ref
        .watch(customerTypeCountsProvider(_search.isEmpty ? null : _search))
        .valueOrNull;
    // 图谱 tab 数据源: 加盟客户的 2 线图谱 (复用 franchisee/me/tree)
    //
    // ★ 深度 = 4 (ADR-0010 硬上限), 主人 2026-09-18 拍:
    //   列表胶囊「加盟」口径 = 我的下级加盟商 (**全深度**, 见后端 myDownlineFranchiseeSql),
    //   图谱原先只请 depth=3 → 画 14 位, 列表却有 30 位 → 又是“两边对不上”.
    //   本 seed 数据是 5 层满二叉树 (1+2+4+8+16=31) → depth=4 刚好画全
    //   (将来层级更深时, 图谱仍受 ADR-0010 ≤4 限制, 胶囊数字会大于画面节点数 — 已知,
    //    真要一致得改 ADR-0010 或分页加载)
    final asyncTree = ref.watch(myFranchiseeTreeProvider(_graphDepth));

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
          // 筛选 (胶囊按键, 主人 2026-09-18 拍): 全部 / 加盟 / 普通 / 种子
          // 4 段平分整行宽, 选中 = 主题色实心; 跟图谱筛选 (全部/A线/B线/直推) 视觉一致
          // 2026-09-18 追加: 胶囊上显示数量 (跟图谱筛选同风格), 数量走 /api/customers/stats
          //   口径: 加盟 = 我的下级加盟商 (跟图谱 tab 同口径), 三类互斥穷尽 → 相加 = 全部
          if (_viewMode == _CustomerViewMode.list)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<_CustomerFilter>(
                segments: [
                  ButtonSegment(
                    value: _CustomerFilter.all,
                    label: _capsuleLabel('全部', 'all', typeCounts),
                  ),
                  ButtonSegment(
                    value: _CustomerFilter.franchisee,
                    label: _capsuleLabel('🟣 加盟', 'franchisee', typeCounts),
                  ),
                  ButtonSegment(
                    value: _CustomerFilter.normal,
                    label: _capsuleLabel('🟢 普通', 'normal', typeCounts),
                  ),
                  ButtonSegment(
                    value: _CustomerFilter.seed,
                    label: _capsuleLabel('🌱 种子', 'seed', typeCounts),
                  ),
                ],
                selected: {_filter},
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero, // 4 段平分整行宽
                onSelectionChanged: (s) => setState(() => _filter = s.first),
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
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(customersProvider),
      ),
      data: (rawCustomers) {
        // 类型筛选走后端 (主人 2026-09-18): ?type=franchisee|seed|normal
        final customers = rawCustomers.cast<Customer>();
        if (customers.isEmpty) {
          final filtered = _filter != _CustomerFilter.all;
          return EmptyState(
            icon: Icons.people_outline,
            title: _search.isNotEmpty
                ? '没找到客户'
                : (filtered ? '没有${_filterLabelText}客户' : '还没有客户'),
            hint: _search.isNotEmpty
                ? '换个名字试试'
                : (filtered ? '换个筛选看看，或点「全部」' : '点击右下角 + 添加第一位客户'),
            onAction: () => context.push('/customers/new'),
            actionLabel: '+ 添加客户',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(customersProvider),
          child: ListView.builder(
            itemCount: customers.length,
            itemBuilder: (context, i) {
              final c = customers[i];
              return CustomerRow(
                customer: c,
                // 类型徽章 = 后端算好的 customerType (加盟 > 种子 > 普通)
                isFranchisee: c.customerType == 'franchisee',
                customerType: c.customerType,
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
        const depth = _graphDepth;
        final layout = TreeLayout.compute(tree, maxDepth: depth);
        final canvasSize = layout.canvasSize;
        final positions = layout.positions;
        final searchMatchedIds = searchQuery.isEmpty
            ? null
            : _collectMatches(tree, searchQuery.toLowerCase());

        // 三维区分 (主人 2026-09-17 拍): 线别 (A/B) × 关系 (直推/下级引荐/上级引荐)
        final relations = _collectRelations(tree);
        final stats = _graphStats(tree, layout);
        final filterIds = _filterIdsFor(tree, layout);
        final selectedNode = _selectedNodeId == null
            ? null
            : _findNodeById(tree, _selectedNodeId!);

        return Column(
          children: [
            // 顶部提示条: 选中节点属性 / 搜索命中数 / 默认指引
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: searchQuery.isNotEmpty
                  ? (matchCount > 0
                      ? AppTheme.primaryLight.withOpacity(0.5)
                      : AppTheme.danger.withOpacity(0.08))
                  : AppTheme.primaryLight.withOpacity(0.3),
              child: (selectedNode != null && searchQuery.isEmpty)
                  ? _buildSelectedNodeBar(selectedNode, layout)
                  : Row(
                      children: [
                        Icon(
                          searchQuery.isNotEmpty
                              ? Icons.search
                              : Icons.touch_app_outlined,
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
                          '共 ${stats.total} 位',
                          style: const TextStyle(
                            fontSize: AppTheme.fontSm,
                            color: AppTheme.primaryDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
            // 筛选 (胶囊按键, 主人 2026-09-17 拍): 全部 / A线 / B线 / 直推
            // 点 = 只看这一类 (其余淡化); 再点「全部」恢复
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: SegmentedButton<_GraphFilter>(
                segments: [
                  const ButtonSegment(
                    value: _GraphFilter.none,
                    label: Text('全部', style: TextStyle(fontSize: 14)),
                  ),
                  ButtonSegment(
                    value: _GraphFilter.aLine,
                    label: _filterLabel('A线', stats.aLine, AppTheme.franchiseeA),
                  ),
                  ButtonSegment(
                    value: _GraphFilter.bLine,
                    label: _filterLabel('B线', stats.bLine, AppTheme.franchiseeB),
                  ),
                  ButtonSegment(
                    value: _GraphFilter.direct,
                    label: _filterLabel('直推', stats.direct, AppTheme.accent),
                  ),
                ],
                selected: {_graphFilter},
                showSelectedIcon: false,
                expandedInsets: EdgeInsets.zero, // 4 段平分整行宽
                onSelectionChanged: (s) =>
                    setState(() => _graphFilter = s.first),
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
                  final viewport = Size(
                    constraints.maxWidth,
                    constraints.maxHeight - _graphBottomControlsHeight,
                  );
                  final rootCenter = positions[tree.id] ??
                      Offset(canvasSize.width / 2,
                          TreeLayout.padding + TreeLayout.nodeRadius);
                  _graphViewport = viewport;
                  _graphRootCenter = rootCenter;
                  _graphContentHeight = layout.contentHeight;

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
                          // 底部给「回到我 / 全景」按钮留一条 (图谱不钻到按钮下面)
                          // (最下层节点的名字不再被按钮盖住)
                          child: Padding(
                            padding: const EdgeInsets.only(
                                bottom: _graphBottomControlsHeight),
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
                                    // 监听缩放: 缩小看全局时少画外侧名字/角标 (减噪)
                                    child: ValueListenableBuilder<Matrix4>(
                                      valueListenable: _graphTransformController,
                                      builder: (context, matrix, _) {
                                        final scale =
                                            matrix.getMaxScaleOnAxis();
                                        return CustomPaint(
                                          size: canvasSize,
                                          painter: FranchiseTreePainter(
                                            root: tree,
                                            positions: positions,
                                            columns: layout.columns,
                                            scale: scale,
                                            columnPitch: layout.columnPitch,
                                            searchMatchedIds: searchMatchedIds,
                                            currentUserId: tree.id,
                                            selectedNodeId: _selectedNodeId,
                                            pathIds: _graphPathIds,
                                            spineIds: layout.spineIds,
                                            aLineIds: layout.aLineIds,
                                            bLineIds: layout.bLineIds,
                                            relations: relations,
                                            filterIds: filterIds,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  ..._buildHitareas(
                                      tree, tree, positions, layout.columns),
                                ],
                              ),
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

  /// 选中节点属性条 (名字 · 线别 · 关系 · 层级)
  Widget _buildSelectedNodeBar(FranchiseeTreeNode node, TreeLayoutResult layout) {
    final line = _lineLabelOf(node.id, layout);
    return Row(
      children: [
        const Icon(Icons.account_tree_outlined, size: 20, color: AppTheme.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${node.name} · $line · ${node.relation.label} · 第${node.placementDepth}层',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppTheme.fontSm,
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 20),
          tooltip: '取消选中',
          visualDensity: VisualDensity.compact,
          onPressed: _clearSelection,
        ),
      ],
    );
  }

  /// 线别文案 (A线 / B线; 根节点不是任一线)
  String _lineLabelOf(String nodeId, TreeLayoutResult layout) {
    if (layout.aLineIds.contains(nodeId)) return 'A线';
    if (layout.bLineIds.contains(nodeId)) return 'B线';
    return '—';
  }

  /// 胶囊按键 segment 文案 (小圆点 + 文字 + 人数)
  Widget _filterLabel(String text, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text('$text $count', style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  /// 节点 id → 关系 (后端 relation 收成 map 给 painter)
  Map<String, FranchiseeRelation> _collectRelations(FranchiseeTreeNode node) {
    final map = <String, FranchiseeRelation>{node.id: node.relation};
    for (final c in node.children) {
      map.addAll(_collectRelations(c));
    }
    return map;
  }

  /// 图谱统计 (共 / 直推 / 下级引荐 / 上级引荐 / A线 / B线)
  ({
    int total,
    int direct,
    int downline,
    int upline,
    int aLine,
    int bLine,
  }) _graphStats(FranchiseeTreeNode tree, TreeLayoutResult layout) {
    var direct = 0;
    var downline = 0;
    var upline = 0;
    void walk(FranchiseeTreeNode n) {
      switch (n.relation) {
        case FranchiseeRelation.direct:
          direct++;
          break;
        case FranchiseeRelation.downline:
          downline++;
          break;
        case FranchiseeRelation.upline:
          upline++;
          break;
        case FranchiseeRelation.root:
          break;
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(tree);
    return (
      total: direct + downline + upline,
      direct: direct,
      downline: downline,
      upline: upline,
      aLine: layout.aLineIds.length,
      bLine: layout.bLineIds.length,
    );
  }

  /// 当前筛选命中的节点 id 集合 (null = 无筛选)
  Set<String>? _filterIdsFor(FranchiseeTreeNode tree, TreeLayoutResult layout) {
    switch (_graphFilter) {
      case _GraphFilter.none:
        return null;
      case _GraphFilter.aLine:
        return layout.aLineIds;
      case _GraphFilter.bLine:
        return layout.bLineIds;
      case _GraphFilter.direct:
        return _idsWhere(
            tree, (n) => n.relation == FranchiseeRelation.direct);
      case _GraphFilter.downline:
        return _idsWhere(
            tree, (n) => n.relation == FranchiseeRelation.downline);
      case _GraphFilter.upline:
        return _idsWhere(
            tree, (n) => n.relation == FranchiseeRelation.upline);
    }
  }

  Set<String> _idsWhere(
    FranchiseeTreeNode node,
    bool Function(FranchiseeTreeNode) test,
  ) {
    final out = <String>{};
    if (test(node)) out.add(node.id);
    for (final c in node.children) {
      out.addAll(_idsWhere(c, test));
    }
    return out;
  }

  /// 按 id 找节点 (选中信息条用)
  FranchiseeTreeNode? _findNodeById(FranchiseeTreeNode node, String id) {
    if (node.id == id) return node;
    for (final c in node.children) {
      final hit = _findNodeById(c, id);
      if (hit != null) return hit;
    }
    return null;
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

  /// 「回到我」视图: 根节点 (我) 顶部居中 + 竖直能放下整棵树的可读缩放 (上限 1:1)
  Matrix4 _focusRootMatrix(Size viewport, Size canvasSize, Offset rootCenter) {
    const topMargin = 20.0;
    final contentHeight = _graphContentHeight ?? canvasSize.height;
    final fit = (viewport.height - topMargin - 8) / contentHeight;
    // 0.5 下限: 再小就没法读了; 1.0 上限: 不放大超过 1:1
    final scale = math.min(1.0, math.max(0.5, fit));
    final dx = viewport.width / 2 - rootCenter.dx * scale;
    final dy = topMargin - (rootCenter.dy - TreeLayout.nodeRadius) * scale;
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
    final tree = ref.read(myFranchiseeTreeProvider(_graphDepth)).valueOrNull as FranchiseeTreeNode?;
    if (tree == null) return;
    final hit = _firstMatchNode(tree, lower);
    if (hit == null) return;
    final center =
        TreeLayout.compute(tree, maxDepth: _graphDepth).positions[hit.id];
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
    Map<String, int> columns,
  ) {
    final widgets = <Widget>[];
    final pos = positions[node.id];
    if (pos == null) return widgets;
    // 外侧节点更小 (前后立体), 点击区跟着半径走
    final radius = TreeLayout.radiusForColumn(columns[node.id] ?? 0);
    widgets.add(
      Positioned(
        left: pos.dx - radius,
        top: pos.dy - radius,
        width: radius * 2,
        // 圆下方到名字/A线B线标签都算可点 (中老年手指粗, 别只让圆圈可点)
        height: radius * 2 + 44,
        child: GestureDetector(
          onTap: () => _selectNode(root, node),
          onLongPress: () => context.push('/franchisees/${node.id}'),
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
      ),
    );
    for (final child in node.children) {
      widgets.addAll(_buildHitareas(root, child, positions, columns));
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

  /// 胶囊标签 (带数量): 数量拿到前只显示文字, 不闪 0 / 不闪占位
  Widget _capsuleLabel(String text, String typeKey, Map<String, int>? counts) {
    final n = counts?[typeKey];
    return Text(
      n == null ? text : '$text $n',
      style: const TextStyle(fontSize: 14),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 胶囊筛选 → 后端 type 参数 (all 不发)
  String get _filterToApi {
    switch (_filter) {
      case _CustomerFilter.all:
        return 'all';
      case _CustomerFilter.franchisee:
        return 'franchisee';
      case _CustomerFilter.normal:
        return 'normal';
      case _CustomerFilter.seed:
        return 'seed';
    }
  }

  /// 空状态文案用 (不含 emoji)
  String get _filterLabelText {
    switch (_filter) {
      case _CustomerFilter.all:
        return '';
      case _CustomerFilter.franchisee:
        return '加盟';
      case _CustomerFilter.normal:
        return '普通';
      case _CustomerFilter.seed:
        return '种子';
    }
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

  /// 种子客户 (潜在客户开关, 主人 2026-09-18 拍 — 显式勾选)
  /// 注意: 已加盟客户 (同手机号有加盟商记录) 后端会优先显示「加盟」, 这个开关就不生效
  bool _isSeed = false;

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
      _isSeed = c.isSeed;
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
        // 种子客户开关 (后端算进 customerType: 加盟 > 种子 > 普通)
        'isSeed': _isSeed,
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
            // 种子客户开关 (潜在客户, 胶囊筛选「种子」命中这里)
            Container(
              decoration: BoxDecoration(
                color: _isSeed ? AppTheme.accent.withOpacity(0.12) : Colors.white,
                border: Border.all(
                  color: _isSeed ? AppTheme.accent : const Color(0xFFD0D0D0),
                  width: _isSeed ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                value: _isSeed,
                onChanged: (v) => setState(() => _isSeed = v),
                activeColor: AppTheme.accent,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                title: const Text('🌱 种子客户', style: TextStyle(fontSize: AppTheme.fontMd)),
                subtitle: const Text(
                  '还没体验过/刚加好友的潜在客户。勾上后客户列表可用「种子」筛出',
                  style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
                ),
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
    // 推荐人选择器不按类型筛 (所有客户都可能当推荐人)
    final asyncCustomers =
        ref.watch(customersProvider(CustomerListQuery(search: _search.isEmpty ? null : _search)));

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