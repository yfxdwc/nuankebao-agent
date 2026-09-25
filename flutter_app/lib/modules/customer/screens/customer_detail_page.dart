// ============================================
// 暖客宝 客户详情页 (B1 客户域换装, 2026-09-24)
//
// 本文件从 customers_page.dart 拆出 (2026-09-24).
// 设计依据 (docs/ui-principles.md):
//   - 原则 1: 密度 = 尊重用户时间 (行高 60, 关键信息紧凑)
//   - 原则 4: 容器越少内容越强 (原则: 一屏有边框/阴影的元素 ≤ 2)
//   - 原则 5: 颜色是信号, 不是装饰 (状态色只在有状态时出现)
//
// 详情页结构 (P2 2026-09-23 + 2026-09-24 三次拍板):
//   TabBar: 记录 / 分析 / 管理
//   记录 Tab 顶部: CustomerInsightActions (「现在该做」) + CustomerFollowUpSection
//     (两张固定卡; 上滑各自收起, 见各自注释)
//   分析 Tab 顶部: CustomerScoreCard (评分环 + 三维度条 + 展开明细)
//   ⚠ 「现在该做」2026-09-24 起**只在记录 Tab** (主人拍板) —— 之前挂 TabBarView
//     外面"切 Tab 也可见", 现改为记录 Tab 内; 分析/管理 Tab 保持干净。
//
// 2026-09-24 收尾: 评分卡从 L0 搬到分析 Tab (主人拍: 「三个 Tab 都有评分环 = 反 vibe,
//   评分是参考, 行动才是产出, 应该分析才需要看评分」)。
//   行动卡**保留在 L0** (CHARTER §1.4 拍板: 行动输出 = 明确的跟进指引必须切 Tab 可见,
//   不能因为这次诉求把"现在该做"也一起移走 —— 同根 §5「贴告示 ≠ 修复」:
//   看起来优化了, 实则把既有拍板撤了)。
//
// 2026-09-24 接 P1 闭环反馈: 「建任务」后用户看不到建哪了、不知道去哪看。
//   修法 = 本页从 ConsumerWidget → ConsumerStatefulWidget + 自管 TabController:
//   - SnackBar 加「查看任务」action, 点了切回记录 Tab 并把「跟进任务」区滚进视口
//   - 同时补 invalidate(customerFollowUpTasksProvider) 让列表立刻刷新
//     (对照 customer_activity_cards.dart::showAddFollowUpSheet, 原本漏了)
//   自管 TabController 之前用 DefaultTabController, 但 SnackBar action 触发后
//   要调 animateTo + Scrollable.ensureVisible, 没有 controller 句柄做不到。
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/customer.dart';
import '../../../core/models/customer_insight.dart';
import '../../../core/models/customer_ownership.dart';
import '../../../core/models/franchisee.dart';
import '../../../core/models/placement_request.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/utils/birthday.dart';
import '../../../core/widgets/app_empty.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/franchise_chip.dart';
import '../../../core/widgets/placement_target_sheet.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../screens/profile_sheets.dart' show showAvatarPickerSheet;
import '../../follow_up/widgets/complete_follow_up_sheet.dart' show showAddInteractionSheet;
import '../widgets/ai_insight_cards.dart';
import '../widgets/customer_activity_cards.dart';
import '../widgets/customer_analysis_charts.dart';
import '../widgets/customer_insight_actions.dart';
import '../widgets/customer_rhythm_card.dart';
import '../widgets/customer_score_card.dart';
import '../widgets/customer_timeline_section.dart';
import '../../../core/widgets/app_section.dart';
import '../widgets/audit_trail_card.dart';
import '../widgets/customer_health_card.dart';
import '../widgets/danger_zone_card.dart';
import '../widgets/ownership_card.dart';
import '../../../core/widgets/b2_no_chrome.dart';

// ============================================
// CustomerDetailPage (详情 + 3 Tab)
// ============================================

class CustomerDetailPage extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerDetailPage({super.key, required this.customerId});

  @override
  ConsumerState<CustomerDetailPage> createState() => CustomerDetailPageState();
}

/// 公开 State 类名 (= ConsumerState<CustomerDetailPage>)
///   · 给 widget test 用: `tester.state<CustomerDetailPageState>(...)` 直接拿 controller
///   · 也方便外部拿 BuildContext 更细 (e.g. 滚动协调)
///   · 类名公开是 Flutter 常规习惯 (名字带下划线是 dart-private, 同 library 外不可见)
class CustomerDetailPageState extends ConsumerState<CustomerDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  /// 本页绑定的客户 ID —— 从 widget 透传, 避免满文件 `widget.customerId` 噪
  String get customerId => widget.customerId;

  /// 给 widget test 暴露 controller (tester.state<...>().tabController.index = N)
  TabController get tabController => _tabController;

  /// 行动卡折叠状态: 详情页 body 上滑越过阈值 → true, 回顶 → false
  ///
  /// 由 `NotificationListener<ScrollNotification>` 一处统一收口 (B 节注释):
  ///   三个 Tab 的滚动容器各自独立 (互不共享 PrimaryScrollController), 没法
  ///   简单地在每个 TabBarView 子节点上挂 ScrollController; 改走
  ///   「子树冒泡的 ScrollNotification」一处监听, 轴向过滤掉横向 PageView 的
  ///   滚动, 状态靠 setState 推进 (变了才刷, 避免每帧 rebuild)。
  ///
  /// 2026-09-24 拓展: L0「现在该做」卡 + 记录 Tab 顶部的「跟进任务」卡
  ///   **共用这一个折叠状态** (主人诉求: 「跟进任务卡随上滑收起, 但不能
  ///   全部不见了」—— 同一把折叠机的两个消费者, 同时收 / 同时展)。
  bool _actionsCollapsed = false;

  @override
  void initState() {
    super.initState();
    // ⚠ 不用 DefaultTabController 是有意的 —— SnackBar「查看任务」action 要
    //   animateTo(0) + Scrollable.ensureVisible, 没有 controller 句柄做不了。
    //   同步换 StatefulWidget + dispose (本页生命周期跟 route 同生同死, 内存
    //   leak 风险已退到路由层级, Flutter framework 管)。
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 行动卡折叠状态的滚动收口 (NotificationListener 回调)。
  ///
  /// 为什么 `bool` 返回: `false` 让 notification 继续向上冒泡, 不阻断父级
  /// (例如 Scaffold 的 AppBar 嵌套滚动、NestedScrollView 等) 的处理。
  /// 只读 + 不阻断 = 纯观察者, 不会跟未来引入的滚动机制冲突。
  bool _onScrollForCollapse(ScrollNotification notification) {
    // 过滤横向: TabBarView (横向 PageView) 自身也会冒泡 ScrollUpdateNotification,
    // 不挡会把"切 Tab"误判成"页面上滑"。metrics.axis 是 notification 携带的
    // 真实轴, 直接读最稳 (不依赖子节点类型)。
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    // 双阈值: > 24 才折叠 (容忍轻微抖动); <= 0 才展开 (回顶才回)
    // 当前 pixels < 0 在正常滚动里不该出现 (overscroll 阶段), 但保留等于 0 的判定
    // 让"刚好回到顶"也能展开。
    final pixels = notification.metrics.pixels;
    final shouldCollapse = pixels > AppSpace.s24; // 24pt
    final shouldExpand = pixels <= 0;
    if (shouldCollapse && !_actionsCollapsed) {
      setState(() => _actionsCollapsed = true);
    } else if (shouldExpand && _actionsCollapsed) {
      setState(() => _actionsCollapsed = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final asyncCustomer = ref.watch(customerDetailProvider(customerId));

    // P2 (主人 2026-09-23 + 2026-09-24 拍): 单页 11 section 堆叠 → L0 + 3 Tab
    //
    // 为什么用自管 TabController 而不是 DefaultTabController:
    //   2026-09-24 P1 闭环诉求: 「建任务」 SnackBar 的「查看任务」action 要
    //   切回「记录」Tab。早期还要 Scrollable.ensureVisible 滚跟进任务进视口
    //   —— 但 2026-09-24 跟随进任务卡固定后, 那段逻辑也不要了 (_revealFollowUpSection
    //   只负责切 Tab + 收回折叠)。不再需要 _followUpKey GlobalKey 字段。
    //   既然必须 StatefulWidget (为了 animateTo), 就一并把 animateTo 拿到手
    //   (后面跟 TabBar/View 显式绑 controller, 不再用 DefaultTabController.of 兜底)。
    //
    // 为什么 L0 (行动卡) 在 TabBarView **外面**:
    //   CHARTER §1.4 的「行动输出 = 明确的跟进指引」必须**切 Tab 也可见** ——
    //   放进任一 Tab 里就等于"只有切到那个 Tab 才看得到", 又退回"要滚才看见"的老毛病。
    //   评分卡则在「分析」Tab 内 (主人 2026-09-24 拍: 评分是参考, 不是日常产出,
    //   三个 Tab 都有评分环 = 反 vibe)。
    return Scaffold(
      appBar: AppBar(
        // 标题 = **当前客户的姓名** (主人 2026-09-24 拍):
        //   原来固定写「客户详情」—— 但销售经常同时开着好几个客户的详情页 /
        //   从中转/搜索结果点进来, 顶部不写名字就不知道在谁那里 (得往下滚看一眼 L0)。
        //   与 body 同一套 `asyncCustomer.maybeWhen`: 还没拿到数据时回落通用文案,
        //   避免顶部空一块 (与 AppBar.bottom 只在 data 分支出 Tab 同一思路)。
        //   ⚠ 不写 fontSize / color —— 让 AppBarTheme.titleTextStyle 管样式
        //   (写死字号会绕过字号档位, 也是护栏 `flutter.fontSize` 盯的项)。
        title: asyncCustomer.maybeWhen(
          data: (c) => Text(
            c.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          orElse: () => const Text('客户详情'),
        ),
        toolbarHeight: AppSize.appBarHeight,
        // ⚠ 2026-09-24 主人拍: 编辑入口**不再**放顶栏 (顶栏图标在三个 Tab 都可见 =
        //   "全局编辑页"的感觉); 改为「基础信息卡」右上角一个编辑图标
        //   (见下方 _buildHeader —— 谁的信息在哪改, 入口就在哪)。
        // Tab 只在数据就绪后出现 (加载中/出错时没有东西可切, 显示 Tab 反而误导)
        bottom: asyncCustomer.maybeWhen(
          data: (_) => TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '记录'),
              Tab(text: '分析'),
              Tab(text: '管理'),
            ],
          ),
          orElse: () => null,
        ),
      ),
      body: asyncCustomer.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (customer) => NotificationListener<ScrollNotification>(
          // 一处监听纵向滚动 → 推进行动卡折叠状态。
          //
          // 为什么用 NotificationListener 而不是给每个 Tab 装 ScrollController:
          //   三个 Tab 各自有 SingleChildScrollView, 滚动容器**互相独立**
          //   (主用 `_tabScroll` 的 `primary: false`, 本页注释解释过 ——
          //   默认共享 PrimaryScrollController 会让切 Tab 时滚动位置串掉)。
          //   给三个 Tab 都装 controller = 三处监听 + 还得协调谁主导; 不如
          //   收口子树冒泡上来的 ScrollNotification, 零侵入 + 顺带覆盖
          //   后续 Tab 增删。
          //
          // 为什么阈值 24 / 回顶才展开 (双阈值防抖):
          //   · 上滑阈值 24: 容忍少量「差点就滚」的轻微滚动, 不至于一碰就折叠,
          //     视觉跳。
          //   · 回到 <= 0 才展开: 同样容忍小范围来回弹; 不要求像素级归零。
          //   两边都有阈值 = 防抖 (轻微回弹不会反复折叠 → 展开 → 折叠 → 展开)。
          //
          // 为什么过滤横向 axis: TabBarView 是横向 PageView, 子树也会冒泡
          // ScrollUpdateNotification, 不过滤会把「用户左右滑切 Tab」误判为
          // 「页面上滑」。
          onNotification: _onScrollForCollapse,
          child: Column(
            children: [
              // ⚠ 2026-09-24 主人拍板: 「现在该做」行动卡**只在记录 Tab 显示**
              //   (分析 / 管理 Tab 不再出现) —— 所以它从 TabBarView 外面**搬进
              //   `_buildRecordTab` 了** (见下方该方法)。
              //   历史: P2 (2026-09-23) 曾按 CHARTER §1.4「行动输出必须切 Tab 可见」
              //   把它挂在 TabBarView 外; 本次主人明确改口径 —— 行动是"记录/跟进"
              //   流程的一部分, 分析/管理 Tab 要干净。
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildRecordTab(context, ref, customer),
                    _buildAnalysisTab(context, ref, customer),
                    _buildManagementTab(context, ref, customer),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 各 Tab 统一的滚动容器 (防止三个各写一遍 padding 漂移)
  ///
  /// ⚠ `primary: false` 是**必须的**, 不是可选优化 ——
  ///   三个 Tab 各有一个纵向 ListView, 默认 `primary: true` 时它们会**共用**
  ///   外层继承到的 `PrimaryScrollController` → 滚动位置互相串:
  ///   切到「分析」时继承了「记录」的偏移 → 顶部图表被顶出视口 →
  ///   语义树/截图里都看不到, 而 `find.text` 却仍能找到 **(极难排查)**。
  ///   每个 Tab 独立滚动位置本来就是正确的交互 (切 Tab 不该共享滚动)。
  Widget _tabScroll({required List<Widget> children}) =>
      SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.fromLTRB(AppSpace.pagePadding, AppSpace.s12,
            AppSpace.pagePadding, AppSpace.s48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  /// **记录 Tab** —— 三大动作之「记录」(2026-09-24 重构 + 接 P1 折叠诉求):
  ///   · 跟进任务**固定** (不再随滚动消失) —— 跟 L0「现在该做」共用折叠状态
  ///   · 时间线混合列表可滚 (养生 + 互动; 胶囊过滤; 上方两个添加按钮)
  ///
  /// 2026-09-24 重构 (本 commit): 跟进任务从「滚动内容里」挪到「Tab 顶部固定」。
  ///   主人诉求: 「跟进任务卡也像现在该做一样随上滑收起, 但不能随上滑全部不见了」。
  ///   修法 = 固定卡 + 共用 `_actionsCollapsed` (同把折叠机的两个消费者):
  ///     · 详情页 body 用 `Column` 套 [固定跟进卡, 可滚时间线]
  ///     · 跟进卡传 `collapsed: _actionsCollapsed` + `onToggleCollapsed: () => setState(() => _actionsCollapsed = false)`
  ///     · 时间线包进 `Expanded` + 单一 `SingleChildScrollView`, 滚动只影响时间线,
  ///       跟进卡永远在视口里 → "全部不见了" 的根因消失
  ///   注: 这里**不**包 `_tabScroll` (那个 helper 一包整个 children 都是滚动内容),
  ///     改成手写 Column + Expanded, 因为我们要的是「混合结构: 固定卡 + 可滚」。
  ///
  /// 旧结构 (养生 → 跟进 → 互动 三大块) 已拆:
  ///   · 养生 + 互动 合并 → `customer_timeline_section.dart::CustomerTimelineSection`
  ///     (同质列表 AppListRow + 胶囊过滤 + 20 条截断 + 健壮性合并)
  ///   · 跟进任务 保留在独立 section, 走 `CustomerFollowUpSection` (现固定在 Tab 顶部)
  ///   · 旧的 `_buildWellnessSection` / `_showAllRecords` / `_recordSummary` /
  ///     `CustomerInteractionSection` / `_showAddInteractionSheet` 全删
  Widget _buildRecordTab(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) {
    return Column(
      children: [
        // ★ L0 行动输出卡「现在该做」—— **只在记录 Tab** (主人 2026-09-24 拍板;
        //   之前挂在 TabBarView 外, 切 Tab 也可见)。
        //   折叠态由页面状态推进 (上滑 > 24px → 折叠; 回顶 → 展开), 跟下面的
        //   跟进卡共用同一个 `_actionsCollapsed`。
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.pagePadding, AppSpace.s8, AppSpace.pagePadding, 0),
          child: CustomerInsightActions(
            customerId: customerId,
            onBuildTask: (action) =>
                _buildTaskFromAction(context, ref, action),
            onClaim: (action) => _claimFromAction(context, ref, action),
            collapsed: _actionsCollapsed,
            onToggleCollapsed: () {
              // 手动点展开图标 → 强制回到展开态 (不管当前滚动位置)
              if (_actionsCollapsed) {
                setState(() => _actionsCollapsed = false);
              }
            },
          ),
        ),
        // ★ 固定跟进卡 (跟 L0 共用 _actionsCollapsed; 折叠图标也在卡内,
        //   点了回调切回 false)。Padding 是横向 pagePadding (跟 L0 左侧对齐),
        //   上方 s12 (跟 L0 间留呼吸), 下方 0 (时间线自身有 padding)。
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.pagePadding,
            AppSpace.s12,
            AppSpace.pagePadding,
            0,
          ),
          child: CustomerFollowUpSection(
            customerId: customerId,
            collapsed: _actionsCollapsed,
            onToggleCollapsed: () {
              if (_actionsCollapsed) {
                setState(() => _actionsCollapsed = false);
              }
            },
          ),
        ),
        // ★ 记录卡 (2026-09-24 第三版, 主人诉求): 「筛选/添加键与列表整体卡片化」
        //   + 「表头不要随列表上滑而隐藏」—— 表头 + 列表现在在**同一张卡**里
        //   (CustomerTimelineSection 内部: 固定表头 + 可滚列表)。
        //   ⇒ 这里只给横向 pagePadding + 顶部 s6, 垂直方向交给 Expanded 撑满;
        //     **不再**套外层 SingleChildScrollView (否则整张卡会一起滚走, 表头就没了)。
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.pagePadding,
              AppSpace.s6,
              AppSpace.pagePadding,
              0,
            ),
            child: CustomerTimelineSection(
              customerId: customerId,
              // ⏵ 2026-09-25 ⑩ 趋势入口: 点「趋势」按钮 → 切到分析 Tab (index 1)
              onViewTrends: () => _tabController.animateTo(1),
            ),
          ),
        ),
      ],
    );
  }

  /// **分析 Tab** —— 三大动作之「分析」: 评分卡 → 图谱 → 跟进节奏(含复购预测) → AI 解读
  ///
  /// 2026-09-25 改造 (P1 合并节奏卡):
  ///   · 旧的 FollowUpAnalysisCard + RepurchaseCard 已合并成 CustomerRhythmCard
  ///     (跟进分析 + 复购预测 两段独立加载, 一段挂了另一段照常显示)
  ///   · 雷达已删 (2026-09-24), 见 CustomerAnalysisCharts 头部注释
  ///   · AI 区只剩三张卡 (画像 / 话术 / 效果), 共用一次调用 (P5)
  Widget _buildAnalysisTab(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) {
    return _tabScroll(children: [
      // ★ 评分卡 (2026-09-24 主人拍: 评分只放在分析 Tab, 不再是 L0)
      //   与 L0 行动卡同源 (都读 customerInsightProvider), 但评分是"参考", 不是"产出",
      //   销售日常看行动 (切 Tab 可见), 真要看分才进分析 Tab。
      CustomerScoreCard(customerId: customerId),
      const SizedBox(height: AppSpace.cardGap),
      // ★ P4 图谱 (主人 2026-09-23 拍, 2026-09-24 砍雷达): 效果趋势 / 部位热力
      //   放评分卡之后: 图比文字快 —— "她整体怎样" 一眼就能看出。
      //   雷达已删 (同源重复 + 3 维可读性差 + Tab 太长), 见组件头部注释。
      CustomerAnalysisCharts(customerId: customerId),
      const SizedBox(height: AppSpace.cardGap),
      // ★ 客观指标 + 复购预测 合并卡 (P1, 2026-09-25):
      //   跟进分析 (免费) + 复购预测 (纯 DB 自动加载) 合并成一张卡,
      //   两段独立加载 / 独立错误态 (静默降级); 复购预测已不再单独成卡。
      CustomerRhythmCard(customerId: customerId),
      const SizedBox(height: AppSpace.cardGap),
      // AI 智能区 (会员): 顺序按「销售员每天最用得上」排
      //   跟进建议 (开口话术 · 唯一生成入口) → 客户画像 (这人是谁) → 效果分析 (疗程有没有用)
      //   P5: 三张卡共用一次调用; P2: 只有话术卡出「生成 AI 解读」按钮 (单入口)
      //   P0: 会员判定走 customerInsightProvider.scriptAvailable, 锁态时
      //   改出「升级会员」按钮 (话术卡) / 锁块 (其他两张卡)
      _buildSectionTitle('AI 助手'),
      AiFollowUpCard(customerId: customerId),
      AiProfileCard(customerId: customerId),
      EffectAnalysisCard(customerId: customerId),
    ]);
  }

  /// **管理 Tab** —— 三大动作之「管理」: 档案字段 + 类型 + 身份
  ///
  /// 为什么把这三个从首屏挪进 Tab:
  ///   它们是"设置频次"的内容 (改一次就不动), 却占着详情页最宝贵的前两屏。
  ///   L0 要留给"每天看"的东西 (§1.4 行动输出)。
  Widget _buildManagementTab(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) {
    // 2026-09-24 重构 (建议 #7): 5 张卡平铺 → 三节分组 (档案 / 关系与身份 / 最近改动)
    //   + 危险操作单独放最后 (视觉隔离, 防误点)
    return _tabScroll(children: [
      // ── ① 档案 ──
      const AppSectionHeader(title: '档案', padding: EdgeInsets.zero),
      const SizedBox(height: AppSpace.s8),
      // #9: 健康提示独立成卡 (过敏/病史 = 安全信息, 不再埋在大头像卡里;
      //   没填时给一条轻提示 —— AI 话术/效果分析都要用)
      CustomerHealthCard(customer: customer),
      const SizedBox(height: AppSpace.cardGap),
      // 大头像 + 基本信息 (类型徽章 / 手机号+复制 / 生日+提醒档位 / 标签 / 备注)
      _buildHeader(context, ref, customer),

      const SizedBox(height: AppSpace.s24),
      // ── ② 关系与身份 ──
      const AppSectionHeader(title: '关系与身份', padding: EdgeInsets.zero),
      const SizedBox(height: AppSpace.s8),
      // ★ 归属 (P7): 谁把她当客户在管 + 认领。
      //   放在类型卡**之前**: 归属是"她算不算我的客户"的前提 (ADR-0015 Q11/Q12)。
      CustomerOwnershipCard(customerId: customerId),
      const SizedBox(height: AppSpace.cardGap),
      // 客户类型切换 (主人 2026-09-18: 「没找到修改客户类型的入口」)
      _buildTypeCard(context, ref, customer),
      const SizedBox(height: AppSpace.cardGap),
      // app 身份 (ADR-0016): 已注册/未注册 + 邀请码绑定 + **她的邀请码** (#6)
      _buildIdentityCard(context, ref, customer),

      const SizedBox(height: AppSpace.s24),
      // ── ③ 最近改动 (#2): 归属转移/合并/绑定/归档 都能查到"谁改的" ──
      const AppSectionHeader(
        title: '最近改动',
        subtitle: '谁在什么时候改了什么 (只记字段名, 不记内容)',
        padding: EdgeInsets.zero,
      ),
      const SizedBox(height: AppSpace.s8),
      CustomerAuditCard(customerId: customerId),

      const SizedBox(height: AppSpace.s24),
      // ── 危险操作 (P8): 归档 / 合并 —— 放最底部, 需要时才滑下来看 ──
      CustomerDangerZoneCard(
        customerId: customerId,
        customerName: customer.name,
      ),
    ]);
  }

  /// 「认领归属」—— 把 `profile_incomplete` 那条行动的闭环做完
  ///
  /// 2026-09-23 修 (主人拍「先挂起…修」后落的): 这条行动原本只有一个「建任务」按钮,
  ///   而建任务**完全不碰 `customer.owner_id`** → `hasOwner` 恒为 false →
  ///   行动永远消不掉 (死路, 详见 docs/backlog 挂起项)。
  ///
  /// 本方法的职责就是把「行动」真闭环: 改归属 → 刷新洞察 (hasOwner 变 true → 行动消失)
  ///   + 刷新归属卡 / 客户列表 (三处都受归属影响)。
  Future<void> _claimFromAction(
    BuildContext context,
    WidgetRef ref,
    ActionItem action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(customerServiceProvider).claim(customerId);
      // 归属变了 → 这四处都受影响
      ref.invalidate(customerInsightProvider(customerId)); // 行动据此消失
      ref.invalidate(customerOwnershipProvider(customerId)); // 管理 Tab 的归属卡
      ref.invalidate(customerDetailProvider(customerId));
      ref.invalidate(customersProvider); // “我的客户”列表
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('已认领为我的客户'),
        ),
      );
    } catch (e) {
      // 409/400 都有业务含义 (被别人抢先 / 是自己) —— 把后端的话翻成人话给用户
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(humanClaimError(e))),
      );
    }
  }

  /// 「建任务」—— 把一条行动指引落成 follow_up_task (闭环的关键一步)
  ///
  /// 为什么这是 P1 的核心: CHARTER §1.4 要求"明确的**可落地**跟进指引"。
  ///   只给一段话术 = 不可勾选/不可追踪; 建了任务才有 dueAt + 状态 + 完成回写,
  ///   完成率还会反哺下一轮评分的「任务健康」因子。
  ///
  /// 2026-09-24 P1 闭环反馈修: 原本只 invalidate 洞察, **漏** invalidate
  /// `customerFollowUpTasksProvider` → 「记录」Tab 的「跟进任务」列表停留旧数据
  /// (销售以为没建成功, 反复点「建任务」)。对照 `customer_activity_cards.dart`
  /// 里 `showAddFollowUpSheet` 的做法: 也 invalidate 跟进任务列表。
  /// SnackBar 同步升级: 加上「查看任务」action, 点了切回记录 Tab 并把
  /// 「跟进任务」滚进视口 —— 不再让用户「建完了不知道怎么找」。
  Future<void> _buildTaskFromAction(
    BuildContext context,
    WidgetRef ref,
    ActionItem action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dueAt = DateTime.tryParse(action.taskDueAt) ?? DateTime.now();
      await ref.read(followUpServiceProvider).create({
        'customerId': customerId,
        'dueAt': dueAt.toUtc().toIso8601String(),
        'reason': action.taskTitle,
      });
      ref.read(usageServiceProvider).track('follow_up_task_created',
          props: {'from': 'insight_action', 'rule': action.id});
      // 任务列表 / 洞察都刷新 (洞察的"任务健康"因子会变)
      ref.invalidate(customerInsightProvider(customerId));
      // ★ 跟进任务列表同步刷 (之前漏, 详见本函数头注释)
      ref.invalidate(customerFollowUpTasksProvider(customerId));
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          // ⚠ 2026-09-24: UTC → local, 跟 _tile 文案同口径,
          //   CST 早晨 00:00-08:00 拿 UTC 直接出年月日的「-1 天」坑。
          content: Text(
            '已建任务「${action.taskTitle}」· ${DateFormat('MM-dd').format(dueAt.toLocal())} 到期',
            style: const TextStyle(fontSize: AppType.md),
          ),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '查看任务',
            onPressed: _revealFollowUpSection,
          ),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('建任务失败: $e',
              style: const TextStyle(fontSize: AppType.md)),
        ),
      );
    }
  }

  /// 「查看任务」= 切回「记录」Tab + 把「跟进任务」**展回** (2026-09-24 简化)
  ///
  /// 变更点 (vs 旧实现): 跟进任务卡**不再**放在滚动区里 (固定在 Tab 顶部) → 旧
  ///   「Scrollable.ensureVisible 把它滚进视口」整段逻辑不需要了 —— 卡永远是
  ///   可见的, 切回 Tab 就够, 顺带把折叠状态收回 (因为任务列表**刚刚被新建**,
  ///   销售第一时间要看的是任务详情, 不是折叠态的一行 header)。
  ///
  /// 有界等待 animateTo (同根 §5「不要用无界 sleep 猜时间」): 上限 1s, 50ms 步进,
  ///   拿到 index==0 就收手。
  ///
  /// ⚠ 不再需要 _followUpKey / Scrollable.ensureVisible: 卡已固定, 它的可见性
  ///   与滚动位置无关。GlobalKey 字段已于本 commit 删除 (全仓 0 引用, 见 git log)。
  Future<void> _revealFollowUpSection() async {
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
      // 等动画完成 (animateTo 走的 Curve.easeOut, 默认 ~300ms; 留 1s 余裕)
      for (var i = 0; i < 20; i++) {
        if (_tabController.index == 0) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
    // 卡是固定可见的, 但折叠态只有一行 header 看不到新建的任务 ——
    // 顺手把折叠状态收回, 销售立刻看到完整列表。设了状态才 setState
    // (避免无谓 rebuild)。
    if (_actionsCollapsed) {
      setState(() => _actionsCollapsed = false);
    }
  }

  // ────────────────────────────────────────────────────────────
  // 旧的 `_buildWellnessSection` / `_showAllRecords` / `_recordSummary`
  // 已在 2026-09-24 记录 Tab 重构中删除 —— 养生记录已迁移到
  // `customer_timeline_section.dart::CustomerTimelineSection` (与互动记录混合列表)。
  // ────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, WidgetRef ref, Customer c) {
    final type = c.customerType;
    final age = c.birthYear == null
        ? null
        : DateTime.now().year - c.birthYear!;
    return B2NoChrome(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        // Stack: 编辑图标浮在卡片右上角 (不挤占原有的居中布局)
        child: Stack(
          children: [
            Column(
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
                      child: const Tooltip(
                        message: '点头像可以换 (拍照 / 相册 / 现成头像)',
                        child: Icon(Icons.photo_camera,
                            size: AppSize.iconSm, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.s8),
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
            // 手机号 + 一键复制 (2026-09-24 建议 #4: 销售经常要粘到微信里)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _maskPhone(c.phone),
                  style: const TextStyle(
                    fontSize: AppTheme.fontMd,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(width: AppSpace.s4),
                IconButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: c.phone));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('手机号已复制')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: AppSize.iconSm),
                  tooltip: '复制手机号',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(AppSpace.s4),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            // #8: 三个 chip → 一行文字 (密度)
            const SizedBox(height: AppSpace.s4),
            Text(
              [
                if (c.gender != null)
                  c.gender == 'F' ? '女' : c.gender == 'M' ? '男' : '未知',
                if (age != null) '$age 岁',
                '建档 ${DateFormat('yyyy-MM-dd').format(c.createdAt)}',
              ].join(' · '),
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                color: context.tokens.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
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
                    onTap: () => showAddInteractionSheet(context, ref,
                        customerId: c.id, customerName: c.name),
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
                              size: AppSize.iconMd,
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
                      // #5 (2026-09-24): 提醒档位**就地**可改 (原来要进编辑表单)
                      const SizedBox(height: AppSpace.s6),
                      Wrap(
                        spacing: AppSpace.s6,
                        children: [
                          for (final d in const [7, 3, 0])
                            ChoiceChip(
                              label: Text(
                                d == 0 ? '当天' : '提前 $d 天',
                                style: const TextStyle(fontSize: AppTheme.fontXs),
                              ),
                              selected: c.birthdayRemindDays == d,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) =>
                                  _setBirthdayRemind(context, ref, c, d),
                            ),
                          ChoiceChip(
                            label: const Text('不提醒',
                                style: TextStyle(fontSize: AppTheme.fontXs)),
                            selected: c.birthdayRemindDays == null,
                            visualDensity: VisualDensity.compact,
                            onSelected: (_) =>
                                _setBirthdayRemind(context, ref, c, null),
                          ),
                        ],
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
            if (c.healthTags.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s12),
              _buildHealthTags(c),
            ],
            // #3 (2026-09-24): 备注 + 最后修改 —— 之前管理 Tab 只显示到标签
            if ((c.notes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: AppSpace.s12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.s12),
                decoration: BoxDecoration(
                  color: context.tokens.surfaceSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('备注',
                        style: TextStyle(
                            fontSize: AppTheme.fontXs,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary)),
                    const SizedBox(height: AppSpace.s4),
                    Text(c.notes!.trim(),
                        style: const TextStyle(fontSize: AppTheme.fontSm)),
                  ],
                ),
              ),
            ],
            // ★ Phase C §1 维度 6 + §4.2 L4 (D6 拍「详情仅管理 Tab 的档案卡显示」):
            //   档案卡走中性 badge (AppBadge tone=neutral, 不另新增色) + 可选「介绍人: XXX」;
            //   跟 web admin 「客户来源: XXX」同口径。遵约束: 不新增 Card, 不涨行高,
            //   跟原有的「最后修改」小字同一条信息密度。
            const SizedBox(height: AppSpace.s12),
            _buildSourceRow(c),
            const SizedBox(height: AppSpace.s8),
            Text(
              '最后修改 ${DateFormat('yyyy-MM-dd HH:mm').format(c.updatedAt.toLocal())}',
              style: TextStyle(
                  fontSize: AppTheme.fontXs, color: context.tokens.textTertiary),
            ),
          ],
        ),
            // ★ 编辑档案入口 (2026-09-24 主人拍): 基础信息卡右上角
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                icon: const Icon(Icons.edit, size: AppSize.iconLg),
                tooltip: '编辑档案',
                visualDensity: VisualDensity.compact,
                onPressed: () => context.push('/customers/${c.id}/edit'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 生日提醒档位 (7/3/当天/不提醒) —— PATCH 后刷新详情 (#5)
  Future<void> _setBirthdayRemind(
    BuildContext context,
    WidgetRef ref,
    Customer c,
    int? days,
  ) async {
    if (c.birthdayRemindDays == days) return;
    try {
      await ref
          .read(customerServiceProvider)
          .update(c.id, {'birthdayRemindDays': days});
      ref.invalidate(customerDetailProvider(c.id));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(days == null ? '已关闭生日提醒' : '生日提醒已设为提前 $days 天')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置失败: $e')),
      );
    }
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

  // ──────────────────────────────────────────────────────
  // 旧的 `_showAddInteractionSheet` 已于 2026-09-24 删除。
  //   管理 Tab 「记一次互动」按钮 → 直接调 `showAddInteractionSheet`
  //   (从 `complete_follow_up_sheet.dart` 导出, 跟「标记完成」共用一份 widget,
  //   标题「添加联系记录」, 按钮「保存」)。
  //   「记录」Tab 同样调它, 入口在混合列表上的两个添加按钮里。
  // ──────────────────────────────────────────────────────

  /// 客户类型卡 (普通 ↔ 种子 一键切换; 加盟类型由关系决定不可切)
  /// app 身份卡 (ADR-0016, 主人 2026-09-22 拍):
  ///   「客户列表中的客户有一些也是 app 用户, 有一些没有注册 app 账号」
  ///   → 详情页给出状态; 没绑定的可以**填她的邀请码 (身份识别码)** 绑定 —— 手机号对不上也能绑
  Widget _buildIdentityCard(BuildContext context, WidgetRef ref, Customer c) {
    final bound = c.hasAccount;
    return B2NoChrome(
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
                  size: AppSize.iconMd,
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
            // #6 (2026-09-24): 已注册 → 直接显示**她的邀请码** + 一键复制
            //   (拉她进沙龙/活动、核对身份时不用回头问她)
            if (bound) ...[
              Row(
                children: [
                  Icon(Icons.qr_code_2,
                      size: AppSize.iconMd, color: context.tokens.primaryDark),
                  const SizedBox(width: AppSpace.s6),
                  const Text('她的邀请码',
                      style: TextStyle(
                          fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
                  const Spacer(),
                  Text(
                    (c.accountReferralCode ?? '').isEmpty
                        ? '—'
                        : c.accountReferralCode!,
                    style: const TextStyle(
                      fontSize: AppTheme.fontLg,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if ((c.accountReferralCode ?? '').isNotEmpty) ...[
                    const SizedBox(width: AppSpace.s4),
                    IconButton(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: c.accountReferralCode!));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('邀请码已复制')),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded, size: AppSize.iconSm),
                      tooltip: '复制邀请码',
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.all(AppSpace.s4),
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpace.s8),
            ],
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
                  icon: const Icon(Icons.qr_code_2, size: AppSize.iconMd),
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
    return B2NoChrome(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_outlined,
                    size: AppSize.iconMd, color: AppTheme.primaryDark),
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
                icon: const Icon(Icons.person_add_alt_1, size: AppSize.iconLg),
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

  /// 客户来源行 (Phase C §1 维度 6 + §4.2 L4, D6 拍「仅详情管理 Tab 的档案卡」)
  ///
  ///   来源 = 4 个枚举 + 未填写; null → "未填写" (后端默认)。
  ///   「转介绍」(referral) → 多出「介绍人: XXX」一行 (后端 zod refine 保证非空)。
  ///   不新增 Card / 不加饱和色: 走现有 AppBadge tone=neutral + 一行文字, 跟备注/最后修改
  ///   同信息密度; 遵约束行高不变。
  Widget _buildSourceRow(Customer c) {
    final source = c.acquireSource;
    final referrer = (c.sourceReferrerName ?? '').trim();
    final label = _acquireSourceLabel(source);
    final isReferral = source == 'referral' && referrer.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('客户来源',
            style: TextStyle(
                fontSize: AppTheme.fontSm,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary)),
        const SizedBox(width: AppSpace.s8),
        AppBadge(label: label, tone: AppBadgeTone.neutral),
        if (isReferral) ...[
          const SizedBox(width: AppSpace.s8),
          Expanded(
            child: Text(
              '介绍人: $referrer',
              style: const TextStyle(
                  fontSize: AppTheme.fontSm, color: AppTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: AppType.md,
          fontWeight: AppWeight.semibold,
          color: t.textPrimary,
        ),
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
// 顶层方法 (被 CustomerDetailPage 用, 放本文件内)
// ============================================

/// 客户来源枚举 → 中文短词 (Phase C §1 维度 6 与 web admin 同口径):
///   null / 未下发 → "未填写"
///   friend / referral / cold_visit / ground_promo → 亲友 / 转介绍 / 陌生拜访 / 地推
String _acquireSourceLabel(String? source) {
  switch (source) {
    case 'friend':
      return '亲友';
    case 'referral':
      return '转介绍';
    case 'cold_visit':
      return '陌生拜访';
    case 'ground_promo':
      return '地推';
    case null:
    case '':
    default:
      return '未填写';
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
          // ★ Phase B §6 E1: 直推者从 PlacementTargetSheet 透传 (null = 服务端默认)
          referrerFid: target.referrerFid,
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
