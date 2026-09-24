// ============================================
// 客户详情 · 「记录」Tab 时间线混合列表 (2026-09-24 拍板重构)
//
// 主人诉求:
//   「养生记录和互动记录混合列表展示(养生记录条目优化得更紧凑),
//     以胶囊键切换展示全部或仅养生记录、互动记录。
//     添加养生记录、添加联系记录两个按键展示在混合列表上方。」
//
// ⏵ 2026-09-24 续拍 (本 commit):
//   「记录列表内容选择标签(全部、养生、互动)折叠为下拉选择框。
//     内容选择框的右侧显示添加记录键, 点击下拉框选择添加养生记录或添加联系记录。」
//   ⇒ 把上面两个诉求合并成一行工具栏:
//      左 = 内容选择下拉 (PopupMenuButton), 右 = 添加记录下拉 (PopupMenuButton)
//   ⇒ 删掉「两个整宽按钮行」+「三个 ChoiceChip 行」, 改用一行 Row + Spacer
//   ⇒ 文字 / 颜色 / 字号 / 间距 / 圆角 一律走 tokens (不写 hex, 不引用 AppTheme.xxx 常量色)
//
// 设计要点 (docs/ui-principles.md 原则 1 密度 + 原则 4 容器越少):
//   - 列表行用 `AppListRow(dense: true)` 契约组件 (B 档统一行)
//   - 整个混合列表包在 **一个** B2NoChrome 容器里 (避免「每行都套卡片」反 vibe)
//   - 工具栏 (两下拉) + 汇总行 **不放**进容器 (容器越少, 内容越强)
//   - 健壮性: 养生 / 互动两边 provider 各自 loading/error 时**互不遮蔽** ——
//     valueOrNull 合并, 一边空另一边仍可见, 全空才显示错误 / 骨架
//   - 触摸区: 下拉按钮高度 = AppSize.controlLg (44) —— 中老年友好, 满足 tapMin/tapCompact
//
// 数据来源 (与旧 customer_activity_cards 同 provider, 不另起):
//   - 养生: customerWellnessRecordsProvider(customerId)   (limit=50, 按 serviceDate 倒序)
//   - 互动: interactionsForCustomerProvider(customerId)  (按 createdAt 倒序)
// ─────────────────────────────────────────────────────

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
import '../../../core/widgets/app_list_row.dart';
import '../../../core/widgets/b2_no_chrome.dart';
import '../../follow_up/widgets/complete_follow_up_sheet.dart' show showAddInteractionSheet;
import 'record_format.dart';

// ============================================
// 主 widget — 「时间线」 section
// ============================================

class CustomerTimelineSection extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerTimelineSection({super.key, required this.customerId});

  @override
  ConsumerState<CustomerTimelineSection> createState() =>
      _CustomerTimelineSectionState();
}

class _CustomerTimelineSectionState
    extends ConsumerState<CustomerTimelineSection> {
  /// 过滤胶囊: 全部 / 养生 / 互动 (默认「全部」, 主人诉求)
  _Filter _filter = _Filter.all;

  /// 截断上限 (最多展示 20 条; 超出在列表底部一行小字提示)
  static const int _maxRows = 20;

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

    // 2) 合并 + 排序 (按时间倒序) + 截断 20
    final timeline = _buildTimeline(
      wellness: wellness,
      interactions: interactions,
      filter: _filter,
      maxRows: _maxRows,
    );

    // 2026-09-24 主人诉求 (第二版):
    //   ① 「筛选和添加键与列表要整体卡片化」—— 之前工具栏/汇总在卡片外, 视觉隔离
    //   ② 「记录列表表头不要随列表上滑而隐藏」—— 表头必须固定, 只有列表滚
    //   ⇒ 结构 = **一张卡片**: 固定表头 (工具栏 + 汇总 + 分隔线) + 内部可滚列表。
    final list = _timelineList(
        dict: dict,
        timeline: timeline,
        totalWellness: wellness.length,
        totalInteractions: interactions.length,
        bothLoading: asyncWellness.isLoading && asyncInteractions.isLoading,
        firstError: asyncWellness.hasError
            ? asyncWellness.error.toString()
            : (asyncInteractions.hasError
                ? asyncInteractions.error.toString()
                : null));

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
            Text(
              summary,
              style: const TextStyle(
                fontSize: AppType.xs,
                color: AppColors.textTertiary,
              ),
            ),
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
    // ⚠ 不再自带横向 padding —— 本行现在在卡片表头的 Padding 里,
    //   再自己加一层会跟卡片内边距叠加 (旧版正是这样, 工具栏比列表多缩进 16px,
    //   视觉上"隔离"; 主人 2026-09-24 指出要整体卡片化)。
    return Row(
      children: [
        // ── 左: 内容选择下拉 (act 模式: open menu 选中切换过滤) ──
        PopupMenuButton<_Filter>(
          // 锁 key: 测试与外层 `find.byKey('timelineFilterDropdown')` 共用
          key: const ValueKey('timelineFilterDropdown'),
          tooltip: '',
          onSelected: (f) => setState(() => _filter = f),
          position: PopupMenuPosition.under,
          itemBuilder: (ctx) => _Filter.values
              .map((f) => PopupMenuItem<_Filter>(
                    value: f,
                    height: AppSize.controlLg,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 当前选中项前打钩 (语义视觉, 不是颜色信号)
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
  //
  // 高度 ≥ AppSize.controlLg (44), 圆角 AppRadius.r10, 边框 t.divider;
  // 横向内边距 AppSpace.s12, 垂直 s8 (文字 sm 居中)。
  // 为什么不直接套 PopupMenuButton 默认 Icon(more_vert) —— 默认箭头/图标不够清晰;
  // 自己 child 才能精确控制「当前值 + 箭头」复合表达。
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
  //
  // FilledButton.tonal 观感: 背景 = 主题 primarySurface (浅绿), 文字 primaryDark;
  // 实现方式 = Container + 主品牌色背景 + InkWell。
  // 为什么不直接用 FilledButton.tonal 再叠 Icon: 高度/圆角/箭头都对不齐 (FilledButton 默认 40 高 + 字面箭头渲染固定) 。
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
  //
  // 风格: 左侧图标 (颜色 t.textSecondary) + 文字 (t.textPrimary / sm);
  // 与右按钮同高度 (controlLg) 保持整页节奏一致。
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
  //
  // 菜单关闭后才走 onSelected, 此时 context 仍是 widget 的 context (mounted 大概率还是 true) 。
  // push 是异步 (Future 后仍可能在 navigator 里), 但导航是同步发起, 不会因页面销毁崩;
  // 安全保险: push 前再 `if (context.mounted)`, showAddInteractionSheet 不需要 (showModalBottomSheet 内部检测)。
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

  // ── 列表主体 ──
  Widget _timelineList({
    required Dictionaries? dict,
    required List<_TimelineRow> timeline,
    required int totalWellness,
    required int totalInteractions,
    required bool bothLoading,
    required String? firstError,
  }) {
    // 错误优先 (任一边出错且**自己那份**为空 → 错也含蓄, 不让另一边的数据也被藏掉)
    if (firstError != null && timeline.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Text(
          '加载失败: $firstError',
          style: const TextStyle(color: AppColors.danger, fontSize: AppType.sm),
        ),
      );
    }

    // 骨架 (两边都还在 loading 且**都没**数据 → 一行转圈 + 「加载中」)
    if (bothLoading && timeline.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Row(
          children: [
            const SizedBox(
              width: AppSpace.s18,
              height: AppSpace.s18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpace.s10),
            Text('加载记录中...',
                style: const TextStyle(
                    fontSize: AppType.sm, color: AppColors.textTertiary)),
          ],
        ),
      );
    }

    // 空态 (按当前过滤给不同文案)
    if (timeline.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Text(
          _emptyTextFor(_filter, totalWellness, totalInteractions),
          style: const TextStyle(
              fontSize: AppType.sm, color: AppColors.textTertiary),
        ),
      );
    }

    // 列表 (最后一行的分割线靠 AppListRow.showDivider 默认 true 自动处理;
    //   「共 N 条 · 只显示最近 20 条」单行小字也用 AppListRow 拼 trailing=meta
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < timeline.length; i++)
          _rowWidgetFor(timeline[i], dict,
              showDivider: i < timeline.length - 1),
        if (timeline.length >= _maxRows)
          _truncatedFooter(
            totalCount: timeline.length < _maxRows
                ? timeline.length
                : (_filter == _Filter.wellness
                    ? totalWellness
                    : _filter == _Filter.interaction
                        ? totalInteractions
                        : totalWellness + totalInteractions),
          ),
      ],
    );
  }

  // ── 单行 widget ──
  Widget _rowWidgetFor(_TimelineRow r, Dictionaries? dict,
      {bool showDivider = true}) {
    switch (r.kind) {
      case _Kind.wellness:
        final w = r.wellness!;
        final itemName = serviceItemName(dict, w.serviceItemId);
        // 部位最多 2 个 (与 _recordSummary 同口径, 副文一行能装下)
        final parts = bodyPartNames(dict, w.bodyPartIds).take(2).toList();
        final delta = metricDeltaSummary(w);
        // 「MM-dd · 部位(≤2) · 疼痛 8→3 ↓5」 —— 无指标则只到部位
        final subtitleParts = <String>[
          _formatDate(w.serviceDate),
          if (parts.isNotEmpty) parts.join('+'),
          if (delta.isNotEmpty) delta,
        ];
        return AppListRow(
          leading: _kindIcon(_Kind.wellness),
          title: Text(itemName ?? '养生记录'),
          subtitle: Text(subtitleParts.join(' · ')),
          onTap: () => context.push('/wellness-records/${w.id}'),
          dense: true,
          showDivider: showDivider,
        );
      case _Kind.interaction:
        final i = r.interaction!;
        final typeLabel = interactionTypeLabels[i.type] ?? i.type;
        final summary = i.summary?.trim() ?? '';
        // 「MM-dd · 内容」 —— 无内容只显示日期
        final subtitleParts = <String>[
          _formatDate(i.createdAt.toLocal().toIso8601String().split('T').first),
          if (summary.isNotEmpty) summary,
        ];
        // 互动行无详情页 → onTap = null (整行不可点; 但仍渲染, 用于只读列表)
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

  Widget _truncatedFooter({required int totalCount}) {
    // 「共 N 条 · 只显示最近 20 条」 —— 单行小字, 不与列表混排以免破坏行距
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.pagePadding, AppSpace.s8, AppSpace.pagePadding, AppSpace.s12),
      child: Text(
        '共 $totalCount 条 · 只显示最近 $_maxRows 条',
        style: const TextStyle(
            fontSize: AppType.xs, color: AppColors.textTertiary),
      ),
    );
  }

  // ── 行内图标 (固定 leading, 圆形浅底色块) ──
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
        // 互动类型分别取; 缺省 → 「其他」
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

  // ── 汇总行 ──
  String _summaryLine(List<WellnessRecord> records) {
    if (records.isEmpty) return '';
    final last = records.first.serviceDate;
    final parts = <String>['共 ${records.length} 次', '最近 $last'];

    if (records.length >= 2) {
      // 排序后算相邻差 (与 _buildWellnessSection 同口径)
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

  // ── 过滤后空态文案 ──
  String _emptyTextFor(_Filter f, int totalWellness, int totalInteractions) {
    switch (f) {
      case _Filter.all:
        return '还没有记录';
      case _Filter.wellness:
        return '还没有养生记录';
      case _Filter.interaction:
        return '还没记过联系';
    }
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

/// 添加记录菜单项 (主人诉求: 点击下拉框选择添加养生记录或添加联系记录)
enum _AddAction { wellness, interaction }

enum _Kind { wellness, interaction }

class _TimelineRow {
  final _Kind kind;
  final WellnessRecord? wellness;
  final Interaction? interaction;
  final DateTime sortKey; // 时间线排序键

  _TimelineRow.wellness(WellnessRecord w)
      : kind = _Kind.wellness,
        interaction = null,
        wellness = w,
        sortKey = DateTime.tryParse(w.serviceDate) ?? w.createdAt.toLocal();

  _TimelineRow.interaction(Interaction i)
      : kind = _Kind.interaction,
        wellness = null,
        interaction = i,
        sortKey = i.createdAt.toLocal();
}

/// 混合 + 过滤 + 排序 + 截断 (纯函数, 容易单测)
List<_TimelineRow> _buildTimeline({
  required List<WellnessRecord> wellness,
  required List<Interaction> interactions,
  required _Filter filter,
  required int maxRows,
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
  if (list.length > maxRows) return list.take(maxRows).toList();
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

/// 「YYYY-MM-DD」 → 「MM-dd」 (副文里省 5 个字符, 与旧版同口径)
String _formatDate(String serviceDate) {
  final d = DateTime.tryParse(serviceDate);
  if (d == null) return serviceDate;
  return DateFormat('MM-dd').format(d);
}