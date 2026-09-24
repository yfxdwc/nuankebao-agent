// ============================================
// 客户详情 · 「记录」Tab 时间线混合列表 (2026-09-24 拍板重构)
//   ⏵ 2026-09-25: 时间线 10 项 UI/交互改进
//     ① 空态 → AppEmptyState (带 action + secondaryAction)
//     ② 错误态 → ErrorState (两边都空) 或 行内错误行 (单边)
//     ③ 加载态 → AppSkeletonList (两边都空)
//     ④ 单边 loading → 列表尾部小字
//     ⑤ 加载更多 → _visibleCount (初始 20, 步长 20; 切换 filter 重置 20)
//     ⑥ 下次建议日期 → adviceHint (逾期片段染 AppColors.warning)
//     ⑦ 相对时间 → relativeDayLabel (汇总行「最近一次 今天/昨天/N 天前」)
//     ⑧ 照片指示 → meta 显示相机图标 + 张数
//     ⑨ 日期分组头 → today/yesterday/thisWeek/thisMonth/earlier
//     ⑩ 趋势入口 → onViewTrends callback (brand 色 + 热区≥48)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/dictionaries.dart';
import '../../../core/models/follow_up.dart' show Interaction, interactionTypeLabels;
import '../../../core/models/wellness_record.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/app_empty.dart';
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/b2_no_chrome.dart';
import '../../follow_up/widgets/complete_follow_up_sheet.dart' show showAddInteractionSheet;
import 'record_format.dart';

// ============================================
// 主 widget — 「时间线」 section
// ============================================

class CustomerTimelineSection extends ConsumerStatefulWidget {
  final String customerId;

  /// ⑩ 趋势入口回调 — 主人要求在汇总行加「趋势」按钮, 点了切到分析 Tab
  ///   (具体跳到哪个 Tab 由调用方决定, 本 widget 不持有 tab controller)
  final VoidCallback? onViewTrends;

  const CustomerTimelineSection({
    super.key,
    required this.customerId,
    this.onViewTrends,
  });

  @override
  ConsumerState<CustomerTimelineSection> createState() =>
      _CustomerTimelineSectionState();
}

class _CustomerTimelineSectionState
    extends ConsumerState<CustomerTimelineSection> {
  /// 过滤胶囊: 全部 / 养生 / 互动 (默认「全部」, 主人诉求)
  _Filter _filter = _Filter.all;

  /// ⑤ 分页可见数 — 初始 20, 点「加载更多」+20; 切换 filter 时重置 20
  static const int _pageSize = 20;

  int _visibleCount = _pageSize;

  void _resetVisibleCountOnFilterChange(_Filter next) {
    if (_filter == next) return;
    setState(() {
      _filter = next;
      _visibleCount = _pageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ⚠ 两边 provider 各自管理自己的状态, 用 valueOrNull 合并:
    //   · 一边 loading / error 不会拖垮另一边
    //   · 仅当两边**都**空 → 才进入骨架 / 错误态
    final asyncWellness =
        ref.watch(customerWellnessRecordsProvider(widget.customerId));
    final asyncInteractions =
        ref.watch(interactionsForCustomerProvider(widget.customerId));

    final wellness =
        asyncWellness.valueOrNull ?? const <WellnessRecord>[];
    final interactions =
        asyncInteractions.valueOrNull ?? const <Interaction>[];

    // 字典 (服务项目 / 部位名) — null 时只影响显示, 不影响列表渲染
    final dict = ref
        .watch(dictionariesProvider)
        .maybeWhen(data: (d) => d, orElse: () => null);

    // 1) 养生汇总 (单行小字, fontXs + textTertiary) —— 与旧 _buildWellnessSection 同口径
    final summary = _summaryLine(wellness);

    // 2) 合并 + 排序 (按时间倒序) + 截断到 _visibleCount
    final timelineAll = _buildTimeline(
      wellness: wellness,
      interactions: interactions,
      filter: _filter,
    );
    final timeline = timelineAll.length > _visibleCount
        ? timelineAll.take(_visibleCount).toList()
        : timelineAll;

    final list = _timelineList(
      dict: dict,
      timeline: timeline,
      timelineTotal: timelineAll.length,
      totalWellness: wellness.length,
      totalInteractions: interactions.length,
      asyncWellness: asyncWellness,
      asyncInteractions: asyncInteractions,
      visibleCount: _visibleCount,
      onLoadMore: () =>
          setState(() => _visibleCount += _pageSize),
    );

    // ── 固定表头 (不随列表滚动): 筛选下拉 + 添加记录 + 养生汇总 ──
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.cardPadding,
        AppSpace.s12,
        AppSpace.cardPadding,
        AppSpace.s10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbarRow(context),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: AppSpace.s6),
            _summaryRowWidget(summary),
          ],
        ],
      ),
    );

    return B2NoChrome(
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          // 空间不足时的**退化策略** (2026-09-24, 防 RenderFlex overflow):
          //   L0 行动卡 + 跟进任务卡都是固定 chrome, 一旦它们把小屏/大字号的
          //   剩余高度吃到 < 表头 (~90) + 几行列表, 固定表头就撑破卡片 →
          //   黄黑条纹 / release 下悄悄裁掉。
          //   ⇒ 低于阈值时把表头**并入滚动** (表头不再钉住, 但内容都能看到、
          //     不溢出错版); 正常空间仍是"固定表头 + 卡内滚动列表"。
          //   阈值 240 ≈ 表头 ~90 + dense 行 52 × 2.5 —— 够放表头和两行才值得钉。
          const pinnedMinHeight = 240.0;
          if (constraints.maxHeight < pinnedMinHeight) {
            return SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.only(bottom: AppSpace.s8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  const Divider(height: 1),
                  list,
                ],
              ),
            );
          }
          return Column(
            children: [
              header,
              const Divider(height: 1),
              // ── 唯一可滚区域: 混合列表 (行用 AppListRow dense) ──
              //   Expanded 吃掉卡片剩余高度 → 列表在卡片内滚, 表头永远钉住
              Expanded(
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.only(bottom: AppSpace.s8),
                  child: list,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── 一行工具栏 ──
  //
  // 拆成两个 PopupMenuButton (左 / 右), 中间 Spacer:
  //   · 左 = 筛选 (全部 / 养生记录 / 互动记录)
  //   · 右 = 添加记录 (养生 / 联系)
  // 高度统一 AppSize.controlLg (44) —— ≥ tapMin (48) 接近, 满足 controlLg 触摸友好档。
  // PopupMenuButton 而非 ChoiceChip / FilledButton.icon: 既保留「点击展开」语义,
  // 又能在窄屏上不挤 —— 旧 ChoiceChip + 2 FilledButton 行高 48+48+8=104,
  // 现合并后只占 44 + 一行间距。
  Widget _toolbarRow(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        // ── 左: 内容选择下拉 (act 模式: open menu 选中切换过滤) ──
        PopupMenuButton<_Filter>(
          // 锁 key: 测试与外层 `find.byKey('timelineFilterDropdown')` 共用
          key: const ValueKey('timelineFilterDropdown'),
          tooltip: '',
          onSelected: _resetVisibleCountOnFilterChange,
          position: PopupMenuPosition.under,
          itemBuilder: (ctx) => _Filter.values
              .map((f) => PopupMenuItem<_Filter>(
                    value: f,
                    height: AppSize.controlLg,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: AppSize.iconMd,
                          height: AppSize.iconMd,
                          child: _filter == f
                              ? Icon(Icons.check,
                                  size: AppSize.iconSm, color: t.primary)
                              : null,
                        ),
                        const SizedBox(width: AppSpace.s8),
                        Text(
                          f.label,
                          style: TextStyle(
                            fontSize: AppType.sm,
                            color: t.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
          child: _filterDropdownChild(t),
        ),
        // ── 中: Spacer (左对齐 + 右对齐) ──
        const Spacer(),
        // ── 右: 添加记录下拉 (FilledButton.tonal 观感) ──
        PopupMenuButton<_AddAction>(
          key: const ValueKey('timelineAddRecordButton'),
          tooltip: '',
          onSelected: (a) => _handleAddAction(a),
          position: PopupMenuPosition.under,
          itemBuilder: (ctx) => [
            _addMenuItem(_AddAction.wellness,
                icon: Icons.spa_outlined, label: '添加养生记录'),
            _addMenuItem(_AddAction.interaction,
                icon: Icons.phone_in_talk, label: '添加联系记录'),
          ],
          child: _addRecordDropdownChild(t),
        ),
      ],
    );
  }

  // ── 工具栏左: 当前过滤 + 下拉箭头 (胶囊外观) ──
  Widget _filterDropdownChild(AppTokens t) {
    return Container(
      height: AppSize.controlLg,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s12, vertical: AppSpace.s8),
      constraints: const BoxConstraints(minWidth: AppSpace.s40),
      decoration: BoxDecoration(
        border: Border.all(color: t.divider),
        borderRadius: BorderRadius.circular(AppRadius.r10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _filter.label,
            style: TextStyle(
              fontSize: AppType.sm,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpace.s4),
          Icon(Icons.arrow_drop_down, size: AppSize.iconMd, color: t.textSecondary),
        ],
      ),
    );
  }

  // ── 工具栏右: 「添加记录」+ 下拉箭头 (FilledButton.tonal 观感) ──
  Widget _addRecordDropdownChild(AppTokens t) {
    return Container(
      height: AppSize.controlLg,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s14, vertical: AppSpace.s8),
      decoration: BoxDecoration(
        color: t.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.r10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, size: AppSize.iconMd, color: t.primaryDark),
          const SizedBox(width: AppSpace.s4),
          Text(
            '添加记录',
            style: TextStyle(
              fontSize: AppType.sm,
              color: t.primaryDark,
              fontWeight: AppWeight.medium,
            ),
          ),
          const SizedBox(width: AppSpace.s4),
          Icon(Icons.arrow_drop_down, size: AppSize.iconMd, color: t.primaryDark),
        ],
      ),
    );
  }

  // ── 添加菜单项工厂 ──
  PopupMenuItem<_AddAction> _addMenuItem(_AddAction action,
      {required IconData icon, required String label}) {
    final t = context.tokens;
    return PopupMenuItem<_AddAction>(
      value: action,
      height: AppSize.controlLg,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: AppSize.iconMd,
            height: AppSize.iconMd,
            child: Icon(icon, size: AppSize.iconSm, color: t.textSecondary),
          ),
          const SizedBox(width: AppSpace.s8),
          Text(
            label,
            style: TextStyle(
              fontSize: AppType.sm,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ── 添加动作分发 ──
  void _handleAddAction(_AddAction a) {
    switch (a) {
      case _AddAction.wellness:
        if (!mounted) return;
        if (!context.mounted) return;
        context.push('/wellness-records/new?customerId=${widget.customerId}');
        break;
      case _AddAction.interaction:
        if (!mounted) return;
        if (!context.mounted) return;
        showAddInteractionSheet(context, ref, customerId: widget.customerId);
        break;
    }
  }

  // ── 汇总行 widget ──
  //
  // 设计:
  //   · 左: 养生汇总小字 (fontXs + textTertiary)
  //   · 右: ⑩「趋势」入口 (品牌色, 仅 summary 非空且有 onViewTrends 时出现)
  //
  // 「趋势」按钮:
  //   · 视觉: 品牌色文字 + 箭头, **无卡片 / 无边框 / 无底色** (原则 4 容器越少)
  //   · 热区: 包成 SizedBox(minHeight: tapMin=48) + InkWell (Ripple 反馈)
  //   · 不写 MaterialTapTargetSize.padded (那是 ListTile 内部用的; InkWell + 显式
  //     SizedBox 即可, 满足 ≥48 触摸底线)
  Widget _summaryRowWidget(String summary) {
    final t = context.tokens;
    final hasTrends = widget.onViewTrends != null;
    return Row(
      children: [
        Expanded(
          child: Text(
            summary,
            style: const TextStyle(
              fontSize: AppType.xs,
              color: AppColors.textTertiary,
            ),
          ),
        ),
        if (hasTrends) ...[
          const SizedBox(width: AppSpace.s8),
          InkWell(
            onTap: widget.onViewTrends,
            // 直角 + 无边框: 与「列表行就该是直角的」同款
            borderRadius: BorderRadius.circular(AppRadius.r4),
            child: SizedBox(
              height: AppSize.tapMin,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.s8, vertical: AppSpace.s4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '趋势',
                      style: TextStyle(
                        fontSize: AppType.xs,
                        color: t.primaryDark,
                        fontWeight: AppWeight.medium,
                      ),
                    ),
                    const SizedBox(width: AppSpace.s2),
                    Icon(Icons.chevron_right,
                        size: AppSize.iconXs, color: t.primaryDark),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── 列表主体 ──
  Widget _timelineList({
    required Dictionaries? dict,
    required List<_TimelineRow> timeline,
    required int timelineTotal,
    required int totalWellness,
    required int totalInteractions,
    required AsyncValue<List<WellnessRecord>> asyncWellness,
    required AsyncValue<List<Interaction>> asyncInteractions,
    required int visibleCount,
    required VoidCallback onLoadMore,
  }) {
    // ② 两边都空且至少一边 error → ErrorState
    //   (任一边有数据就走下面的「单边错误 → 行内错误」分支)
    final wellnessEmpty = asyncWellness.valueOrNull == null ||
        (asyncWellness.valueOrNull?.isEmpty ?? true);
    final interactionsEmpty = asyncInteractions.valueOrNull == null ||
        (asyncInteractions.valueOrNull?.isEmpty ?? true);
    final bothEmpty = wellnessEmpty && interactionsEmpty;
    if (bothEmpty &&
        (asyncWellness.hasError || asyncInteractions.hasError)) {
      final firstErr = asyncWellness.error ?? asyncInteractions.error;
      return ErrorState(
        error: firstErr ?? '加载失败',
        onRetry: () {
          ref.invalidate(customerWellnessRecordsProvider(widget.customerId));
          ref.invalidate(interactionsForCustomerProvider(widget.customerId));
        },
      );
    }

    // ③ 两边都 loading 且**都**空 → AppSkeletonList (替换旧的「转圈 + 加载中」)
    if (asyncWellness.isLoading && asyncInteractions.isLoading && bothEmpty) {
      return const AppSkeletonList(rows: 4, dense: true);
    }

    // ① 空态 — 按当前过滤给不同文案 + action + secondaryAction
    if (timeline.isEmpty) {
      return _emptyStateFor(_filter);
    }

    // ⑨ 日期分组: 把 timeline 按 today/yesterday/thisWeek/thisMonth/earlier 切片
    //   单测覆盖在 record_format_test; 这里只组装 UI
    final groups = _groupTimeline(timeline);

    // 列表 — 行 + 分组头 + 行内错误 (单边) + 单边 loading 小字 + 加载更多 footer
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var gi = 0; gi < groups.length; gi++) ...[
          _groupHeader(groups[gi].bucket),
          for (var ri = 0; ri < groups[gi].rows.length; ri++)
            _rowWidgetFor(groups[gi].rows[ri], dict,
                showDivider: !(gi == groups.length - 1 &&
                    ri == groups[gi].rows.length - 1)),
        ],
        // ② 单边错误 (非空时): 行内错误行 + 仅 invalidate 出错 provider
        ..._inlineErrorRows(
          wellness: asyncWellness,
          interactions: asyncInteractions,
          filter: _filter,
        ),
        // ④ 单边 loading (其空且未被过滤排除): 列表尾部小字
        ..._inlineLoadingRows(
          wellness: asyncWellness,
          interactions: asyncInteractions,
          filter: _filter,
        ),
        // ⑤ 加载更多 footer
        _loadMoreFooter(
          timelineTotal: timelineTotal,
          visibleCount: visibleCount,
          onLoadMore: onLoadMore,
          // ⑥ 「养生记录较多, 当前仅加载最近 50 条」条件
          wellnessLoadedAtCap: asyncWellness.valueOrNull?.length == 50,
        ),
      ],
    );
  }

  // ── 单边错误行 (② 列表尾部内嵌) ──
  //
  // 条件: 任一边 error + **该边**数据为空 + **该边未被当前 filter 排除**
  //   · filter=all / wellness → 养生侧在视; 互动侧不在视 → 互动错误不显示
  //   · filter=interaction → 反之
  //   (有数据时 provider 自己的 error 已被 valueOrNull 吞掉, 走不到这里)
  List<Widget> _inlineErrorRows({
    required AsyncValue<List<WellnessRecord>> wellness,
    required AsyncValue<List<Interaction>> interactions,
    required _Filter filter,
  }) {
    final out = <Widget>[];
    final showWellness = filter == _Filter.all || filter == _Filter.wellness;
    final showInteractions =
        filter == _Filter.all || filter == _Filter.interaction;
    final wellnessErr = wellness.hasError &&
        (wellness.valueOrNull == null || wellness.valueOrNull!.isEmpty);
    final interactionsErr = interactions.hasError &&
        (interactions.valueOrNull == null ||
            interactions.valueOrNull!.isEmpty);
    if (showWellness && wellnessErr) {
      out.add(_inlineErrorLine(
        text: '养生记录加载失败',
        onRetry: () => ref.invalidate(
            customerWellnessRecordsProvider(widget.customerId)),
      ));
    }
    if (showInteractions && interactionsErr) {
      out.add(_inlineErrorLine(
        text: '互动加载失败',
        onRetry: () => ref.invalidate(
            interactionsForCustomerProvider(widget.customerId)),
      ));
    }
    return out;
  }

  Widget _inlineErrorLine({required String text, required VoidCallback onRetry}) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.pagePadding, AppSpace.s8, AppSpace.pagePadding, AppSpace.s8),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              size: AppSize.iconSm, color: AppColors.danger),
          const SizedBox(width: AppSpace.s8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: AppType.xs,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          // 重试按钮: 热区 ≥ AppSize.tapMin
          InkWell(
            onTap: onRetry,
            borderRadius: BorderRadius.circular(AppRadius.r6),
            child: SizedBox(
              height: AppSize.tapMin,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.s10, vertical: AppSpace.s6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh,
                        size: AppSize.iconXs, color: t.primaryDark),
                    const SizedBox(width: AppSpace.s4),
                    Text(
                      '重试',
                      style: TextStyle(
                        fontSize: AppType.xs,
                        color: t.primaryDark,
                        fontWeight: AppWeight.medium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 单边 loading 小字 (④) ──
  //
  // 条件: 一边已回数据 + 另一边 loading 且其为空 + 其未被 filter 排除
  List<Widget> _inlineLoadingRows({
    required AsyncValue<List<WellnessRecord>> wellness,
    required AsyncValue<List<Interaction>> interactions,
    required _Filter filter,
  }) {
    final out = <Widget>[];
    final showWellness = filter == _Filter.all || filter == _Filter.wellness;
    final showInteractions =
        filter == _Filter.all || filter == _Filter.interaction;
    final wellnessEmpty = wellness.valueOrNull == null ||
        wellness.valueOrNull!.isEmpty;
    final interactionsEmpty = interactions.valueOrNull == null ||
        interactions.valueOrNull!.isEmpty;
    if (showWellness && wellness.isLoading && wellnessEmpty) {
      out.add(_inlineLoadingLine('养生记录加载中…'));
    }
    if (showInteractions && interactions.isLoading && interactionsEmpty) {
      out.add(_inlineLoadingLine('互动加载中…'));
    }
    return out;
  }

  Widget _inlineLoadingLine(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.pagePadding, AppSpace.s6, AppSpace.pagePadding, AppSpace.s6),
      child: Row(
        children: [
          const SizedBox(
            width: AppType.xs + 2,
            height: AppType.xs + 2,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          ),
          const SizedBox(width: AppSpace.s8),
          Text(
            text,
            style: const TextStyle(
              fontSize: AppType.xs,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  // ── 加载更多 footer (⑤) ──
  //
  // 三种形态:
  //   · 总数 > visibleCount → 「加载更多（还有 N 条）」按钮 (热区 ≥48)
  //   · 都显示完 + wellness.length == 50 → 「养生记录较多, 当前仅加载最近 50 条」
  //   · 否则不显示
  Widget _loadMoreFooter({
    required int timelineTotal,
    required int visibleCount,
    required VoidCallback onLoadMore,
    required bool wellnessLoadedAtCap,
  }) {
    if (timelineTotal > visibleCount) {
      final remaining = timelineTotal - visibleCount;
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.pagePadding,
          AppSpace.s6,
          AppSpace.pagePadding,
          AppSpace.s10,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: onLoadMore,
            borderRadius: BorderRadius.circular(AppRadius.r6),
            child: SizedBox(
              height: AppSize.tapMin,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.s8, vertical: AppSpace.s4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '加载更多（还有 $remaining 条）',
                      style: TextStyle(
                        fontSize: AppType.xs,
                        color: context.tokens.primaryDark,
                        fontWeight: AppWeight.medium,
                      ),
                    ),
                    const SizedBox(width: AppSpace.s4),
                    Icon(Icons.expand_more,
                        size: AppSize.iconSm, color: context.tokens.primaryDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (wellnessLoadedAtCap) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.pagePadding,
          AppSpace.s6,
          AppSpace.pagePadding,
          AppSpace.s12,
        ),
        child: Text(
          '养生记录较多, 当前仅加载最近 50 条',
          style: const TextStyle(
            fontSize: AppType.xs,
            color: AppColors.textTertiary,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  // ── 单行 widget ──
  Widget _rowWidgetFor(_TimelineRow r, Dictionaries? dict,
      {bool showDivider = true}) {
    switch (r.kind) {
      case _Kind.wellness:
        final w = r.wellness!;
        final itemName = serviceItemName(dict, w.serviceItemId);
        final parts = bodyPartNames(dict, w.bodyPartIds).take(2).toList();
        final delta = metricDeltaSummary(w);
        // ⑥ 下次建议日期提示 (逾期片段染 AppColors.warning)
        final advice = adviceHint(w);
        final isOverdue = adviceOverdue(w);

        // 主副文拼接: 「MM-dd · 部位(≤2) · 疼痛 8→3 ↓5 · 建议 09-30 · 已过 3 天」
        //   —— 用 join(' · ') 拼一个**基础串**, 但已过 N 天要变红 → 单独 build。
        final baseParts = <String>[
          _formatDate(w.serviceDate),
          if (parts.isNotEmpty) parts.join('+'),
          if (delta.isNotEmpty) delta,
        ];
        final baseStr = baseParts.join(' · ');
        final subtitleText = (advice == null)
            ? baseStr
            : (baseStr.isEmpty ? advice : '$baseStr · $advice');

        final Widget subtitle;
        if (isOverdue && advice != null && baseStr.isNotEmpty) {
          // 渲染「基础 · 建议 MM-dd · 已过 N 天」, 已过 N 天 染 AppColors.warning
          final advicePrefix = advice.split('·').first.trim(); // "建议 MM-dd"
          final overdueSuffix = advice.split('·').last.trim(); // "已过 N 天"
          subtitle = Text.rich(
            TextSpan(children: [
              TextSpan(text: '$baseStr · $advicePrefix · '),
              TextSpan(
                text: overdueSuffix,
                style: const TextStyle(color: AppColors.warning),
              ),
            ]),
          );
        } else {
          subtitle = Text(subtitleText);
        }

        // ⑧ 照片指示: meta 显示相机图标 + 张数
        final photoCount = w.photos.length;
        final Widget? meta = photoCount > 0
            ? _photosMeta(photoCount)
            : null;

        return AppListRow(
          leading: _kindIcon(_Kind.wellness),
          title: Text(itemName ?? '养生记录'),
          subtitle: subtitle,
          meta: meta,
          onTap: () => context.push('/wellness-records/${w.id}'),
          dense: true,
          showDivider: showDivider,
        );
      case _Kind.interaction:
        final i = r.interaction!;
        final typeLabel = interactionTypeLabels[i.type] ?? i.type;
        final summary = i.summary?.trim() ?? '';
        final subtitleParts = <String>[
          _formatDate(i.createdAt.toLocal().toIso8601String().split('T').first),
          if (summary.isNotEmpty) summary,
        ];
        return AppListRow(
          leading: _kindIcon(_Kind.interaction, typeKey: i.type),
          title: Text(typeLabel),
          subtitle: Text(subtitleParts.join(' · '),
              maxLines: 2),
          onTap: null,
          dense: true,
          showDivider: showDivider,
        );
    }
  }

  // ── 行内图标 ──
  Widget _kindIcon(_Kind k, {String? typeKey}) {
    IconData icon;
    Color bg;
    Color fg;
    switch (k) {
      case _Kind.wellness:
        icon = Icons.spa_outlined;
        bg = AppColors.surfaceSubtle;
        fg = AppPalette.amber500;
        break;
      case _Kind.interaction:
        icon = _iconForInteraction(typeKey);
        bg = AppColors.surfaceSubtle;
        fg = AppColors.textSecondary;
        break;
    }
    return Container(
      width: AppSize.avatarMd,
      height: AppSize.avatarMd,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.r10),
      ),
      child: Icon(icon, size: AppSize.iconMd, color: fg),
    );
  }

  // ── ⑧ 照片 meta (相机图标 + 张数) ──
  //
  // 用 Material Icons.photo_camera_outlined (实心图标, tokens 化的尺寸/颜色);
  // 与 AppListRow 默认 meta (sm + textTertiary) 同节奏, 但内嵌图标颜色更明显。
  Widget _photosMeta(int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.photo_camera_outlined,
          size: AppSize.iconXs,
          color: AppColors.textTertiary,
        ),
        const SizedBox(width: AppSpace.s2),
        Text(
          '$count',
          style: const TextStyle(
            fontSize: AppType.sm,
            color: AppColors.textTertiary,
          ),
        ),
      ],
    );
  }

  // ── 汇总行 — ⑦ 相对时间「最近一次 今天/昨天/N 天前」 ──
  String _summaryLine(List<WellnessRecord> records) {
    if (records.isEmpty) return '';
    // ⑦ 取**最新**一条 (serviceDate 倒序); provider 未必排序, 主动找一下
    final sorted = [...records]
      ..sort((a, b) => (DateTime.tryParse(b.serviceDate) ?? b.createdAt)
          .compareTo(DateTime.tryParse(a.serviceDate) ?? a.createdAt));
    final last = sorted.first.serviceDate;
    final relLabel = relativeDayLabel(last);
    final lastDisplay = relLabel.isEmpty ? last : relLabel;

    final parts = <String>['共 ${records.length} 次', '最近一次 $lastDisplay'];

    if (records.length >= 2) {
      final days = records
          .map((r) => DateTime.tryParse(r.serviceDate))
          .whereType<DateTime>()
          .toList()
        ..sort();
      if (days.length >= 2) {
        var sum = 0;
        var n = 0;
        for (var i = 1; i < days.length; i++) {
          final d = days[i].difference(days[i - 1]).inDays;
          if (d >= 0) {
            sum += d;
            n++;
          }
        }
        if (n > 0) parts.add('平均 ${(sum / n).round()} 天一次');
      }
    }
    return parts.join(' · ');
  }

  // ── ① 空态 (按过滤给不同文案 + actions) ──
  //
  // 设计: AppEmptyState (B 档统一空态), 无装饰条/图标前缀, 原则 8「下一步做什么」;
  //   · filter=all    → icon history, action 「记一条养生记录」+ secondary「记一笔联系」
  //   · filter=wellness → action 「记第一条养生记录」
  //   · filter=interaction → action 「记一笔联系」
  Widget _emptyStateFor(_Filter f) {
    switch (f) {
      case _Filter.all:
        return AppEmptyState(
          icon: Icons.history,
          title: '还没有记录',
          hint: '记录每一次到店和联系, 跟进更有依据',
          action: FilledButton(
            onPressed: _goNewWellnessRecord,
            child: const Text('记一条养生记录'),
          ),
          secondaryAction: TextButton(
            onPressed: _goNewInteraction,
            child: const Text('记一笔联系'),
          ),
        );
      case _Filter.wellness:
        return AppEmptyState(
          icon: Icons.spa_outlined,
          title: '还没有养生记录',
          hint: '第一次到店记下来, 后续变化一目了然',
          action: FilledButton(
            onPressed: _goNewWellnessRecord,
            child: const Text('记第一条养生记录'),
          ),
        );
      case _Filter.interaction:
        return AppEmptyState(
          icon: Icons.phone_in_talk_outlined,
          title: '还没记过联系',
          hint: '每次电话 / 微信 / 到店都记一笔, 跟进节奏更稳',
          action: FilledButton(
            onPressed: _goNewInteraction,
            child: const Text('记一笔联系'),
          ),
        );
    }
  }

  void _goNewWellnessRecord() {
    if (!mounted) return;
    if (!context.mounted) return;
    context.push('/wellness-records/new?customerId=${widget.customerId}');
  }

  void _goNewInteraction() {
    if (!mounted) return;
    if (!context.mounted) return;
    showAddInteractionSheet(context, ref, customerId: widget.customerId);
  }

  // ── ⑨ 日期分组头 (纯文字小标题, 无装饰条/色块/图标) ──
  Widget _groupHeader(TimelineBucket bucket) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.pagePadding,
        AppSpace.s10,
        AppSpace.pagePadding,
        AppSpace.s4,
      ),
      child: Text(
        bucketLabel(bucket),
        style: const TextStyle(
          fontSize: AppType.xs,
          color: AppColors.textTertiary,
          fontWeight: AppWeight.medium,
        ),
      ),
    );
  }
}

// ============================================
// 内部类型 (仅本文件用)
// ============================================

enum _Filter { all, wellness, interaction }

extension on _Filter {
  String get label => switch (this) {
        _Filter.all => '全部记录',
        _Filter.wellness => '养生记录',
        _Filter.interaction => '互动记录',
      };
}

/// 添加记录菜单项
enum _AddAction { wellness, interaction }

enum _Kind { wellness, interaction }

class _TimelineRow {
  final _Kind kind;
  final WellnessRecord? wellness;
  final Interaction? interaction;
  final DateTime sortKey; // 时间线排序键
  final String? dateYmd; // YYYY-MM-DD (用于分组)

  _TimelineRow.wellness(WellnessRecord w)
      : kind = _Kind.wellness,
        interaction = null,
        wellness = w,
        sortKey = DateTime.tryParse(w.serviceDate) ?? w.createdAt.toLocal(),
        dateYmd = w.serviceDate;

  _TimelineRow.interaction(Interaction i)
      : kind = _Kind.interaction,
        wellness = null,
        interaction = i,
        sortKey = i.createdAt.toLocal(),
        dateYmd = i.createdAt.toLocal().toIso8601String().split('T').first;
}

/// ⑨ 分组结果 — 一个桶 + 桶内行
class _GroupedRows {
  final TimelineBucket bucket;
  final List<_TimelineRow> rows;
  const _GroupedRows(this.bucket, this.rows);
}

/// ⑨ 按日期分组 (按桶顺序 today→...→earlier; 桶内保持原时间倒序)
List<_GroupedRows> _groupTimeline(List<_TimelineRow> rows) {
  final grouped = <TimelineBucket, List<_TimelineRow>>{
    for (final b in kBucketOrderDesc) b: <_TimelineRow>[],
  };
  for (final r in rows) {
    grouped[bucketOf(r.dateYmd)]!.add(r);
  }
  return <_GroupedRows>[
    for (final b in kBucketOrderDesc)
      if (grouped[b]!.isNotEmpty) _GroupedRows(b, grouped[b]!),
  ];
}

/// 混合 + 过滤 + 排序 (纯函数, 容易单测)
List<_TimelineRow> _buildTimeline({
  required List<WellnessRecord> wellness,
  required List<Interaction> interactions,
  required _Filter filter,
}) {
  final list = <_TimelineRow>[];
  if (filter == _Filter.all || filter == _Filter.wellness) {
    for (final w in wellness) {
      list.add(_TimelineRow.wellness(w));
    }
  }
  if (filter == _Filter.all || filter == _Filter.interaction) {
    for (final i in interactions) {
      list.add(_TimelineRow.interaction(i));
    }
  }
  list.sort((a, b) => b.sortKey.compareTo(a.sortKey));
  return list;
}

/// 互动类型 → 图标 (与 interactionTypeLabels 同字段)
IconData _iconForInteraction(String? typeKey) {
  switch (typeKey) {
    case 'phone':
      return Icons.phone;
    case 'wechat':
      return Icons.chat;
    case 'visit':
      return Icons.storefront;
    case 'holiday_greeting':
      return Icons.card_giftcard;
    default:
      return Icons.more_horiz;
  }
}

/// 「YYYY-MM-DD」 → 「MM-dd」 (副文里省 5 个字符)
String _formatDate(String serviceDate) {
  final d = DateTime.tryParse(serviceDate);
  if (d == null) return serviceDate;
  return DateFormat('MM-dd').format(d);
}