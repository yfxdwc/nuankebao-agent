import 'package:flutter/material.dart';

import '../../../core/models/dictionaries.dart';
import '../../../core/models/wellness_record.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';

// ============================================
// 养生记录卡片 (记录 Tab 列表项)
// ============================================
// 主人 2026-09-23「先完善记录页」。
//
// 为什么需要它 —— 原实现的记录卡片**标题每条都是「养生记录」**:
//
//     title:    '养生记录'
//     subtitle: '2026-09-22 · 挺舒服的, 下次还来'
//
// 也就是说: 列表里看**不出**哪次做了什么项目、做了哪个部位、做完有没有改善 ——
// 必须逐条点进明细页才知道。而销售看这个列表的动作是「扫一眼她做过什么 / 有没有用」,
// 扫不动的列表等于没有列表。
//
// 修法 = 把明细页里最有用的四样搬到卡片上:
//   ① 服务项目名 (肩颈经络理疗)   ← 靠字典把 serviceItemId 翻成名字
//   ② 部位 (肩颈 / 腰部)
//   ③ **前 → 后 改善对比** (疼痛 8 → 4 ↓4)   ← 这才是"有没有用"的直接答案
//   ④ 客户反馈 (保留, 截断)
//
// 故意不做的事:
//   - 不在卡片上放"编辑/删除"按钮: 列表要的是**扫读**, 动作收进明细页
//     (误触代价也低不了 —— 养生记录是健康数据, 删错要重录)
//   - 不显示产品用量 / 照片计数: 明细页有, 卡片放不下也不常用
// ============================================

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

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.s8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.s14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 项目名 + 日期 ──
              Row(
                children: [
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
                      // 字典没到 / id 查不到 → 回落旧文案 (宁可笼统, 不要显示 #12 这种)
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

              // ── 部位 ──
              if (parts.isNotEmpty) ...[
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

              // ── 前 → 后 改善 ──
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: AppSpace.s10),
                Wrap(
                  spacing: AppSpace.s8,
                  runSpacing: AppSpace.s6,
                  children: metrics.map((m) => _MetricChip(delta: m)).toList(),
                ),
              ],

              // ── 反馈 ──
              if (hasFeedback) ...[
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

/// serviceItemId → 项目名; 查不到返回 null (调用方决定回落文案)
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

/// bodyPartIds → 部位名 (按入参顺序; 查不到的丢掉, 不显示 #id)
List<String> bodyPartNames(Dictionaries? dict, List<String> ids) {
  if (dict == null || ids.isEmpty) return const [];
  final byId = {for (final b in dict.bodyParts) b.id: b.name};
  return [
    for (final id in ids)
      if ((byId[id] ?? '').trim().isNotEmpty) byId[id]!.trim(),
  ];
}

// ============================================
// 前 → 后 改善 (纯函数, 可单测)
// ============================================

/// 一项指标的对比结果
class MetricDelta {
  final String label; // 疼痛 / 睡眠 / 情绪
  final int? pre;
  final int? post;
  /// true = 数值越小越好 (疼痛); false = 数值越大越好 (睡眠 / 情绪)
  final bool lowerIsBetter;

  const MetricDelta({
    required this.label,
    required this.pre,
    required this.post,
    required this.lowerIsBetter,
  });

  /// 前后都有值才能算改善 (只填了一半 = 数据不全, 不猜)
  bool get isComplete => pre != null && post != null;

  /// 原始变化量 (post - pre)。正数 = 数值上升
  int? get rawDelta => isComplete ? post! - pre! : null;
  int? get absDelta => rawDelta?.abs();

  /// 有没有变好
  bool get isImprovement {
    final d = rawDelta;
    if (d == null || d == 0) return false;
    return lowerIsBetter ? d < 0 : d > 0;
  }

  /// 有没有变差
  bool get isWorsening {
    final d = rawDelta;
    if (d == null || d == 0) return false;
    return lowerIsBetter ? d > 0 : d < 0;
  }
}

/// 从记录里抽出要展示的指标对比
///
/// 口径与后端 `src/lib/customer/scoring.ts` 的 effect 维度一致:
///   pain_level 越小越好; sleep_quality / mood 越大越好 (0-10 量表)。
/// ⚠ 顺序在这里定死 (疼痛 → 睡眠 → 情绪): 疼痛是养生客户最主要的诉求,
///   排在前面销售一眼就看到。最多 2 项 —— 卡片要能扫读, 不是把明细页搬过来。
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
  // 只保留前后都填了的 (半截数据画出来是误导)
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

/// `疼痛 8 → 4 ↓4` —— 颜色表示**改善方向**, 不是数值方向
///
/// ⚠ 这里最容易做错: 疼痛从 8 降到 4 是**好事**(绿), 但显示的是"下降";
///   睡眠从 5 升到 7 也是好事(绿), 显示的是"上升"。
///   所以颜色必须按 `isImprovement` 判, 不能按箭头方向判。
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
        children: [
          Text(
            '${delta.label} ${delta.pre} → ${delta.post}',
            style: TextStyle(
              fontSize: AppTheme.fontXs,
              color: t.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AppSpace.s4),
          Text(
            arrow,
            style: TextStyle(
              fontSize: AppTheme.fontXs,
              fontWeight: FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
