// ============================================
// 客户详情 · 「记录」Tab 时间线混合列表 (2026-09-24 拍板重构)
//
// 主人诉求:
//   「养生记录和互动记录混合列表展示(养生记录条目优化得更紧凑),
//     以胶囊键切换展示全部或仅养生记录、互动记录。
//     添加养生记录、添加联系记录两个按键展示在混合列表上方。」
//
// 设计要点 (docs/ui-principles.md 原则 1 密度 + 原则 4 容器越少):
//   - 列表行用 `AppListRow(dense: true)` 契约组件 (B 档统一行)
//   - 整个混合列表包在 **一个** B2NoChrome 容器里 (避免「每行都套卡片」反 vibe)
//   - 两个添加按钮 + 胶囊 + 汇总行 **不放**进容器 (容器越少, 内容越强)
//   - 健壮性: 养生 / 互动两边 provider 各自 loading/error 时**互不遮蔽** ——
//     valueOrNull 合并, 一边空另一边仍可见, 全空才显示错误 / 骨架
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 添加按钮 (Row + 2 Expanded, 不放进 B2NoChrome 容器) ──
        _addButtonsRow(context),
        const SizedBox(height: AppSpace.s10),
        // ── 养生汇总行 (fontXs, 信息不丢) ──
        if (summary.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.pagePadding),
            child: Text(
              summary,
              style: const TextStyle(
                fontSize: AppType.xs,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        const SizedBox(height: AppSpace.s10),
        // ── 胶囊过滤 (全部 / 养生记录 / 互动记录) ──
        _filterChips(),
        const SizedBox(height: AppSpace.s10),
        // ── 混合列表 (单 B2NoChrome 容器, 行用 AppListRow dense) ──
        B2NoChrome(
          margin: const EdgeInsets.only(bottom: AppSpace.s12),
          child: _timelineList(
              dict: dict,
              timeline: timeline,
              totalWellness: wellness.length,
              totalInteractions: interactions.length,
              bothLoading: asyncWellness.isLoading && asyncInteractions.isLoading,
              firstError: asyncWellness.hasError
                  ? asyncWellness.error.toString()
                  : (asyncInteractions.hasError
                      ? asyncInteractions.error.toString()
                      : null)),
        ),
      ],
    );
  }

  // ── 两个添加按钮 (养生 / 联系) ──
  Widget _addButtonsRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            // 主按钮 (FilledButton) — 「添加养生记录」
            onPressed: () => context.push(
                '/wellness-records/new?customerId=${widget.customerId}'),
            icon: const Icon(Icons.favorite, size: AppSize.iconMd),
            label: const Text('添加养生记录'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonLgHeight),
              textStyle: const TextStyle(fontSize: AppType.sm),
            ),
          ),
        ),
        const SizedBox(width: AppSpace.s8),
        Expanded(
          child: FilledButton.tonalIcon(
            // 次按钮 (FilledButton.tonal) — 「添加联系记录」
            //   复用「完成跟进」弹层 (D, 在 complete_follow_up_sheet.dart 内),
            //   标题「添加联系记录」, 按钮「保存」
            onPressed: () => showAddInteractionSheet(context, ref,
                customerId: widget.customerId),
            icon: const Icon(Icons.phone_in_talk, size: AppSize.iconMd),
            label: const Text('添加联系记录'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, AppSize.buttonLgHeight),
              textStyle: const TextStyle(fontSize: AppType.sm),
            ),
          ),
        ),
      ],
    );
  }

  // ── 胶囊过滤 ──
  Widget _filterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.pagePadding),
      child: Wrap(
        spacing: AppSpace.s8,
        children: _Filter.values
            .map((f) => ChoiceChip(
                  label: Text(f.label,
                      style: const TextStyle(fontSize: AppType.sm)),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ))
            .toList(),
      ),
    );
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
        _Filter.all => '全部',
        _Filter.wellness => '养生记录',
        _Filter.interaction => '互动记录',
      };
}

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