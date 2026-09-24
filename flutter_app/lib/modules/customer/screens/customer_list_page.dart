// ============================================
// 暖客宝 客户列表页 (B1 客户域换装, 2026-09-24)
//
// 本文件从 customers_page.dart 拆出 (2026-09-24).
// 拆分目的: 4017 行的"上帝文件" → 5 个文件. 每个文件 ≤ 1200 行.
//
// 拆分原则 (B1 任务书 §2):
//   - 列表视图 + 图谱视图都在本文件 (互为切换, 共享 provider / state)
//   - 详情 + 表单 + 弹层 = 各自独立文件
//   - 行为零改动: 拆分前后, 用户能看到的每一处一模一样
//
// 中老年易用 (B 档前时代) → B 档 (B0/B1 换装):
//   - 行高 80 → 60 (AppListRow), 一屏可看 9+ 客户
//   - FAB 80 → 56 (主题 FloatingActionButton)
//   - 旧 BigFab/AppButton 调用点 → 标准组件 (本批不动文件本身)
// ============================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/follow_up_info.dart';
import '../../../core/models/franchisee.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/app_empty.dart';
import '../../presentation/graph/widgets/franchise_tree_painter.dart';
import '../widgets/customer_row.dart';
import 'customer_pickers.dart' show GroupHeaderData;

import '../../../core/theme/tokens.g.dart';

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
  /// 搜索埋点去抖 (打字 800ms 后才记一次, 不逐字母上报)
  Timer? _searchTrackTimer;
  _CustomerFilter _filter = _CustomerFilter.all;

  /// 排序 = 产品内部规则, **不做用户选择** (主人 2026-09-21 拍):
  ///   紧急度 → 最近联系 → 最近添加, 由后端 sortByUrgency 级联算好 (见 attach.ts)
  ///   前端不摆胶囊给用户挑; 非会员后端降级为「最近添加」(Q1 会员判权不变)
  static const String _sortRule = 'urgency';

  /// 折叠的分组 (主人 2026-09-20 拍 P1: 分组可折叠; 默认全展开, 休眠池默认折叠)
  final Set<String> _collapsedGroups = {'p4'};

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
  /// 上层格中心 (画布坐标; null = 这一格不画) —— 初始相机要以它为上沿, 否则它被顶出屏幕
  Offset? _graphUplineCapCenter;
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
    _searchTrackTimer?.cancel();
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
      // 排序 = 内部规则 (主人 2026-09-21): 固定紧急度, 用户不选
      sort: _sortRule,
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
        toolbarHeight: AppSize.appBarHeight,
        actions: [
          // 落位「三方确认」待办入口 (主人 2026-09-18 拍) — 有待确认时红点
          Consumer(
            builder: (context, ref, _) {
              final count =
                  ref.watch(placementToConfirmCountProvider).valueOrNull ?? 0;
              return IconButton(
                tooltip: '待我确认的加盟落位',
                onPressed: () async {
                  await context.push('/franchisees/placement-requests');
                  ref.invalidate(placementToConfirmCountProvider);
                  ref.invalidate(myFranchiseeTreeProvider);
                },
                icon: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: const Icon(Icons.fact_check_outlined, size: AppSize.iconLg),
                ),
              );
            },
          ),
          // 列表/图谱 切换 (Material 3 SegmentedButton)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s8),
            child: SegmentedButton<_CustomerViewMode>(
              // fix-graph-ui-v3 (2026-09-17): 去 icon + 去掉 compact/shrinkWrap
              //   旧版 (icon 20 + label 14 + compact) 每个 segment 只有 63pt 宽,
              //   "列表"/"图谱" 被挤到竖排 2 行 (字号小=图标宽度), 主人截图里就是歪的
              //   现在纯文字 15pt + 默认密度: segment ≈54pt, 文字单行, 点击区 40pt
              segments: const [
                ButtonSegment(
                  value: _CustomerViewMode.list,
                  label: Text('列表', style: TextStyle(fontSize: AppType.sm)),
                ),
                ButtonSegment(
                  value: _CustomerViewMode.graph,
                  label: Text('图谱', style: TextStyle(fontSize: AppType.sm)),
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
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: InputDecoration(
                hintText: _viewMode == _CustomerViewMode.graph
                    ? '搜索客户姓名 (高亮匹配节点)'
                    : '搜索 姓名 或 手机号',
                prefixIcon: const Icon(Icons.search, size: AppSize.iconXl),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: AppSize.iconMd),
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
                // 用量: 停止输入 800ms 后记一次 (只记长度, 不记关键词 — 红线§4.4.5)
                _searchTrackTimer?.cancel();
                _searchTrackTimer = Timer(const Duration(milliseconds: 800), () {
                  if (v.trim().isEmpty) return;
                  if (!mounted) return;
                  ref.read(usageServiceProvider).track('customer_search',
                      props: {'keywordLen': v.trim().length});
                });
              },
            ),
          ),
          // 筛选 (胶囊按键, 主人 2026-09-18 拍): 全部 / 加盟 / 普通 / 种子
          // 4 段平分整行宽, 选中 = 主题色实心; 跟图谱筛选 (全部/A线/B线/直推) 视觉一致
          // 2026-09-18 追加: 胶囊上显示数量 (跟图谱筛选同风格), 数量走 /api/customers/stats
          //   口径: 加盟 = 我的下级加盟商 (跟图谱 tab 同口径), 三类互斥穷尽 → 相加 = 全部
          if (_viewMode == _CustomerViewMode.list)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, 16, 8),
              child: SegmentedButton<_CustomerFilter>(
                segments: [
                  ButtonSegment(
                    value: _CustomerFilter.all,
                    label: _capsuleLabel('全部', 'all', typeCounts),
                  ),
                  ButtonSegment(
                    value: _CustomerFilter.franchisee,
                    label: _capsuleLabel('🤝 加盟', 'franchisee', typeCounts),
                  ),
                  ButtonSegment(
                    value: _CustomerFilter.normal,
                    label: _capsuleLabel('👤 普通', 'normal', typeCounts),
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

          // 顶部提醒条 (主人 2026-09-20 拍 P1): 「今天要联系 N 位」—— 仅会员 (summary 有值才显示)
          if (_viewMode == _CustomerViewMode.list &&
              (asyncCustomers.valueOrNull?.summary?.isEmpty == false))
            _buildReminderBar(asyncCustomers.valueOrNull!.summary!),

          // 主体: 列表 / 图谱
          Expanded(
            child: _viewMode == _CustomerViewMode.list
                ? _buildListView(asyncCustomers, null)
                : _buildGraphView(asyncTree),
          ),
        ],
      ),
      // fix-graph-ui (2026-09-17): graph 视图下隐藏 FAB (FAB 会遮右子节点;
      //   graph 主要用来查看关系, 添加客户走列表视图 FAB 更顺手)
      floatingActionButton: _viewMode == _CustomerViewMode.list
          ? FloatingActionButton(
              // 主题里已配 56pt 圆形 FAB (AppSize.fabSize), 无需 SizedBox
              onPressed: () => context.push('/customers/new'),
              tooltip: '添加客户',
              child: const Icon(Icons.add),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  static String _levelLabelOf(String level) {
    switch (level) {
      case 'p0':
        return '今天必须联系';
      case 'p1':
        return '本周联系';
      case 'p2':
        return '两周内联系';
      case 'p3':
        return '正常节奏';
      default:
        return '休眠池';
    }
  }

  /// 顶部提醒条: 今天要联系 / 逾期 / 本周 (会员)
  Widget _buildReminderBar(FollowUpSummary s) {
    final parts = <String>[];
    if (s.dueToday > 0) parts.add('今天要联系 ${s.dueToday} 位');
    if (s.overdue > 0) parts.add('逾期 ${s.overdue} 位');
    if (s.thisWeek > 0) parts.add('本周 ${s.thisWeek} 位');
    final text = parts.isEmpty ? '节奏都很稳，没有要紧急联系的客户' : parts.join(' · ');
    final urgent = s.dueToday > 0 || s.overdue > 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(AppSpace.s16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s10),
      decoration: BoxDecoration(
        color: (urgent ? AppTheme.danger : AppTheme.primary).withOpacity(0.10),
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(
          color: (urgent ? AppTheme.danger : AppTheme.primary).withOpacity(0.35),
        ),
      ),
      child: Row(
        children: [
          Text(urgent ? '🔴' : '🟢', style: const TextStyle(fontSize: AppType.sm)),
          const SizedBox(width: AppSpace.s8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                fontWeight: FontWeight.w600,
                color: urgent ? AppTheme.danger : AppTheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 分组表头 (可折叠): 🔴 今天必须联系 (3)
  Widget _buildGroupHeader(String level, String label, int count) {
    final collapsed = _collapsedGroups.contains(level);
    final color = CustomerRow.levelColor(level);
    return InkWell(
      onTap: () => setState(() {
        if (collapsed) {
          _collapsedGroups.remove(level);
        } else {
          _collapsedGroups.add(level);
        }
      }),
      child: Container(
        color: AppTheme.bgWarm,
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 10, 16, 6),
        child: Row(
          children: [
            Container(width: AppSpace.s8, height: AppSpace.s8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
            const SizedBox(width: AppSpace.s8),
            Text(
              label,
              style: TextStyle(fontSize: AppTheme.fontSm, fontWeight: FontWeight.w700, color: color),
            ),
            const SizedBox(width: AppSpace.s6),
            Text('($count)', style: TextStyle(fontSize: AppTheme.fontXs, color: color)),
            const Spacer(),
            Icon(collapsed ? Icons.expand_more : Icons.expand_less, size: AppSize.iconMd, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(
    AsyncValue<CustomerListResult> asyncCustomers,
    AsyncValue<dynamic>? _unused,
  ) {
    return asyncCustomers.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(customersProvider),
      ),
      data: (result) {
        final customers = result.items;
        if (customers.isEmpty) {
          final filtered = _filter != _CustomerFilter.all;
          return AppEmptyState(
            icon: Icons.people_outline,
            title: _search.isNotEmpty
                ? '没找到客户'
                : (filtered ? '没有${_filterLabelText}客户' : '还没有客户'),
            hint: _search.isNotEmpty
                ? '换个名字试试'
                : (filtered ? '换个筛选看看，或点「全部」' : '点击右下角 + 添加第一位客户'),
            action: FilledButton(
              onPressed: () => context.push('/customers/new'),
              child: const Text('+ 添加客户'),
            ),
          );
        }
        // 分组 (主人 2026-09-20 拍 P1): 仅紧急度排序下按分档分组; 表头可折叠 (休眠池默认折叠)
        final display = <Object>[];
        if (result.sort == 'urgency') {
          final counts = <String, int>{};
          for (final r in customers) {
            final lv = r.followUp?.level ?? 'p4';
            counts[lv] = (counts[lv] ?? 0) + 1;
          }
          String? cur;
          for (final r in customers) {
            final lv = r.followUp?.level ?? 'p4';
            if (lv != cur) {
              cur = lv;
              display.add(GroupHeaderData(
                level: lv,
                label: r.followUp?.levelLabel ?? _levelLabelOf(lv),
                count: counts[lv] ?? 0,
              ));
            }
            if (!_collapsedGroups.contains(lv)) display.add(r);
          }
        } else {
          display.addAll(customers);
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(customersProvider),
          child: ListView.builder(
            itemCount: display.length,
            itemBuilder: (context, i) {
              final item = display[i];
              if (item is GroupHeaderData) {
                return _buildGroupHeader(item.level, item.label, item.count);
              }
              final row = item as CustomerWithFollowUp;
              final c = row.customer;
              return CustomerRow(
                customer: c,
                // 类型徽章 = 后端算好的 customerType (加盟 > 种子 > 普通)
                isFranchisee: c.customerType == 'franchisee',
                customerType: c.customerType,
                pendingCount: 0,
                followUp: row.followUp,
                // 会员标识 = 后端算好的 isMember (同手机号账号的会员状态)
                isMember: row.isMember,
                onTap: () => context.push('/customers/${c.id}'),
              );
            },
          ),
        );
      },
    );
  }

  /// 图谱最上方「上层点位」链 (ADR-0015 Q13, 主人 2026-09-22 拍「上行最多 3 层直系」)
  ///
  ///   口径 (主人原话): 「上层」= **点位父**, 不一定是推荐码提供人。
  ///   - 后端给 `uplines` (由近到远, 最多 3 个) → 每层画一格 (单线直上; 最远在上)
  ///   - 我是树根 (上层空着) → 一格虚线「上层 · 虚位以待」→ 点它去认领
  ///   - 我发起的认领单还 pending → 虚线「待她确认」
  ///   ⚠ 上层一旦有人就不可撤换 (联系系统管理员协商处理); 所以这里**没有**换上层入口
  List<UplineCap> _uplineCapsOf(FranchiseeTreeNode tree) {
    if (tree.id == '0' || tree.name == '未加盟') return const [];
    if (tree.uplines.isNotEmpty) {
      // 邻居顺序 = 近 → 远; 画布上最远在最上 (布局时按 index 倒序定位)
      return tree.uplines
          .map(
            (up) => UplineCap(
              node: FranchiseeTreeNode(
                id: up.id,
                name: up.name,
                // ⚠ side 不往节点上放: painter 会在圆下再画一次「A线/B线」标签, 而那一行的位置
                //   正好压在「我」的圆上 (而且我自己的节点下面已经标了我在她的哪条线) → 只留在弹层里说
                placementSide: null,
                placementDepth: up.depth,
                relation: FranchiseeRelation.upline,
                children: const [],
                member: up.member,
              ),
            ),
          )
          .toList();
    }
    // 不是树根却没有上层 → 数据异常 (父节点被删), 不画, 免得误导
    if (tree.placementSide != null) return const [];
    final req = tree.uplineRequest;
    if (req != null) {
      return [
        UplineCap(
          node: FranchiseeTreeNode(
            id: '__upline_slot__',
            name: '「${req.newName ?? "上级"}」· 待她确认',
            placementSide: null,
            placementDepth: -1,
            relation: FranchiseeRelation.upline,
            children: const [],
          ),
          ghost: true,
          hint: '点此查看确认进度',
        ),
      ];
    }
    return [
      UplineCap(
        node: FranchiseeTreeNode(
          id: '__upline_slot__',
          name: '上层 · 虚位以待',
          placementSide: null,
          placementDepth: -1,
          relation: FranchiseeRelation.upline,
          children: const [],
        ),
        ghost: true,
        hint: '点此认领一位上级',
      ),
    ];
  }

  /// 布局 + 上层链: 整棵树整体下移 N 层, 空出来的最上面 N 层放上层格
  ///   caps 顺序 = 近 → 远; 画布上最远在最上 (index 越大越靠上)
  ///
  /// 为什么不下移不显示、也不把上层塞进布局算法:
  ///   塞进去 = 我这棵树会被当成上层的一条腿 (A线或B线), 整棵树被算歪到一侧;
  ///   下移 N 层 = 我的子树保持原来的双主线形状, 上面顶 N 格, 视觉最稳。
  TreeLayoutResult _layoutWithUpline(
    FranchiseeTreeNode tree,
    List<UplineCap> caps,
  ) {
    final base = TreeLayout.compute(tree, maxDepth: _graphLayoutMaxDepth);
    if (caps.isEmpty) return base;
    final rootPos = base.positions[tree.id];
    if (rootPos == null) return base;
    final n = caps.length;
    final capPositions = <String, Offset>{};
    for (var i = 0; i < n; i++) {
      // i=0 (最近) 紧贴「我」上方; i=n-1 (最远) 在最上
      capPositions[caps[i].node.id] = Offset(
        rootPos.dx,
        rootPos.dy + (n - 1 - i) * TreeLayout.levelHeight,
      );
    }
    final positions = <String, Offset>{
      for (final e in base.positions.entries)
        e.key: e.value + Offset(0, n * TreeLayout.levelHeight),
      ...capPositions,
    };
    return TreeLayoutResult(
      positions: positions,
      columns: {...base.columns, for (final c in caps) c.node.id: 0},
      depths: {
        ...base.depths,
        for (var i = 0; i < n; i++) caps[i].node.id: i,
      },
      spineIds: base.spineIds,
      aLineIds: base.aLineIds,
      bLineIds: base.bLineIds,
      leftColumns: base.leftColumns,
      rightColumns: base.rightColumns,
      contentHeight: base.contentHeight + n * TreeLayout.levelHeight,
      columnPitch: base.columnPitch,
      canvasSize: Size(
        base.canvasSize.width,
        base.canvasSize.height + n * TreeLayout.levelHeight,
      ),
    );
  }

  /// 上层格点击区: 虚位 → 认领; 待确认 → 「待我确认」页; 有人 → 她的信息 (每层各自可点)
  List<Widget> _buildUplineCapHitarea(
    FranchiseeTreeNode tree,
    Map<String, Offset> positions,
  ) {
    final caps = _uplineCapsOf(tree);
    if (caps.isEmpty) return const [];
    final radius = TreeLayout.nodeRadius;
    return [
      for (final cap in caps)
        if (positions[cap.node.id] != null)
          Positioned(
            left: positions[cap.node.id]!.dx - radius,
            top: positions[cap.node.id]!.dy - radius,
            width: radius * 2,
            height: radius * 2 + 52,
            child: Semantics(
              button: true,
              label: cap.ghost
                  ? '上层点位 ${cap.node.name}, 点击认领上级'
                  : '我的上层 ${cap.node.name}',
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _onTapUplineCap(tree, cap);
                },
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
          ),
    ];
  }

  /// 从上层链里按节点 id 取那一位 (点哪格开哪位的弹层)
  FranchiseeUpline? _uplineByNodeId(FranchiseeTreeNode tree, String id) {
    for (final u in tree.uplines) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// 点上层格 (每层各自可点; cap.node.id = 那一层的节点 id)
  Future<void> _onTapUplineCap(FranchiseeTreeNode tree, UplineCap cap) async {
    final up = _uplineByNodeId(tree, cap.node.id);
    if (up != null) {
      // 有人: 只给看信息 (上层不可撤换, 没有「换掉」按钮)
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppTheme.bgWarm,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.r20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '我的上层 · ${up.name}',
                  style: const TextStyle(
                    fontSize: AppTheme.fontLg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpace.s8),
                Text(
                  '我在她的${up.sideLabel} · 第${up.depth}层\n'
                  '上层一旦确定就不能撤换; 确需调整请联系系统管理员。',
                  style: const TextStyle(
                    fontSize: AppTheme.fontSm,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpace.s12),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.push('/franchisees/${up.id}');
                  },
                  child: const Text('查看她的加盟商详情'),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    if (tree.uplineRequest != null) {
      context.push('/franchisees/placement-requests');
      return;
    }
    await _showClaimUplineDialog();
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
        final isUnaffiliated =
            tree == null || tree.id == '0' || tree.name == '未加盟';
        // ★ 主人 2026-09-21 拍: 图谱在「我」上面永远留一格「上层点位」——
        //   刚被建根、还没有下线的加盟商也要能看到这一格 (那是往上发展的唯一入口),
        //   所以「我是加盟商但还没下线」不再拦成空状态 (只留「未加盟」这一种空状态)
        if (isUnaffiliated) {
          return const AppEmptyState(
            icon: Icons.account_tree_outlined,
            title: '还不是加盟商, 没有加盟网络',
            hint: '当前账号未关联加盟关系, 无法查看加盟图谱',
          );
        }
        // 预算搜索匹配数 (全树 O(n) 走一遍)
        final searchQuery = _search.trim();
        final matchCount = searchQuery.isEmpty
            ? 0
            : _countMatches(tree, searchQuery.toLowerCase());

        // 双主线「对碰」布局: 两条主线平行直下, 侧枝往外侧展开
        // ADR-0011: 层数不限 → 布局深度给足, 实际节点由懒加载合并进来
        // 上层点位链 (ADR-0015 Q13, 主人 2026-09-22 拍): 在「我」正上方留 N 格 (整树下移 N 层)
        final uplineCaps = _uplineCapsOf(tree);
        final layout = _layoutWithUpline(tree, uplineCaps);
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s8),
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
                          size: AppSize.iconMd,
                          color: searchQuery.isNotEmpty && matchCount == 0
                              ? AppTheme.danger
                              : AppTheme.primaryDark,
                        ),
                        const SizedBox(width: AppSpace.s8),
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
              padding: const EdgeInsets.fromLTRB(AppSpace.s16, 6, 16, 6),
              child: SegmentedButton<_GraphFilter>(
                segments: [
                  const ButtonSegment(
                    value: _GraphFilter.none,
                    label: Text('全部', style: TextStyle(fontSize: AppType.xs)),
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
            // 会员图例 + 计数 (主人 2026-09-21 拍): 「20 位加盟客户里 5 位是会员」
            //   只在真有会员时出现 —— 没会员不占地方 (大多数树一开始没会员)
            if (_memberCountInTree(tree) > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, 16, 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.s8, vertical: 3),
                      decoration: BoxDecoration(
                        color: kMemberGold.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(AppRadius.r10),
                        border: Border.all(
                            color: kMemberGold.withOpacity(0.55), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('👑', style: TextStyle(fontSize: AppType.xs)),
                          const SizedBox(width: AppSpace.s4),
                          Text(
                            '会员 ${_memberCountInTree(tree)} 位',
                            style: const TextStyle(
                              fontSize: AppTheme.fontXs,
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.s8),
                    const Expanded(
                      child: Text(
                        '金环 + 👑 = 会员',
                        style: TextStyle(
                          fontSize: AppTheme.fontXs,
                          color: AppTheme.textSecondary,
                        ),
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
                  final viewport = Size(
                    constraints.maxWidth,
                    constraints.maxHeight - _graphBottomControlsHeight,
                  );
                  final rootCenter = positions[tree.id] ??
                      Offset(canvasSize.width / 2,
                          TreeLayout.padding + TreeLayout.nodeRadius);
                  _graphViewport = viewport;
                  _graphRootCenter = rootCenter;
                  // 聚焦用: 最远那格的中心 (包含全部上层格 → 全部可见)
                  _graphUplineCapCenter = uplineCaps.isEmpty
                      ? null
                      : positions[uplineCaps.last.node.id];
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
                        _focusRootMatrix(viewport, canvasSize, rootCenter,
                            capCenter: _graphUplineCapCenter);
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
                                            uplineCaps: uplineCaps,
                                            uplineCapCenters: {
                                              for (final c in uplineCaps)
                                                if (positions[c.node.id] != null)
                                                  c.node.id:
                                                      positions[c.node.id]!,
                                            },
                                            scale: scale,
                                            columnPitch: layout.columnPitch,
                                            pendingPlacements:
                                                tree.pendingPlacements,
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
                                  // 待确认虚位也能点 (主人 2026-09-19: 点进「待我确认」页)
                                  ..._buildGhostHitareas(tree, positions,
                                      layout.columns, layout.aLineIds,
                                      layout.bLineIds, layout.columnPitch),
                                  // 上层格也能点 (主人 2026-09-21: 虚位 → 认领; 待确认 → 确认页)
                                  ..._buildUplineCapHitarea(tree, positions),
                                ],
                              ),
                            ),
                          ),
                          ),
                        ),
                      ),
                      // 右下角: 「回到我」(根节点居中 1:1) / 「全景」(整树 fit)
                      Positioned(
                        right: AppSpace.s12,
                        bottom: AppSpace.s12,
                        child: Row(
                          children: [
                            _graphControlButton(
                              icon: Icons.my_location,
                              label: '回到我',
                              onTap: _focusGraphView,
                            ),
                            const SizedBox(width: AppSpace.s8),
                            _graphControlButton(
                              icon: Icons.zoom_out_map,
                              label: '全景',
                              onTap: _fitGraphView,
                            ),
                            // 认领上级 (主人 2026-09-21 拍 B2): 只有**树根**才显示 ——
                            //   (上层格点「＋」也能进来, 这条是显式按钮, 老用户习惯)
                            //   非根用户上面已经有 app 内的上级, 往上发展该由那个根去做
                            //   (placementSide == null ⟺ 我这张图的根无侧别 = 我是树根)
                            if (tree.placementSide == null) ...[
                              const SizedBox(width: AppSpace.s8),
                              _graphControlButton(
                                icon: Icons.arrow_circle_up,
                                label: '认领上级',
                                onTap: _showClaimUplineDialog,
                              ),
                            ],
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

  /// 向上认领上级 (主人 2026-09-21 拍 B2) —— 「往根部发展」
  ///
  /// 场景 (主人原话): 客户公司 (如碧波庭) 现实里**早就有固有加盟体系**了, app 只是把
  ///   现公司的加盟树同步进来。admin 指定的初始用户**大概率只是公司体系里的中间层**
  ///   (比如第 10 层) → 她下面能长 (老的三方确认), 但**上面接不进来** (第 9 层那个上级)。
  ///
  /// 做法: 把我现实里的**直接上级 U** 接进 app → U 成为**新根**, 我这棵子树整体下降一层。
  ///
  /// 确认方 = **双方** (我 + U 本人): app 里根本没有"上上层"那个人, 也就没人能当老三方
  ///   —— 跟老规则"父节点 == 设置者 → 双方"是同一条 (U 就是我 app 里的邻接点)。
  ///   老的三方确认往下生长的方案**完全不变**。
  Future<void> _showClaimUplineDialog() async {
    // ★ P6 (ADR-0016 D1, 主人 2026-09-22 拍): 按**邀请码**找账号 (手机号不再作为识别依据)
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
          title: const Text('认领我的上级',
              style: TextStyle(fontSize: AppTheme.fontLg)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '公司现实里的加盟体系已经存在, app 只是把它同步进来。'
                  '这里把您的直接上级接进来: 她成为新的树根, 您这棵子树整体往下挪一层。\n\n'
                  '需要双方确认: 您 (自动记 1 票) + 上级本人 (要她先注册登录, '
                  '再到「加盟落位确认」里点同意)。\n\n'
                  '⚠ 您在她哪条线 (A线/B线) 不用您选 —— 由她本人在同意时决定。',
                  style: TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpace.s12),
                TextField(
                  controller: codeCtrl,
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: '上级的邀请码 *',
                    helperText: '6 位字母数字 —— 她的唯一识别码 (手机号不再作为识别依据)',
                  ),
                ),
                const SizedBox(height: AppSpace.s8),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                  decoration: const InputDecoration(
                    labelText: '称呼 (可选)',
                    helperText: '留空就用她账号里的真实姓名',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('提交确认', style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
          ],
      ),
    );
    final name = nameCtrl.text.trim();
    final code = codeCtrl.text.trim().toUpperCase();
    codeCtrl.dispose();
    nameCtrl.dispose();
    if (submitted != true) return;
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填上级的 6 位邀请码')),
      );
      return;
    }
    try {
      final req = await ref.read(franchiseeServiceProvider).claimUpline(
            newReferralCode: code,
            newName: name.isEmpty ? null : name,
          );
      if (!mounted) return;
      ref.invalidate(placementToConfirmCountProvider);
      final done = req.status == 'executed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            done
                ? '已认领: 「$name」成为新的树根 (管理员设置, 立即生效)'
                : '已提交: 认领「$name」为上级, 等她本人在「加盟落位确认」里同意'
                    ' (您在她哪条线由她定)',
            style: const TextStyle(fontSize: AppTheme.fontSm),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败: $e')),
      );
    }
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
        const Icon(Icons.account_tree_outlined, size: AppSize.iconMd, color: AppTheme.accent),
        const SizedBox(width: AppSpace.s8),
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
        // 落位「三方确认」(主人 2026-09-18 拍): 在这个点位的下级加新加盟商
        IconButton(
          icon: const Icon(Icons.person_add_alt_1, size: AppSize.iconMd),
          tooltip: '加下线到此点位',
          visualDensity: VisualDensity.compact,
          onPressed: () => _showAddDownlineDialog(node),
        ),
        // 懒加载 (ADR-0011): 有下级 + 未展开 → 「展开」; 展开了 → 「收起」
        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpace.s8),
            child: SizedBox(
              width: AppSpace.s16,
              height: AppSpace.s16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else if (canExpand)
          TextButton.icon(
            onPressed: () => _expandNode(node),
            icon: const Icon(Icons.unfold_more, size: AppSize.iconMd),
            label: const Text('展开下级', style: TextStyle(fontSize: AppType.xs)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          )
        else if (childrenLoaded && !_graphNoFold)
          TextButton.icon(
            onPressed: () => _collapseNode(node),
            icon: const Icon(Icons.unfold_less, size: AppSize.iconMd),
            label: const Text('收起', style: TextStyle(fontSize: AppType.xs)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        IconButton(
          icon: const Icon(Icons.close, size: AppSize.iconMd),
          tooltip: '取消选中',
          visualDensity: VisualDensity.compact,
          onPressed: _clearSelection,
        ),
      ],
    );
  }

  /// 落位「三方确认」: 在 node 的下级空位加新加盟商 (主人 2026-09-18 拍)
  ///
  /// 提交后**不立即生效**: 需要 设置者(我) + 新加盟商本人 + 新位置上级 三方确认
  /// (若上级 == 我 → 双方); 72h 未确认自动失效; 期间点位预占
  Future<void> _showAddDownlineDialog(FranchiseeTreeNode parent) async {
    // ★ P6 (ADR-0016 D1): 按**邀请码**找账号
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    var side = 'left';
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('加到「${parent.name}」的下级',
              style: const TextStyle(fontSize: AppTheme.fontLg)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '需要三方确认才生效: 我 (设置者) + 新加盟商本人 + 新位置的上级。'
                  '本人和上级要各自在自己 App 的「加盟落位确认」里点同意。',
                  style: TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpace.s12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'left', label: Text('A线')),
                    ButtonSegment(value: 'right', label: Text('B线')),
                  ],
                  selected: {side},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setDlg(() => side = v.first),
                ),
                const SizedBox(height: AppSpace.s12),
                TextField(
                  controller: codeCtrl,
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: '她的邀请码 *',
                    helperText: '6 位字母数字 —— 她的唯一识别码 (手机号不再作为识别依据)',
                  ),
                ),
                const SizedBox(height: AppSpace.s8),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                  decoration: const InputDecoration(
                    labelText: '称呼 (可选)',
                    helperText: '留空就用她账号里的真实姓名',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('提交确认', style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    final code = codeCtrl.text.trim().toUpperCase();
    codeCtrl.dispose();
    nameCtrl.dispose();
    if (submitted != true) return;
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填她的 6 位邀请码')),
      );
      return;
    }
    try {
      await ref.read(franchiseeServiceProvider).createPlacementRequest(
            targetParentId: parent.id,
            side: side,
            newReferralCode: code,
            newName: name.isEmpty ? null : name,
          );
      if (!mounted) return;
      ref.invalidate(placementToConfirmCountProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已提交, 等三方确认后生效', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败: $e')),
      );
    }
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
          width: AppSpace.s8,
          height: AppSpace.s8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: AppSpace.s4),
        Flexible(
          child: Text(
            '$text $count',
            style: const TextStyle(fontSize: AppType.xs),
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

  /// 树里的会员数 (只数下属, 不含「我」= 根节点; 与顶部「共 N 位」同口径)
  ///   口径 = 后端每个节点现算的 member (绑定账号是会员) → 充值/到期下次拉树即变
  int _memberCountInTree(FranchiseeTreeNode tree) {
    var n = 0;
    void walk(FranchiseeTreeNode node, {required bool isRoot}) {
      if (!isRoot && node.member) n++;
      for (final c in node.children) {
        walk(c, isRoot: false);
      }
    }

    walk(tree, isRoot: true);
    return n;
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
  /// 上沿对齐谁: 有上层格 → 对齐上层格 (否则它会伸出屏幕外被裁掉), 没有 → 对齐我
  Matrix4 _focusRootMatrix(
    Size viewport,
    Size canvasSize,
    Offset rootCenter, {
    Offset? capCenter,
  }) {
    // 有上层格 → 上沿多留一圈 (名字画在虚位圆上方, 不留就被顶出屏幕)
    final topMargin =
        capCenter == null ? 20.0 : 20.0 + TreeLayout.nodeRadius + 26;
    final contentHeight = _graphContentHeight ?? canvasSize.height;
    final fit = (viewport.height - topMargin - 8) / contentHeight;
    // 0.5 下限: 再小就没法读了; 1.0 上限: 不放大超过 1:1
    final scale = math.min(1.0, math.max(0.5, fit));
    final anchor = capCenter ?? rootCenter;
    final dx = viewport.width / 2 - rootCenter.dx * scale;
    final dy = topMargin - (anchor.dy - TreeLayout.nodeRadius) * scale;
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
        _layoutWithUpline(tree, _uplineCapsOf(tree)).positions[hit.id];
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
          _focusRootMatrix(viewport, canvasSize, rootCenter,
              capCenter: _graphUplineCapCenter);
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
        borderRadius: BorderRadius.circular(AppRadius.r20),
        side: BorderSide(color: AppTheme.primary.withOpacity(0.4), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.r20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppSize.iconSm, color: AppTheme.primaryDark),
              const SizedBox(width: AppSpace.s4),
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

  /// 待确认虚位的点击区 (主人 2026-09-19 拍: 点虚位 → 「待我确认」页)
  ///   位置公式与 painter 共用 FranchiseTreePainter.pendingGhostCenter
  ///   放在节点点击区**之后** → 真节点优先, 虚位只占空位
  List<Widget> _buildGhostHitareas(
    FranchiseeTreeNode root,
    Map<String, Offset> positions,
    Map<String, int> columns,
    Set<String> aLineIds,
    Set<String> bLineIds,
    double columnPitch,
  ) {
    final widgets = <Widget>[];
    for (final p in root.pendingPlacements) {
      final parentPos = positions[p.targetParentFid];
      if (parentPos == null) continue;
      final isA = aLineIds.contains(p.targetParentFid);
      final isB = bLineIds.contains(p.targetParentFid);
      final parentCol = columns[p.targetParentFid] ?? 0;
      final center = FranchiseTreePainter.pendingGhostCenter(
        parentPos: parentPos,
        parentIsA: isA,
        parentIsB: isB,
        parentCol: parentCol,
        columnPitch: columnPitch,
        targetSide: p.targetSide,
      );
      final continuing = isA ? 'left' : 'right';
      final radius = TreeLayout.radiusForColumn(
          p.targetSide == continuing ? parentCol : parentCol + 1);
      // 圆 + 下方「⏳ 名字」都算可点 (中老年手指粗)
      final w = (radius * 2).clamp(88.0, 200.0);
      final h = radius * 2 + 52;
      widgets.add(
        Positioned(
          left: center.dx - w / 2,
          top: center.dy - radius,
          width: w,
          height: h,
          child: Semantics(
            button: true,
            label: '待确认虚位 ${p.label}, 点击查看待我确认',
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                context.push('/franchisees/placement-requests');
              },
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );
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
      style: const TextStyle(fontSize: AppType.xs),
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