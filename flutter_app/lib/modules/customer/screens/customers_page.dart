// ============================================
// 暖客宝 客户页 (Plan F2 极简版)
// 单文件 3 widget: 列表 + 详情 + 表单
// 中老年易用: 字号 18pt+ / 按钮 64pt+ / FAB 80pt / 行高 80pt
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/customer.dart';
// fix-graph-zoom-pan (2026-09-16): auto-fit initial scale, user can see whole tree on open
import 'dart:math' as math;
import '../../../core/models/franchisee.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/big_button.dart';
import '../widgets/big_fab.dart';
import '../widgets/ai_insight_cards.dart';
import '../widgets/customer_activity_cards.dart';
import '../widgets/customer_row.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/franchise_chip.dart';
import '../../../core/utils/birthday.dart';
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
  /// 图谱初始取层数 (载荷旋钮, **不是** 层级上限 —— ADR-0011: 层级不限)
  ///   其余层级走懒加载: 用户选中某节点 → 点「展开下级」才拉一级 (GET :id/children)
  static const int _graphInitialDepth = 2;

  /// 折叠门槛 (主人 2026-09-18 拍): 全树加盟客户 **< 50** → 不折叠 (一次拉全树)
  ///   ≥ 50 → 折叠: 初始只画 [_graphInitialDepth] 层, 单击节点自动展开它正面 3 层
  static const int _graphNoFoldMaxNodes = 50;

  /// 单击节点时自动展开的层数 (主人: 「确保当前节点正面的 3 层都是展开的」)
  static const int _graphTapExpandLevels = 3;

  /// 「全树」请求深度 (≤50 节点时一次拉完; 服务端每次请求上限 16 层)
  static const int _graphFullDepth = 12;

  /// 布局深度上限 (纯布局保护; 实际节点由懒加载决定)
  static const int _graphLayoutMaxDepth = 12;

  /// 已展开节点的子级缓存 (nodeId → children); 用于合并展示树 + 再展开走缓存
  final Map<String, List<FranchiseeTreeNode>> _lazyChildren = {};
  /// 正在拉子级的节点 id (按钮 loading + 防重入)
  final Set<String> _loadingChildren = {};
  /// 当前是否「不折叠」模式 (全树 < 50 个节点 → 一次全展开; 隐藏 收起 按钮)
  bool _graphNoFold = false;

  /// 本次树变化是否由懒加载展开/收起引起 → 保留用户当前视窗 (不弹回根部)
  bool _keepCameraOnTreeChange = false;

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
    // 图谱 tab 数据源: 我的加盟树 (placement 二叉树)
    //
    // ★ 层级不限 + 懒加载 (ADR-0011, 主人 2026-09-18 拍):
    //   旧版硬限 4 层 → 现在只请初始 2 层 (载荷 O(前两层)), 深节点由用户展开
    //   (「上限」本身已从服务层去掉 —— 第 5 层、第 6 层都能建)
    // ★ 折叠策略 (主人 2026-09-18 拍):
    //   全树 < 50 个加盟客户 → 不折叠 (一次把全树拉回来, 小树别让用户一层层点)
    //   ≥ 50 → 折叠 (懒加载: 初始 _graphInitialDepth 层 + 单击节点自动展开正面 3 层)
    final asyncShallowTree =
        ref.watch(myFranchiseeTreeProvider(_graphInitialDepth));
    final shallowTotal = _rawTotalOf(asyncShallowTree);
    _graphNoFold =
        shallowTotal != null && shallowTotal < _graphNoFoldMaxNodes;
    final asyncTree = _graphNoFold
        ? ref.watch(myFranchiseeTreeProvider(_graphFullDepth))
        : asyncShallowTree;

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
        // ★ 懒加载合并: 把已展开节点的子级接回展示树 (不动 provider 里的对象)
        final rawTree = raw as FranchiseeTreeNode?;
        final tree = rawTree == null ? null : _withLazyChildren(rawTree);

        // ★ 业务空状态 (非错误, 不走 ErrorState):
        //   - tree == null: 后端 404 真错误 (franchiseeId 存在但记录被删)
        //   - id == "0" / name == "未加盟": user 没加盟关系 (dev mode / 普通用户)
        //   - 没有下级: 加盟了但没发展 (totalDescendants 是服务端全深度真值,
        //     不能拿 _countDescendants 比 — 懒加载后本地只加载了前两层)
        final isUnaffiliated =
            tree == null || tree.id == '0' || tree.name == '未加盟';
        final hasDownline = tree != null &&
            ((tree.totalDescendants ?? (_countDescendants(tree) - 1)) > 0);
        if (isUnaffiliated || !hasDownline) {
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
        // ADR-0011: 层数不限 → 布局深度给足, 实际节点由懒加载合并进来
        final layout = TreeLayout.compute(tree, maxDepth: _graphLayoutMaxDepth);
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
                                ? (_countDescendants(tree) - 1 <
                                        (tree.totalDescendants ?? 0)
                                    ? '单击看线 · 选中后可展开下级'
                                    : '单击看线 · 长按进详情')
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
                          // 共 N = 服务端全深度真值 (懒加载不缩水); 已展开 M = 当前画布上的下级数
                          (tree.totalDescendants ?? stats.total) >
                                  (_countDescendants(tree) - 1)
                              ? (_graphNoFold
                                  ? '共 ${tree.totalDescendants ?? stats.total} 位'
                                  : '共 ${tree.totalDescendants ?? stats.total} 位 · 已展开 ${_countDescendants(tree) - 1}')
                              : '共 ${tree.totalDescendants ?? stats.total} 位',
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
                    // 树变了 (懒加载展开/收起) 不无脑清选中:
                    //   选中的节点还在 → 保留选中 + 重算路径 (这样展开后能直接看到「收起」)
                    //   节点没了 → 才清 (路径失效)
                    if (_selectedNodeId != null &&
                        _findNodeById(tree, _selectedNodeId!) == null) {
                      _selectedNodeId = null;
                      _graphPathIds = const {};
                    }
                    final matrix =
                        _focusRootMatrix(viewport, canvasSize, rootCenter);
                    if (treeChanged) {
                      // 懒加载引起的树变化 (展开/收起) → 不重置相机,
                      // 否则用户每展开一个深节点就被弹回根部 (很难用)
                      if (_keepCameraOnTreeChange) {
                        _keepCameraOnTreeChange = false;
                      } else {
                        // InteractiveViewer 已挂载, build 期间不能动 controller → 下一帧设
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          _graphTransformController.value = matrix;
                        });
                      }
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
    final childrenLoaded = _lazyChildren.containsKey(node.id);
    final loading = _loadingChildren.contains(node.id);
    final canExpand =
        node.hasChildren && node.children.isEmpty && !childrenLoaded;
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
        // 懒加载 (ADR-0011): 有下级 + 未展开 → 「展开」; 展开了 → 「收起」
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (canExpand)
          TextButton.icon(
            onPressed: () => _expandNode(node),
            icon: const Icon(Icons.unfold_more, size: 20),
            label: const Text('展开下级', style: TextStyle(fontSize: 14)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          )
        else if (childrenLoaded && !_graphNoFold)
          TextButton.icon(
            onPressed: () => _collapseNode(node),
            icon: const Icon(Icons.unfold_less, size: 20),
            label: const Text('收起', style: TextStyle(fontSize: 14)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
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

  /// 懒加载: 拉某个节点的直接子级并缓入 (ADR-0011)
  Future<void> _expandNode(FranchiseeTreeNode node) async {
    await _ensureChildrenLoaded(node);
  }

  /// 收起 (只清本地展开缓存; 服务端不动)
  void _collapseNode(FranchiseeTreeNode node) {
    setState(() {
      _lazyChildren.remove(node.id);
      _keepCameraOnTreeChange = true; // 收起也不重置视窗
    });
  }

  /// 把已展开的子级合并进展示树 (递归拷贝, 不 mutate provider 对象)
  FranchiseeTreeNode _withLazyChildren(FranchiseeTreeNode node) {
    final loaded = _lazyChildren[node.id];
    final base = loaded ?? node.children;
    if (base.isEmpty) return node;
    return node.copyWith(
      children: base.map(_withLazyChildren).toList(),
      // 展开过的节点一定“有下级” (服务端已确认), 收起后仍能再展开
      hasChildren: node.hasChildren || loaded != null,
    );
  }

  /// 线别文案 (A线 / B线; 根节点不是任一线)
  String _lineLabelOf(String nodeId, TreeLayoutResult layout) {
    if (layout.aLineIds.contains(nodeId)) return 'A线';
    if (layout.bLineIds.contains(nodeId)) return 'B线';
    return '—';
  }

  /// 胶囊按键 segment 文案 (小圆点 + 文字 + 人数)
  /// 注: 圆点 8pt + 字号 13 + Flexible(ellipsis) —— 4 段平分时留余量,
  /// 人数到 3 位数 (e.g. 「A线 123」) 或窄屏 (360pt) 也不溢出
  Widget _filterLabel(String text, int count, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$text $count',
            style: const TextStyle(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
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

  /// 服务端直报的「全树下级数」(懒加载不缩水); 拿不到 → null
  static int? _rawTotalOf(AsyncValue<dynamic> async) {
    final raw = async.valueOrNull as FranchiseeTreeNode?;
    return raw?.totalDescendants;
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
    final tree = ref.read(myFranchiseeTreeProvider(_graphInitialDepth)).valueOrNull as FranchiseeTreeNode?;
    if (tree == null) return;
    final hit = _firstMatchNode(tree, lower);
    if (hit == null) return;
    final center =
        TreeLayout.compute(tree, maxDepth: _graphLayoutMaxDepth).positions[hit.id];
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
    final wasSelected = _selectedNodeId == node.id;
    setState(() {
      if (wasSelected) {
        _selectedNodeId = null;
        _graphPathIds = const {};
      } else {
        _selectedNodeId = node.id;
        _graphPathIds = _pathIdsTo(root, node.id) ?? {node.id};
      }
    });
    // 主人 2026-09-18 拍: 单击节点时, 确保它正面 3 层都是展开的
    //   (折叠模式下; 不折叠模式本来就是全展开 → 直接跳过)
    if (!wasSelected) {
      _ensureExpandedBelow(node, _graphTapExpandLevels);
    }
  }

  /// 确保 [node] 下面 [levels] 层都已展开 (逐层懒加载; 不折叠模式跳过)
  Future<void> _ensureExpandedBelow(FranchiseeTreeNode node, int levels) async {
    if (_graphNoFold || levels <= 0) return;
    var frontier = <FranchiseeTreeNode>[node];
    for (var lv = 0; lv < levels && frontier.isNotEmpty; lv++) {
      final next = <FranchiseeTreeNode>[];
      for (final n in frontier) {
        next.addAll(await _ensureChildrenLoaded(n));
      }
      frontier = next;
    }
  }

  /// 取某节点的直接子级: 缓存优先 → 树里已有就用树里的 → 否则拉一级 (ADR-0011)
  Future<List<FranchiseeTreeNode>> _ensureChildrenLoaded(
    FranchiseeTreeNode node,
  ) async {
    final cached = _lazyChildren[node.id];
    if (cached != null) return cached;
    if (node.children.isNotEmpty) {
      // 初始 1-2 层的子级本来就在树里 → 记进缓存, 语义跟「已展开」一致
      _lazyChildren[node.id] = node.children;
      return node.children;
    }
    if (!node.hasChildren) return const [];
    if (_loadingChildren.contains(node.id)) return const [];
    setState(() => _loadingChildren.add(node.id));
    try {
      final children =
          await ref.read(franchiseeServiceProvider).getChildren(node.id);
      if (!mounted) return const [];
      setState(() {
        _lazyChildren[node.id] = children;
        _loadingChildren.remove(node.id);
        _keepCameraOnTreeChange = true; // 展开不重置视窗
      });
      return children;
    } catch (e) {
      if (mounted) setState(() => _loadingChildren.remove(node.id));
      return const [];
    }
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
        // 1) 大头像 + 基本信息 (类型徽章 / 年龄 / 拨号)
        _buildHeader(context, ref, customer),
        const SizedBox(height: 12),

        // 2) 被动养生记录 (含汇总: 共 N 次 / 最近到店)
        _buildWellnessSection(context, asyncRecords),
        const SizedBox(height: 12),

        // 3) AI 智能区 (主人 2026-09-18 拍: 复购预测 / 客户画像 / 跟进建议 / 效果分析)
        //    顺序按「销售员每天最用得上」排: 复购预测 (自动算, 不烧额度) →
        //    跟进建议 (开口话术) → 客户画像 (这人是谁) → 效果分析 (疗程有没有用)
        _buildSectionTitle('AI 助手'),
        RepurchaseCard(customerId: customerId),
        AiFollowUpCard(customerId: customerId),
        AiProfileCard(customerId: customerId),
        EffectAnalysisCard(customerId: customerId),
        const SizedBox(height: 4),

        // 4) 跟进任务 (该客户待办, 可直接勾完成)
        CustomerFollowUpSection(customerId: customerId),

        // 5) 互动记录 (电话/微信/到店流水)
        CustomerInteractionSection(customerId: customerId),
      ],
    );
  }

  /// 养生记录区: 汇总 + 最近 5 条 + 入口
  Widget _buildWellnessSection(
    BuildContext context,
    AsyncValue<List<dynamic>> asyncRecords,
  ) {
    final fmt = DateFormat('yyyy-MM-dd');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.favorite, size: 26, color: AppTheme.accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('养生记录',
                      style: TextStyle(
                          fontSize: AppTheme.fontMd,
                          fontWeight: FontWeight.w700)),
                ),
                asyncRecords.maybeWhen(
                  data: (records) {
                    if (records.isEmpty) return const SizedBox.shrink();
                    final last = records.first.serviceDate.toString();
                    // Flexible: 窄屏/大字体下让文案省略, 不撑破 Row (中老年常放大系统字号)
                    return Flexible(
                      child: Text(
                        '共 ${records.length} 次 · 最近 ${fmt.format(DateTime.parse(last))}',
                        style: const TextStyle(
                            fontSize: AppTheme.fontXs,
                            color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            asyncRecords.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: LoadingState(),
              ),
              error: (e, _) => Text('加载失败: $e',
                  style: const TextStyle(color: AppTheme.danger)),
              data: (records) {
                if (records.isEmpty) {
                  return _buildEmptyHint('还没有记录', '点下面的「添加记录」开始');
                }
                return Column(
                  children: [
                    ...records.take(5).map((r) => _buildRecordTile(context, r)),
                    if (records.length > 5)
                      TextButton.icon(
                        onPressed: () => _showAllRecords(context, records),
                        icon: const Icon(Icons.expand_more, size: 22),
                        label: Text('查看全部 ${records.length} 条',
                            style: const TextStyle(fontSize: AppTheme.fontSm)),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: BigButton(
                    label: '+ 添加记录',
                    icon: Icons.add_circle_outline,
                    onPressed: () =>
                        showAddRecordSheet(context, customerId: customerId),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 全部记录 (底部弹层; 列表长了不把详情页撑爆)
  void _showAllRecords(BuildContext context, List<dynamic> records) {
    final fmt = DateFormat('yyyy-MM-dd');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView.builder(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: records.length,
          itemBuilder: (ctx, i) {
            final r = records[i];
            final parts = (r.bodyParts as List?)?.join('/') ?? '';
            return ListTile(
              leading: const Icon(Icons.favorite, color: AppTheme.accent),
              title: Text(fmt.format(DateTime.parse(r.serviceDate.toString())),
                  style: const TextStyle(fontSize: AppTheme.fontMd)),
              subtitle: Text(
                [
                  if (r.serviceItem != null) '${r.serviceItem}',
                  if (parts.isNotEmpty) parts,
                  if (r.customerFeedback != null) '反馈: ${r.customerFeedback}',
                ].join(' · '),
                style: const TextStyle(fontSize: AppTheme.fontSm),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/wellness-records/${r.id}');
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, Customer c) {
    final type = c.customerType;
    final age = c.birthYear == null
        ? null
        : DateTime.now().year - c.birthYear!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: AppTheme.avatarLg / 2,
              backgroundColor: type == 'franchisee'
                  ? AppTheme.franchisee.withOpacity(0.2)
                  : (type == 'seed'
                      ? AppTheme.accent.withOpacity(0.2)
                      : AppTheme.primaryLight),
              child: Text(
                c.name.isNotEmpty ? c.name[0] : '?',
                style: TextStyle(
                  fontSize: 36,
                  color: type == 'franchisee'
                      ? AppTheme.franchisee
                      : (type == 'seed'
                          ? AppTheme.accent
                          : AppTheme.primaryDark),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    c.name,
                    style: const TextStyle(
                      fontSize: AppTheme.fontXl,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                // 类型徽章 (加盟紫 / 种子橙 / 普通绿) —— 跟客户列表同口径
                FranchiseChip(type: type),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _maskPhone(c.phone),
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                color: AppTheme.textSecondary,
              ),
            ),
            if (c.gender != null || age != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (c.gender != null)
                    Chip(label: Text(c.gender == 'F' ? '女' : c.gender == 'M' ? '男' : '未知')),
                  if (age != null) Chip(label: Text('$age 岁')),
                  Chip(
                    label: Text(
                        '建档 ${DateFormat('yyyy-MM-dd').format(c.createdAt)}'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // 快捷操作: 打电话 / 记一次互动 (拨号在 web 不支持时静默失败)
            Row(
              children: [
                Expanded(
                  child: BigActionButton(
                    icon: Icons.phone,
                    label: '打电话',
                    compact: true,
                    onTap: () => _callCustomer(context, c.phone),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: BigActionButton(
                    icon: Icons.edit_note,
                    label: '记一次互动',
                    compact: true,
                    onTap: () => _showAddInteractionSheet(context, ref, c.id),
                  ),
                ),
              ],
            ),
            // 生日 + 提醒 (主人 2026-09-18)
            if (c.birthMonth != null && c.birthDay != null) ...[
              const SizedBox(height: 10),
              Builder(builder: (_) {
                final info = birthdayInfo(
                  month: c.birthMonth,
                  day: c.birthDay,
                  calendar: c.birthCalendar,
                );
                final due = isInBirthdayRemindWindow(
                  month: c.birthMonth,
                  day: c.birthDay,
                  calendar: c.birthCalendar,
                  remindDays: c.birthdayRemindDays,
                );
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: due
                        ? AppTheme.accent.withOpacity(0.18)
                        : AppTheme.bgWarm,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: due ? AppTheme.accent : const Color(0xFFEDE6DA),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cake_outlined,
                              size: 20,
                              color: due ? AppTheme.accent : AppTheme.primaryDark),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '生日 ${birthdayLabel(month: c.birthMonth, day: c.birthDay, calendar: c.birthCalendar, year: c.birthYear)}'
                              '${info != null ? ' · ${info.countdownLabel}' : ''}',
                              style: TextStyle(
                                fontSize: AppTheme.fontSm,
                                fontWeight: FontWeight.w600,
                                color: due ? AppTheme.accent : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '提醒: ${remindLabel(c.birthdayRemindDays)}'
                        '${info.nextSolarDate != null ? ' · 下次 ${info.nextSolarDate.year}-${info.nextSolarDate.month.toString().padLeft(2, '0')}-${info.nextSolarDate.day.toString().padLeft(2, '0')}' : ''}',
                        style: const TextStyle(
                            fontSize: AppTheme.fontXs,
                            color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                );
              }),
            ] else if (c.birthYear != null) ...[
              const SizedBox(height: 10),
              Text(
                '生日未填 (只知道年份 ${c.birthYear}) · 填上月日可开启生日提醒',
                style: const TextStyle(
                    fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
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
            if (c.allergyHistory != null && c.allergyHistory!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 20, color: AppTheme.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '过敏史: ${c.allergyHistory}',
                        style: const TextStyle(
                          fontSize: AppTheme.fontSm,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (c.healthTags.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildHealthTags(c),
            ],
          ],
        ),
      ),
    );
  }

  /// 拨号 (tel:) — web 不支持时给提示, 不崩
  Future<void> _callCustomer(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法拨号, 号码: $phone')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法拨号, 号码: $phone')),
        );
      }
    }
  }

  /// 记一次互动 (电话/微信/到店/节日问候/其他 + 备注)
  void _showAddInteractionSheet(
    BuildContext context, WidgetRef ref, String customerId) {
    const types = {
      'phone': '电话',
      'wechat': '微信',
      'visit': '到店',
      'holiday_greeting': '节日问候',
      'other': '其他',
    };
    var selected = 'phone';
    final summaryCtrl = TextEditingController();
    var saving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('记一次互动',
                  style: TextStyle(
                      fontSize: AppTheme.fontLg, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: types.entries
                    .map((e) => ChoiceChip(
                          label: Text(e.value,
                              style: const TextStyle(fontSize: AppTheme.fontSm)),
                          selected: selected == e.key,
                          onSelected: (_) =>
                              setSheetState(() => selected = e.key),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: summaryCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                    labelText: '聊了什么 (可选)', hintText: '例: 说腰疼好多了, 约下周三'),
              ),
              const SizedBox(height: 16),
              BigButton(
                label: saving ? '保存中...' : '保存',
                icon: Icons.check,
                onPressed: saving
                    ? () {}
                    : () async {
                        setSheetState(() => saving = true);
                        try {
                          await ref
                              .read(interactionServiceProvider)
                              .create({
                            'customerId': customerId,
                            'type': selected,
                            if (summaryCtrl.text.isNotEmpty)
                              'summary': summaryCtrl.text,
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('已记录')),
                            );
                          }
                          ref.invalidate(interactionsForCustomerProvider(customerId));
                        } catch (e) {
                          setSheetState(() => saving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('保存失败: $e')),
                            );
                          }
                        }
                      },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthTags(Customer c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '健康标签',
            style: TextStyle(
              fontSize: AppTheme.fontSm,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
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
  final _diseaseController = TextEditingController(); // 既往病史
  final _allergyController = TextEditingController(); // 过敏史 (2026-09-18 新增)
  final _customTagController = TextEditingController(); // 自定义健康标签
  String? _gender = 'F';
  DateTime? _birthYear;
  /// 生日 月/日 (主人 2026-09-18 拍): 都可缺 — 不知道就 null
  int? _birthMonth;
  int? _birthDay;
  /// 历法: solar 阳历 / lunar 农历
  String _birthCalendar = 'solar';
  /// 生日提醒强度 (7/3/0 天); null = 不提醒
  /// 规则: 月 + 日 都填 = 自动开启 (默认 3 天前); 任一个清空 = 关掉
  int? _birthdayRemindDays = 3;
  final List<String> _healthTags = [];

  /// 健康标签默认候选项 (中老年养生高频; 主人 2026-09-18 拍「显示一些默认候选项」)
  static const List<String> _defaultHealthTags = [
    '肩颈僵硬', '腰椎不适', '膝关节痛', '睡眠差',
    '体寒怕冷', '湿气重', '气血不足', '脾胃虚弱',
    '手脚冰凉', '头晕乏力', '更年期', '便秘',
  ];

  /// 自定义标签上限: 6 个汉字 (主人 2026-09-18 拍)
  static const int _maxTagLength = 6;
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
      _diseaseController.text = c.diseaseHistory ?? '';
      _allergyController.text = c.allergyHistory ?? '';
      _gender = c.gender;
      _birthYear = c.birthYear != null ? DateTime(c.birthYear!, 1, 1) : null;
      _birthMonth = c.birthMonth;
      _birthDay = c.birthDay;
      _birthCalendar = c.birthCalendar;
      _birthdayRemindDays = c.birthdayRemindDays;
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
    _diseaseController.dispose();
    _allergyController.dispose();
    _customTagController.dispose();
    super.dispose();
  }

  // ===== 生日: 年/月/日 各自可选填 (不知道就留空) =====

  /// 生日选择按钮 (值 == null 显示「不清楚」)
  Widget _birthPickerButton({
    required String label,
    required String? value,
    required VoidCallback onPick,
  }) {
    return OutlinedButton(
      onPressed: onPick,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ${value ?? '不清楚'}',
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
                color: value == null
                    ? AppTheme.textSecondary
                    : AppTheme.textPrimary,
              )),
        ],
      ),
    );
  }

  Future<void> _pickBirthYear() async {
    final year = await showDialog<int>(
      context: context,
      builder: (_) => _YearPickerDialog(initial: _birthYear?.year ?? 1965),
    );
    if (year == null) return;
    setState(() => _birthYear = DateTime(year, 1, 1));
  }

  /// 月 / 日 选择 (含「不清楚」= 清空)
  Future<void> _pickBirthPart({required bool isMonth}) async {
    final current = isMonth ? _birthMonth : _birthDay;
    final max = isMonth ? 12 : 31;
    final picked = await showDialog<int?>(
      context: context,
      builder: (_) => _NumberPickerDialog(
        title: isMonth ? '选择出生月份' : '选择出生日期',
        max: max,
        initial: current,
        suffix: isMonth ? '月' : '日',
      ),
    );
    if (picked == null && current == null) return;
    setState(() {
      if (isMonth) {
        _birthMonth = picked;
      } else {
        _birthDay = picked;
      }
      // 月+日 都有 → 默认开启提醒 (3 天前); 任一清空 → 关掉
      if (_birthMonth == null || _birthDay == null) {
        _birthdayRemindDays = null;
      } else if (_birthdayRemindDays == null) {
        _birthdayRemindDays = 3;
      }
    });
  }

  /// 自定义健康标签 (≤6 汉字, 去重, 空/超长给提示)
  void _addCustomTag() {
    final v = _customTagController.text.trim();
    if (v.isEmpty) return;
    if (v.runes.length > _maxTagLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标签最多 6 个字')),
      );
      return;
    }
    if (_healthTags.contains(v)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个标签已经有了')),
      );
      _customTagController.clear();
      return;
    }
    setState(() {
      _healthTags.add(v);
      _customTagController.clear();
    });
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
        // 生日细化 + 提醒 (显式发 null = 清空; 后端按月/日 自动开关提醒)
        'birthMonth': _birthMonth,
        'birthDay': _birthDay,
        'birthCalendar': _birthCalendar,
        'birthdayRemindDays': _birthdayRemindDays,
        'healthTags': _healthTags,
        'diseaseHistory': _diseaseController.text,
        'allergyHistory': _allergyController.text,
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
            // ===== 生日 (主人 2026-09-18: 年月日可选填 + 农历/阳历 + 生日提醒) =====
            const Text('生日', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: 4),
            const Text(
              '知道多少填多少, 不知道的留空 (例: 只记得属相/年份 → 只填年; 过农历生日 → 切「农历」)',
              style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _birthPickerButton(
                    label: '年',
                    value: _birthYear == null ? null : '${_birthYear!.year}',
                    onPick: _pickBirthYear,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _birthPickerButton(
                    label: '月',
                    value: _birthMonth == null ? null : '$_birthMonth',
                    onPick: () => _pickBirthPart(isMonth: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _birthPickerButton(
                    label: '日',
                    value: _birthDay == null ? null : '$_birthDay',
                    onPick: () => _pickBirthPart(isMonth: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 历法 (阳历 / 农历)
            Row(
              children: [
                const Text('历法:', style: TextStyle(fontSize: AppTheme.fontSm)),
                const SizedBox(width: 8),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'solar', label: Text('阳历', style: TextStyle(fontSize: 14))),
                      ButtonSegment(value: 'lunar', label: Text('农历', style: TextStyle(fontSize: 14))),
                    ],
                    selected: {_birthCalendar},
                    showSelectedIcon: false,
                    expandedInsets: EdgeInsets.zero,
                    onSelectionChanged: (v) =>
                        setState(() => _birthCalendar = v.first),
                  ),
                ),
              ],
            ),
            // 月+日 都填了 = 开启生日提醒 (提醒强度可选)
            if (_birthMonth != null && _birthDay != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.notifications_active_outlined,
                            size: 20, color: AppTheme.accent),
                        SizedBox(width: 6),
                        Text('生日提醒 (已开启)',
                            style: TextStyle(
                                fontSize: AppTheme.fontSm,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final d in const [7, 3, 0])
                          ChoiceChip(
                            label: Text(
                              d == 0 ? '生日当天' : '提前 $d 天',
                              style: const TextStyle(fontSize: AppTheme.fontSm),
                            ),
                            selected: _birthdayRemindDays == d,
                            onSelected: (_) =>
                                setState(() => _birthdayRemindDays = d),
                          ),
                        ChoiceChip(
                          label: const Text('不提醒',
                              style: TextStyle(fontSize: AppTheme.fontSm)),
                          selected: _birthdayRemindDays == null,
                          onSelected: (_) =>
                              setState(() => _birthdayRemindDays = null),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            // ===== 健康标签 (默认候选 + 自定义, 单个 ≤6 汉字; 主人 2026-09-18) =====
            const Text('健康标签', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: 4),
            const Text(
              '点一下选中/取消; 也可以自己加 (最多 6 个字)',
              style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 已选中的标签 (排前面, 一眼看全)
                ..._healthTags.map((t) => InputChip(
                      label: Text(t, style: const TextStyle(fontSize: AppTheme.fontSm)),
                      selected: true,
                      selectedColor: AppTheme.primaryLight,
                      onDeleted: () => setState(() => _healthTags.remove(t)),
                    )),
                // 默认候选 (未选中的)
                ..._defaultHealthTags
                    .where((t) => !_healthTags.contains(t))
                    .map((t) => FilterChip(
                          label: Text(t,
                              style: const TextStyle(fontSize: AppTheme.fontSm)),
                          selected: false,
                          onSelected: (_) =>
                              setState(() => _healthTags.add(t)),
                        )),
              ],
            ),
            const SizedBox(height: 8),
            // 自定义标签输入 (≤6 汉字)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customTagController,
                    style: const TextStyle(fontSize: AppTheme.fontMd),
                    maxLength: _maxTagLength,
                    decoration: const InputDecoration(
                      hintText: '自定义 (最多 6 个字)',
                      counterText: '',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addCustomTag(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _addCustomTag,
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('添加', style: TextStyle(fontSize: AppTheme.fontSm)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ===== 既往病史 / 过敏史 (主人 2026-09-18: 过敏史新增) =====
            TextField(
              controller: _diseaseController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '既往病史',
                hintText: '例: 高血压(服药中) / 腰椎间盘突出',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _allergyController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '过敏史',
                hintText: '例: 青霉素过敏 / 对薰衣草精油过敏 / 皮肤敏感',
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

/// 月 / 日 数字选择器 (含「不清楚」= 返回 null 清空)
class _NumberPickerDialog extends StatelessWidget {
  final String title;
  final int max;
  final int? initial;
  final String suffix;

  const _NumberPickerDialog({
    required this.title,
    required this.max,
    required this.suffix,
    this.initial,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: AppTheme.fontLg)),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        height: 300,
        width: 240,
        child: ListView.builder(
          itemCount: max + 1, // 第 0 项 = 不清楚
          itemBuilder: (context, i) {
            if (i == 0) {
              return ListTile(
                title: const Text('不清楚 / 清空',
                    style: TextStyle(fontSize: AppTheme.fontMd)),
                selected: initial == null,
                onTap: () => Navigator.of(context).pop(null),
              );
            }
            return ListTile(
              title: Text('$i$suffix', style: const TextStyle(fontSize: AppTheme.fontMd)),
              selected: i == initial,
              onTap: () => Navigator.of(context).pop(i),
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