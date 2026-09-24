// ============================================
// 评分滑块 (Plan F2.5, 中老年大字版)
// 大字反馈 + 大触摸区 + 显示当前数值
// ============================================

import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

import '../../../core/theme/tokens.g.dart';
class RatingSlider extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final int? divisions;
  final String Function(int)? valueFormatter; // 数字 → 显示文本
  final ValueChanged<int> onChanged;

  /// 强调色 (数值徽章底 + 滑轨 / 滑块) —— 默认品牌主色 [AppTheme.primary]。
  /// 「理疗前 / 后」对比场景: 前 = 中性色 (已成过去), 后 = 主色 (这次结果);
  /// 差值语义交给旁边的 delta 徽章, 不靠滑块颜色重复表达。
  final Color? accent;

  const RatingSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 10,
    this.divisions,
    this.valueFormatter,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = valueFormatter != null ? valueFormatter!(value) : '$value';
    final accent = this.accent ?? AppTheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s6),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(AppRadius.r16),
              ),
              child: Text(
                displayValue,
                style: const TextStyle(
                  fontSize: AppTheme.fontLg,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 8,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 28),
            activeTrackColor: accent,
            inactiveTrackColor: accent.withOpacity(0.22),
            thumbColor: accent,
          ),
          child: Slider(
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: divisions ?? (max - min),
            value: value.toDouble(),
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }
}

/// 1-5 评分滑块 (情绪 / 睡眠)
class FiveRatingSlider extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final Color? accent;

  const FiveRatingSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return RatingSlider(
      label: label,
      value: value,
      min: 1,
      max: 5,
      valueFormatter: (v) => '$v/5',
      onChanged: onChanged,
      accent: accent,
    );
  }
}

/// 1-10 评分滑块 (疼痛程度, 1=不痛 10=剧痛)
class PainSlider extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  final Color? accent;

  const PainSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return RatingSlider(
      label: label,
      value: value,
      min: 1,
      max: 10,
      accent: accent,
      valueFormatter: (v) {
        if (v <= 3) return '$v 不痛';
        if (v <= 6) return '$v 有点痛';
        return '$v 剧痛';
      },
      onChanged: onChanged,
    );
  }
}