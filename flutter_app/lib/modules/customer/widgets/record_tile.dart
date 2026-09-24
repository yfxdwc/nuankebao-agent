// ============================================
// 养生记录卡片 (B2 换装, 2026-09-25)
//
//   旧 B2NoChrome(margin/elevation) → Container + 无边框 + tokens.surfaceSubtle 浅底
//   渲染逻辑 / 颜色语义 / 测试断言 (find.byType(RecordTile)) 完全保留
// ============================================

import 'package:flutter/material.dart';

import '../../../core/models/dictionaries.dart';
import '../../../core/models/wellness_record.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';

class RecordTile extends StatelessWidget {
  final WellnessRecord record;
  /// 字典 (服务项目 / 部位名)。为 null = 还没加载完 → 只显示 ID, 不阻塞列表渲染
  final Dictionaries? dict;
  final VoidCallback? onTap;

  const RecordTile({
    super.key,
    required this.record,
    this.dict,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final itemName = serviceItemName(dict, record.serviceItemId);
    final parts = bodyPartNames(dict, record.bodyPartIds);
    final metrics = metricDeltas(record);
    final feedback = record.customerFeedback?.trim();
    final hasFeedback = feedback != null && feedback.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.s14),
          decoration: BoxDecoration(
            color: t.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // ── 项目名 + 日期 ──
              Row(
                children: <Widget>[
                  Container(
                    width: AppSpace.s32,
                    height: AppSpace.s32,
                    decoration: BoxDecoration(
                      color: t.accentSurface,
                      borderRadius: BorderRadius.circular(AppRadius.r10),
                    ),
                    child: Icon(Icons.spa_outlined,
                        size: AppSize.iconMd, color: t.accent),
                  ),
                  const SizedBox(width: AppSpace.s10),
                  Expanded(
                    child: Text(
                      itemName ?? '养生记录',
                      style: TextStyle(
                        fontSize: AppTheme.fontMd,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpace.s6),
                  Text(
                    record.serviceDate,
                    style: TextStyle(
                      fontSize: AppTheme.fontXs,
                      color: t.textTertiary,
                    ),
                  ),
                ],
              ),

              if (parts.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpace.s8),
                Wrap(
                  spacing: AppSpace.s6,
                  runSpacing: AppSpace.s4,
                  children: parts
                      .take(4)
                      .map((name) => _Tag(text: name))
                      .toList(),
                ),
              ],

              if (metrics.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpace.s10),
                Wrap(
                  spacing: AppSpace.s8,
                  runSpacing: AppSpace.s6,
                  children:
                      metrics.map((m) => _MetricChip(delta: m)).toList(),
                ),
              ],

              if (hasFeedback) ...<Widget>[
                const SizedBox(height: AppSpace.s8),
                Text(
                  feedback,
                  style: TextStyle(
                    fontSize: AppTheme.fontSm,
                    color: t.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================
// 字典翻译 (纯函数, 可单测)
// ============================================

String? serviceItemName(Dictionaries? dict, String id) {
  if (dict == null) return null;
  for (final s in dict.serviceItems) {
    if (s.id == id) {
      final n = s.name.trim();
      return n.isEmpty ? null : n;
    }
  }
  return null;
}

List<String> bodyPartNames(Dictionaries? dict, List<String> ids) {
  if (dict == null || ids.isEmpty) return const [];
  final byId = {for (final b in dict.bodyParts) b.id: b.name};
  return <String>[
    for (final id in ids)
      if ((byId[id] ?? '').trim().isNotEmpty) byId[id]!.trim(),
  ];
}

// ============================================
// 前 → 后 改善 (纯函数, 可单测)
// ============================================

class MetricDelta {
  final String label;
  final int? pre;
  final int? post;
  final bool lowerIsBetter;

  const MetricDelta({
    required this.label,
    required this.pre,
    required this.post,
    required this.lowerIsBetter,
  });

  bool get isComplete => pre != null && post != null;
  int? get rawDelta => isComplete ? post! - pre! : null;
  int? get absDelta => rawDelta?.abs();

  bool get isImprovement {
    final d = rawDelta;
    if (d == null || d == 0) return false;
    return lowerIsBetter ? d < 0 : d > 0;
  }

  bool get isWorsening {
    final d = rawDelta;
    if (d == null || d == 0) return false;
    return lowerIsBetter ? d > 0 : d < 0;
  }
}

List<MetricDelta> metricDeltas(WellnessRecord r, {int max = 2}) {
  final all = <MetricDelta>[
    MetricDelta(
      label: '疼痛',
      pre: _intOf(r.preCondition['pain_level']),
      post: _intOf(r.postCondition['pain_level']),
      lowerIsBetter: true,
    ),
    MetricDelta(
      label: '睡眠',
      pre: _intOf(r.preCondition['sleep_quality']),
      post: _intOf(r.postCondition['sleep_quality']),
      lowerIsBetter: false,
    ),
    MetricDelta(
      label: '情绪',
      pre: _intOf(r.preCondition['mood']),
      post: _intOf(r.postCondition['mood']),
      lowerIsBetter: false,
    ),
  ];
  return all.where((m) => m.isComplete).take(max).toList();
}

int? _intOf(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

// ============================================
// 展示部件
// ============================================

class _Tag extends StatelessWidget {
  final String text;
  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s8, vertical: AppSpace.s2),
      decoration: BoxDecoration(
        color: t.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.r4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: AppTheme.fontXs, color: t.textSecondary),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final MetricDelta delta;
  const _MetricChip({required this.delta});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = delta.isImprovement
        ? t.success
        : delta.isWorsening
            ? t.warning
            : t.textTertiary;
    final bg = delta.isImprovement
        ? t.successSurface
        : delta.isWorsening
            ? t.warningSurface
            : t.surfaceSubtle;

    final d = delta.rawDelta ?? 0;
    final arrow = d == 0 ? '持平' : (d < 0 ? '↓${d.abs()}' : '↑$d');

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.s8, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.r4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${delta.label} ${delta.pre} → ${delta.post}',
            style: TextStyle(
              fontSize: AppTheme.fontXs,
              color: t.textPrimary,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AppSpace.s4),
          Text(
            arrow,
            style: TextStyle(
              fontSize: AppTheme.fontXs,
              fontWeight: FontWeight.w600,
              color: color,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
