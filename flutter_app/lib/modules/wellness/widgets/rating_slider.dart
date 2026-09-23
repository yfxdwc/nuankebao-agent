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

  const RatingSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 10,
    this.divisions,
    this.valueFormatter,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = valueFormatter != null ? valueFormatter!(value) : '$value';
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
                color: AppTheme.primary,
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
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: AppTheme.primaryLight,
            thumbColor: AppTheme.primary,
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

  const FiveRatingSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
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
    );
  }
}

/// 1-10 评分滑块 (疼痛程度, 1=不痛 10=剧痛)
class PainSlider extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  const PainSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return RatingSlider(
      label: label,
      value: value,
      min: 1,
      max: 10,
      valueFormatter: (v) {
        if (v <= 3) return '$v 不痛';
        if (v <= 6) return '$v 有点痛';
        return '$v 剧痛';
      },
      onChanged: onChanged,
    );
  }
}