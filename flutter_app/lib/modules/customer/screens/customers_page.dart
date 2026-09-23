// ============================================
// 暖客宝 客户页 (Plan F2 极简版)
// 单文件 3 widget: 列表 + 详情 + 表单
// 中老年易用: 字号 18pt+ / 按钮 64pt+ / FAB 80pt / 行高 80pt
// ============================================

import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/customer.dart';
import '../../../core/models/follow_up_info.dart';
// fix-graph-zoom-pan (2026-09-16): auto-fit initial scale, user can see whole tree on open
import 'dart:math' as math;
import '../../../core/models/franchisee.dart';
import '../../../core/services/api.dart' show ReferralLookup;
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/member_avatar.dart';
import '../../../core/widgets/big_button.dart';
import '../../../core/widgets/big_fab.dart';
import '../widgets/ai_insight_cards.dart';
import '../widgets/customer_activity_cards.dart';
import '../widgets/customer_row.dart';
import '../../follow_up/widgets/follow_up_analysis_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/franchise_chip.dart';
import '../../../core/utils/birthday.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../screens/profile_sheets.dart' show showAvatarPickerSheet;
import '../../presentation/graph/widgets/franchise_tree_painter.dart';
import 'add_record_sheet.dart';
import '../../../core/models/placement_request.dart';
import '../../../core/widgets/placement_target_sheet.dart';

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
        toolbarHeight: 64,
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
                  child: const Icon(Icons.fact_check_outlined, size: 26),
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
          ? BigFab(
              onPressed: () => context.push('/customers/new'),
              tooltip: '添加客户',
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
            Icon(collapsed ? Icons.expand_more : Icons.expand_less, size: 20, color: AppTheme.textSecondary),
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
              display.add(_GroupHeaderData(
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
              if (item is _GroupHeaderData) {
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
                const SizedBox(height: AppSpace.s16),
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
          return const EmptyState(
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
                          size: 20,
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
        const Icon(Icons.account_tree_outlined, size: 20, color: AppTheme.accent),
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
          icon: const Icon(Icons.person_add_alt_1, size: 22),
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
            icon: const Icon(Icons.unfold_more, size: 20),
            label: const Text('展开下级', style: TextStyle(fontSize: AppType.xs)),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          )
        else if (childrenLoaded && !_graphNoFold)
          TextButton.icon(
            onPressed: () => _collapseNode(node),
            icon: const Icon(Icons.unfold_less, size: 20),
            label: const Text('收起', style: TextStyle(fontSize: AppType.xs)),
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
              Icon(icon, size: 18, color: AppTheme.primaryDark),
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
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 8, 16, 80),
      children: [
        // 1) 大头像 + 基本信息 (类型徽章 / 年龄 / 拨号)
        _buildHeader(context, ref, customer),
        const SizedBox(height: AppSpace.s12),

        // 1.5) 客户类型切换 (主人 2026-09-18: 「没找到修改客户类型的入口」→ 详情页直接给开关)
        _buildTypeCard(context, ref, customer),
        const SizedBox(height: AppSpace.s12),

        // 1.6) app 身份 (ADR-0016 主人 2026-09-22): 已注册 / 未注册 + 填邀请码绑定
        _buildIdentityCard(context, ref, customer),
        const SizedBox(height: AppSpace.s12),

        // 2) 被动养生记录 (含汇总: 共 N 次 / 最近到店)
        _buildWellnessSection(context, asyncRecords),
        const SizedBox(height: AppSpace.s12),

        // 2.5) 跟进分析 (客观指标; 主人 2026-09-20 拍 P1 §7.1) —— 先事实, 再 AI 解读
        FollowUpAnalysisCard(customerId: customerId),
        const SizedBox(height: AppSpace.s12),

        // 3) AI 智能区 (主人 2026-09-18 拍: 复购预测 / 客户画像 / 跟进建议 / 效果分析)
        //    顺序按「销售员每天最用得上」排: 复购预测 (自动算, 不烧额度) →
        //    跟进建议 (开口话术) → 客户画像 (这人是谁) → 效果分析 (疗程有没有用)
        _buildSectionTitle('AI 助手'),
        RepurchaseCard(customerId: customerId),
        AiFollowUpCard(customerId: customerId),
        AiProfileCard(customerId: customerId),
        EffectAnalysisCard(customerId: customerId),
        const SizedBox(height: AppSpace.s4),

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
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.favorite, size: 26, color: AppTheme.accent),
                const SizedBox(width: AppSpace.s8),
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
            const SizedBox(height: AppSpace.s12),
            asyncRecords.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpace.s8),
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
            const SizedBox(height: AppSpace.s8),
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
          padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, 16, 24),
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
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          children: [
            // 头像 + 右下角相机角标 (主人 2026-09-18 拍: 点它设置客户头像)
            GestureDetector(
              onTap: () => _pickCustomerAvatar(context, ref, c),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(
                    avatarUrl: c.avatar,
                    name: c.name,
                    size: AppTheme.avatarLg,
                  ),
                  // 相机角标 (64pt 头像右下角, 触摸区 32pt 对中老年友好)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: AppSpace.s32,
                      height: AppSpace.s32,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: AppSpace.s2),
                      ),
                      child: const Icon(Icons.photo_camera,
                          size: 18, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.s6),
            const Text(
              '点头像可以换 (拍照 / 相册 / 现成头像)',
              style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppSpace.s6),
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
                const SizedBox(width: AppSpace.s8),
                // 类型徽章 (加盟紫 / 种子橙 / 普通绿) —— 跟客户列表同口径
                FranchiseChip(type: type),
              ],
            ),
            const SizedBox(height: AppSpace.s6),
            Text(
              _maskPhone(c.phone),
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                color: AppTheme.textSecondary,
              ),
            ),
            if (c.gender != null || age != null) ...[
              const SizedBox(height: AppSpace.s8),
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
            const SizedBox(height: AppSpace.s12),
            // 快捷操作: 打电话 / 记一次互动 (拨号在 web 不支持时静默失败)
            Row(
              children: [
                Expanded(
                  child: BigActionButton(
                    icon: Icons.phone,
                    label: '打电话',
                    compact: true,
                    onTap: () => _callCustomer(context, ref, c.phone),
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
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
              const SizedBox(height: AppSpace.s10),
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
                final nextSolar = info?.nextSolarDate;
                final nextSolarText = nextSolar == null
                    ? ''
                    : ' · 下次 ${nextSolar.year}-${nextSolar.month.toString().padLeft(2, '0')}-${nextSolar.day.toString().padLeft(2, '0')}';
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s10),
                  decoration: BoxDecoration(
                    color: due
                        ? AppTheme.accent.withOpacity(0.18)
                        : AppTheme.bgWarm,
                    borderRadius: BorderRadius.circular(AppRadius.r10),
                    border: Border.all(
                      color: due ? AppTheme.accent : AppColors.divider,
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
                          const SizedBox(width: AppSpace.s6),
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
                      const SizedBox(height: AppSpace.s4),
                      Text(
                        '提醒: ${remindLabel(c.birthdayRemindDays)}$nextSolarText',
                        style: const TextStyle(
                            fontSize: AppTheme.fontXs,
                            color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                );
              }),
            ] else if (c.birthYear != null) ...[
              const SizedBox(height: AppSpace.s10),
              Text(
                '生日未填 (只知道年份 ${c.birthYear}) · 填上月日可开启生日提醒',
                style: const TextStyle(
                    fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
              ),
            ],
            if (c.diseaseHistory != null && c.diseaseHistory!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s12),
              Container(
                padding: const EdgeInsets.all(AppSpace.s12),
                decoration: BoxDecoration(
                  color: AppColors.dangerSurface,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
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
              const SizedBox(height: AppSpace.s8),
              Container(
                padding: const EdgeInsets.all(AppSpace.s12),
                decoration: BoxDecoration(
                  color: AppColors.accentSurfaceWarm,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 20, color: AppTheme.accent),
                    const SizedBox(width: AppSpace.s6),
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
              const SizedBox(height: AppSpace.s12),
              _buildHealthTags(c),
            ],
          ],
        ),
      ),
    );
  }

  /// 换客户头像 (主人 2026-09-18 拍)
  ///   复用「我的」页那套 sheet: 候选头像 (8 个养生图标) + 拍照 + 相册 + 恢复默认;
  ///   区别只是保存动作 = PATCH /api/customers/:id 的 avatar 字段
  Future<void> _pickCustomerAvatar(
    BuildContext context,
    WidgetRef ref,
    Customer c,
  ) async {
    final changed = await showAvatarPickerSheet(
      context,
      ref,
      currentAvatarUrl: c.avatar,
      name: c.name,
      title: '给「${c.name}」设头像',
      subtitle: '拍照 / 相册上传, 或挑一个现成的 (不想用真人照片就选花草茶禅)',
      onApply: (value) async {
        await ref
            .read(customerServiceProvider)
            .update(c.id, {'avatar': value});
        ref.invalidate(customerDetailProvider(c.id));
        // 列表里的小头像也跟着刷新
        ref.invalidate(customersProvider);
      },
    );
    if (changed && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像已更新')),
      );
    }
  }

  /// 拨号 (tel:) — web 不支持时给提示, 不崩
  Future<void> _callCustomer(
      BuildContext context, WidgetRef ref, String phone) async {
    ref.read(usageServiceProvider).track('customer_call');
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
            left: AppSpace.s16,
            right: AppSpace.s16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('记一次互动',
                  style: TextStyle(
                      fontSize: AppTheme.fontLg, fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.s12),
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
              const SizedBox(height: AppSpace.s12),
              TextField(
                controller: summaryCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                    labelText: '聊了什么 (可选)', hintText: '例: 说腰疼好多了, 约下周三'),
              ),
              const SizedBox(height: AppSpace.s16),
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
              const SizedBox(height: AppSpace.s8),
            ],
          ),
        ),
      ),
    );
  }

  /// 客户类型卡 (普通 ↔ 种子 一键切换; 加盟类型由关系决定不可切)
  /// app 身份卡 (ADR-0016, 主人 2026-09-22 拍):
  ///   「客户列表中的客户有一些也是 app 用户, 有一些没有注册 app 账号」
  ///   → 详情页给出状态; 没绑定的可以**填她的邀请码 (身份识别码)** 绑定 —— 手机号对不上也能绑
  Widget _buildIdentityCard(BuildContext context, WidgetRef ref, Customer c) {
    final bound = c.hasAccount;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  bound ? Icons.verified_user : Icons.person_add_alt_1_outlined,
                  size: 20,
                  color: bound ? AppTheme.primaryDark : AppTheme.textSecondary,
                ),
                const SizedBox(width: AppSpace.s6),
                const Text(
                  'app 身份',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: AppSpace.s4),
                  decoration: BoxDecoration(
                    color: bound ? AppTheme.primaryLight : AppTheme.bgWarm,
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                  ),
                  child: Text(
                    bound ? '已注册' : '未注册',
                    style: TextStyle(
                      // ⚠ 必须显式给 color (AGENTS §5: 不给 = 真机白字)
                      color: bound ? AppTheme.primaryDark : AppTheme.textSecondary,
                      fontSize: AppTheme.fontXs,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            Text(
              bound
                  ? '她已经是 app 用户 —— 可以在 app 内直接邀请她 (沙龙 / 活动)'
                  : '还不是 app 用户。她注册 app 后, 把她的 6 位**邀请码**填进来即可绑定身份'
                      ' (手机号对不上也能绑; 若系统已按她的号自动建了空档案, 会自动并入这条)',
              style: const TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            if (!bound) ...[
              const SizedBox(height: AppSpace.s12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => _showBindAccountDialog(context, ref, c),
                  icon: const Icon(Icons.qr_code_2, size: 20),
                  label: const Text(
                    '填邀请码绑定身份',
                    style: TextStyle(fontSize: AppTheme.fontSm),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 绑定弹层: 填她的 6 位邀请码 (身份识别码)
  Future<void> _showBindAccountDialog(
    BuildContext context,
    WidgetRef ref,
    Customer c,
  ) async {
    final codeCtrl = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('绑定 app 身份', style: TextStyle(fontSize: AppTheme.fontLg)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '让「${c.name}」打开 app → 我的 → 我的邀请码, 把 6 位码填到这里。',
              style: const TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            TextField(
              controller: codeCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '她的邀请码 *',
                helperText: '6 位字母数字 (不区分大小写)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('绑定', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
    final code = codeCtrl.text.trim().toUpperCase();
    codeCtrl.dispose();
    if (submitted != true || !context.mounted) return;
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填对方的 6 位邀请码')),
      );
      return;
    }
    try {
      final res = await ref.read(customerServiceProvider).bindAccount(c.id, code);
      ref.invalidate(customerDetailProvider(c.id));
      ref.invalidate(customersProvider);
      ref.invalidate(customerTypeCountsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message.isEmpty ? '已绑定' : res.message)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('绑定失败: ${_apiErrorText(e)}')),
      );
    }
  }

  /// 从 dio 异常里取服务端人话错误 (AGENTS: 不要只显示 DioException)
  String _apiErrorText(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
    }
    return e.toString();
  }

  Widget _buildTypeCard(BuildContext context, WidgetRef ref, Customer c) {
    final isFranchisee = c.customerType == 'franchisee';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_outlined,
                    size: 20, color: AppTheme.primaryDark),
                const SizedBox(width: AppSpace.s6),
                const Text(
                  '客户类型',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                FranchiseChip(type: c.customerType),
              ],
            ),
            const SizedBox(height: AppSpace.s10),
            if (isFranchisee)
              const Text(
                '加盟客户：类型由加盟关系决定，不能在这里切换；\n要退出加盟请到加盟商详情页走「解除加盟」(需三方确认)',
                style: TextStyle(
                  fontSize: AppTheme.fontXs,
                  color: AppTheme.textSecondary,
                ),
              )
            else ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'normal', label: Text('普通')),
                  ButtonSegment(value: 'seed', label: Text('🌱 种子')),
                ],
                selected: {c.isSeed ? 'seed' : 'normal'},
                showSelectedIcon: false,
                onSelectionChanged: (v) =>
                    _setCustomerSeed(context, ref, c, v.first == 'seed'),
              ),
              const SizedBox(height: AppSpace.s6),
              const Text(
                '种子 = 还没体验过 / 刚加好友的潜在客户；选「种子」后可用列表顶部「🌱 种子」筛出来',
                style: TextStyle(
                  fontSize: AppTheme.fontXs,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Divider(height: AppSpace.s20),
              const Text(
                '要变成加盟商？走加盟落位（需三方确认）',
                style: TextStyle(
                  fontSize: AppTheme.fontXs,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpace.s8),
              // 发展客户为加盟商 (主人 2026-09-19: 入口迁到「客户类型」区块里)
              //   走三方确认的落位流程 (我 + 客户本人 + 目标上级), 通过后自动成为加盟商
              FilledButton.icon(
                onPressed: () =>
                    _promoteCustomerToFranchisee(context, ref, c),
                icon: const Icon(Icons.person_add_alt_1, size: 24),
                label: const Text(
                  '发展为加盟商',
                  style: TextStyle(fontSize: AppTheme.fontMd),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHealthTags(Customer c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s12),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.25),
        borderRadius: BorderRadius.circular(AppRadius.r10),
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
          const SizedBox(height: AppSpace.s8),
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
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s12),
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
      padding: const EdgeInsets.all(AppSpace.s24),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.history, size: 56, color: AppTheme.textSecondary),
            const SizedBox(height: AppSpace.s8),
            Text(title, style: const TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: AppSpace.s4),
            Text(hint, style: const TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordTile(BuildContext context, dynamic r) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.s8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s12),
        leading: Container(
          width: AppSpace.s48,
          height: AppSpace.s48,
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(AppRadius.r24),
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
          padding: const EdgeInsets.only(top: AppSpace.s4),
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

  /// 推荐码识别 (只新建时显示; ADR-0015 Q10/Q12):
  ///   推荐码 = 身份识别码 → 填已注册朋友的码 = 把**她**加为客户 (不新建重复档案)
  final _refCodeController = TextEditingController();
  ReferralLookup? _lookup;
  bool _lookupLoading = false;

  /// 「识别到可加的人」→ 保存走 claim, 不走 create
  bool get _claimMode => widget.customerId == null && _lookup?.canClaim == true;
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
      _isSeed = c.isSeed;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _refCodeController.dispose();
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
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8),
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

  /// 按推荐码识别已注册用户 (ADR-0015 Q10)
  /// 后端: 登录 + 限流 10/分 + 审计; 只返回姓名/打码手机号/会员/归属状态
  Future<void> _lookupCode() async {
    final code = _refCodeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入推荐码')),
      );
      return;
    }
    setState(() => _lookupLoading = true);
    try {
      final r = await ref.read(billingServiceProvider).lookupReferralCode(code);
      if (!mounted) return;
      setState(() {
        _lookup = r;
        // 识别到可加的人 → 预填真实姓名 (手机号拿不到明文, 用打码显示)
        if (r.canClaim) _nameController.text = r.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('识别失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _lookupLoading = false);
    }
  }

  /// 识别结果提示框 (可加 = 暖色提示; 不可加 = 警示色)
  Widget _lookupHint(ReferralLookup r) {
    if (!r.found) {
      return _hintBox('没找到这个推荐码, 请核对后重试', warn: true);
    }
    if (r.canClaim) {
      final member = r.isMember ? ' · 会员' : '';
      return _hintBox(
        '已识别: ${r.name}${r.phoneMasked.isEmpty ? '' : ' (${r.phoneMasked})'}$member\n'
        '保存后把她加为你的客户 (不新建重复档案, 之后可继续编辑资料)',
      );
    }
    return _hintBox('已识别: ${r.name} — ${r.claimLabel}', warn: true);
  }

  Widget _hintBox(String text, {bool warn = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: warn ? AppTheme.bgWarm : AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.r10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTheme.fontXs,
          height: 1.5,
          color: warn ? AppTheme.textSecondary : AppTheme.primaryDark,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      // 新建 + 填了推荐码但还没点「识别」→ 先识别 (直接保存也兜得住)
      if (widget.customerId == null &&
          _refCodeController.text.trim().isNotEmpty &&
          _lookup == null) {
        await _lookupCode();
        if (_lookup == null) return; // 识别失败已提示
      }
      final lookup = _lookup;
      if (lookup != null) {
        if (!lookup.found) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('推荐码不存在, 请核对后重试')),
          );
          return;
        }
        if (!lookup.canClaim) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(lookup.claimLabel)),
          );
          return;
        }
        // 识别到 → 归属声明 (ADR-0015 Q15 先到先得; 409 会被后端拦下)
        await ref.read(customerServiceProvider).claim(lookup.customerId!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已把 ${lookup.name} 加为我的客户')),
        );
        ref.invalidate(customersProvider);
        ref.invalidate(customerTypeCountsProvider);
        context.pop();
        return;
      }
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
        // 种子客户开关 (后端算进 customerType: 加盟 > 种子 > 普通)
        'isSeed': _isSeed,
      };
      if (widget.customerId != null) {
        await ref.read(customerServiceProvider).update(widget.customerId!, data);
        ref.read(usageServiceProvider).track('customer_edit');
      } else {
        await ref.read(customerServiceProvider).create(data);
        ref.read(usageServiceProvider).track('customer_create', props: {'source': 'form'});
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
          padding: const EdgeInsets.all(AppSpace.s16),
          children: [
            // 推荐码识别 (只新建时; ADR-0015 Q10): 填已注册朋友的码 → 把她加为客户
            if (widget.customerId == null) ...[
              TextFormField(
                controller: _refCodeController,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) {
                  // 码改了 → 之前的识别结果作废 (避免拿旧结果去 claim)
                  if (_lookup != null &&
                      v.trim().toUpperCase() != _lookup!.code) {
                    setState(() => _lookup = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: '推荐码 (可选)',
                  hintText: '6 位字母数字',
                  helperText: '朋友的推荐码: 填了可把已注册的她加为客户',
                  suffixIcon: _lookupLoading
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpace.s12),
                          child: SizedBox(
                            width: AppSpace.s18,
                            height: AppSpace.s18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : TextButton(
                          onPressed: _loading ? null : _lookupCode,
                          child: const Text('识别',
                              style: TextStyle(fontSize: AppTheme.fontSm)),
                        ),
                ),
              ),
              if (_lookup != null) ...[
                const SizedBox(height: AppSpace.s8),
                _lookupHint(_lookup!),
              ],
              const SizedBox(height: AppSpace.s16),
            ],
            TextFormField(
              controller: _nameController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              readOnly: _claimMode, // 已注册用户用她的真实姓名 (claim 不改档案)
              decoration: InputDecoration(
                labelText: '姓名 *',
                helperText: _claimMode ? '用对方账号的真实姓名 (不能改)' : null,
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
            ),
            const SizedBox(height: AppSpace.s16),
            // 已注册用户: 手机号在对方账号里, 不需要录 (档案已存在)
            if (!_claimMode) ...[
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
              const SizedBox(height: AppSpace.s16),
            ],
            // 性别 (大按钮组)
            const Text('性别', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: AppSpace.s8),
            Row(
              children: [
                _genderButton('女', 'F'),
                const SizedBox(width: AppSpace.s8),
                _genderButton('男', 'M'),
                const SizedBox(width: AppSpace.s8),
                _genderButton('未知', 'U'),
              ],
            ),
            const SizedBox(height: AppSpace.s16),
            // ===== 生日 (主人 2026-09-18: 年月日可选填 + 农历/阳历 + 生日提醒) =====
            const Text('生日', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: AppSpace.s4),
            const Text(
              '知道多少填多少, 不知道的留空 (例: 只记得属相/年份 → 只填年; 过农历生日 → 切「农历」)',
              style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppSpace.s8),
            Row(
              children: [
                Expanded(
                  child: _birthPickerButton(
                    label: '年',
                    value: _birthYear == null ? null : '${_birthYear!.year}',
                    onPick: _pickBirthYear,
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: _birthPickerButton(
                    label: '月',
                    value: _birthMonth == null ? null : '$_birthMonth',
                    onPick: () => _pickBirthPart(isMonth: true),
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: _birthPickerButton(
                    label: '日',
                    value: _birthDay == null ? null : '$_birthDay',
                    onPick: () => _pickBirthPart(isMonth: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            // 历法 (阳历 / 农历)
            Row(
              children: [
                const Text('历法:', style: TextStyle(fontSize: AppTheme.fontSm)),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'solar', label: Text('阳历', style: TextStyle(fontSize: AppType.xs))),
                      ButtonSegment(value: 'lunar', label: Text('农历', style: TextStyle(fontSize: AppType.xs))),
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
              const SizedBox(height: AppSpace.s12),
              Container(
                padding: const EdgeInsets.all(AppSpace.s12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(AppRadius.r10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.notifications_active_outlined,
                            size: 20, color: AppTheme.accent),
                        SizedBox(width: AppSpace.s6),
                        Text('生日提醒 (已开启)',
                            style: TextStyle(
                                fontSize: AppTheme.fontSm,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: AppSpace.s8),
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
            const SizedBox(height: AppSpace.s16),
            // ===== 健康标签 (默认候选 + 自定义, 单个 ≤6 汉字; 主人 2026-09-18) =====
            const Text('健康标签', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: AppSpace.s4),
            const Text(
              '点一下选中/取消; 也可以自己加 (最多 6 个字)',
              style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppSpace.s8),
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
            const SizedBox(height: AppSpace.s8),
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
                const SizedBox(width: AppSpace.s8),
                // 定宽: 主题里 OutlinedButton minimumSize = infinity, 在 Row 里会被量成无限宽
                SizedBox(
                  width: AppSpace.s88,
                  height: AppSpace.s48,
                  child: OutlinedButton.icon(
                    onPressed: _addCustomTag,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('添加', style: TextStyle(fontSize: AppTheme.fontSm)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s16),
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
            const SizedBox(height: AppSpace.s12),
            TextField(
              controller: _allergyController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '过敏史',
                hintText: '例: 青霉素过敏 / 对薰衣草精油过敏 / 皮肤敏感',
              ),
            ),
            const SizedBox(height: AppSpace.s16),
            // 种子客户开关 (潜在客户, 胶囊筛选「种子」命中这里)
            Container(
              decoration: BoxDecoration(
                color: _isSeed ? AppTheme.accent.withOpacity(0.12) : Colors.white,
                border: Border.all(
                  color: _isSeed ? AppTheme.accent : AppColors.border,
                  width: _isSeed ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(AppRadius.r12),
              ),
              child: SwitchListTile(
                value: _isSeed,
                onChanged: (v) => setState(() => _isSeed = v),
                activeColor: AppTheme.accent,
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s8),
                title: const Text('🌱 种子客户', style: TextStyle(fontSize: AppTheme.fontMd)),
                subtitle: const Text(
                  '还没体验过/刚加好友的潜在客户。勾上后客户列表可用「种子」筛出',
                  style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s16),
            TextFormField(
              controller: _notesController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            const SizedBox(height: AppSpace.s32),
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
            width: AppSpace.s2,
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: AppTheme.fontMd)),
      ),
    );
  }

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
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpace.s8),
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

/// 客户类型切换: 普通 ↔ 种子 (主人 2026-09-18: 详情页直接切, 不用进编辑表单)
Future<void> _setCustomerSeed(
  BuildContext context,
  WidgetRef ref,
  Customer c,
  bool seed,
) async {
  if (c.isSeed == seed) return;
  try {
    await ref.read(customerServiceProvider).update(c.id, {'isSeed': seed});
    ref.invalidate(customerDetailProvider(c.id));
    ref.invalidate(customersProvider);
    ref.invalidate(customerTypeCountsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          seed ? '已标记为 🌱 种子客户' : '已改为普通客户',
          style: const TextStyle(fontSize: AppTheme.fontMd),
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('修改失败: $e')),
    );
  }
}

Future<void> _promoteCustomerToFranchisee(
BuildContext context,
WidgetRef ref,
Customer c,
) async {
  if (c.phone.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这位客户没手机号, 先补手机号再发展为加盟商')),
    );
    return;
  }
  FranchiseeTreeNode tree;
  try {
    tree = await ref
        .read(franchiseeServiceProvider)
        .getMyTree(depth: 12, mode: 'placement');
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('读取我的图谱失败: $e')),
    );
    return;
  }
  if (!context.mounted) return;
  final target = await showModalBottomSheet<PlacementTarget>(
    context: context,
    isScrollControlled: true,
    builder: (_) => PlacementTargetSheet(
      tree: tree,
      title: '发展「${c.name}」为加盟商',
    ),
  );
  if (target == null || !context.mounted) return;

  // ★ P6 (ADR-0016 D1, 主人 2026-09-22 拍): 落位按**邀请码**找账号 —— 先问她本人要码
  //   (她必须已注册 app; 没注册就让她先注册, 再回来发展)
  final codeCtrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('发展「${c.name}」为加盟商',
          style: const TextStyle(fontSize: AppTheme.fontLg)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '节点必须对应一个已注册账号 (她的邀请码 = 唯一识别码)。\n'
            '还没注册? 先请她注册, 再回来发展。',
            style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppSpace.s12),
          TextField(
            controller: codeCtrl,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: '她的邀请码 *',
              helperText: '6 位字母数字',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
        FilledButton(
          onPressed: () {
            final v = codeCtrl.text.trim().toUpperCase();
            Navigator.of(ctx).pop(RegExp(r'^[A-Z0-9]{6}$').hasMatch(v) ? v : null);
          },
          child: const Text('提交', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      ],
    ),
  );
  codeCtrl.dispose();
  if (code == null || !context.mounted) return;

  try {
    final req = await ref
        .read(franchiseeServiceProvider)
        .createPlacementRequest(
          targetParentId: target.parentId,
          side: target.side,
          newReferralCode: code,
          newName: c.name,
        );
    if (!context.mounted) return;
    ref.invalidate(placementToConfirmCountProvider);
    // 主人 2026-09-19: 系统管理员设置加盟免多方确认 → 直接生效
    final done = req.status == 'executed';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? '已落位: 加到「${target.parentName}」的${PlacementRequest.sideLabel(target.side)} · 管理员设置, 立即生效'
              : '已提交: 加到「${target.parentName}」的${PlacementRequest.sideLabel(target.side)} · 等三方确认后生效',
          style: const TextStyle(fontSize: AppTheme.fontSm),
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('提交失败: $e')),
    );
  }
}

/// 分组表头数据 (列表渲染用的小载体)
class _GroupHeaderData {
  final String level;
  final String label;
  final int count;
  const _GroupHeaderData({required this.level, required this.label, required this.count});
}
