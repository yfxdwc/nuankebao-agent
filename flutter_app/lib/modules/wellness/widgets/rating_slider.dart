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

  /// 紧凑模式 (2026-09-24, 主人: 「文字、进度条、数字整合到一行」):
  ///   一行 = 标签 (前/后) + 滑轨 + 数字; 用于「理疗前 → 后」对比卡 (6 个滑块叠着摆)。
  ///   false (默认) = 原来的两行式 (标题行 + 大号数值徽章 + 第二行滑轨), 其它调用方不受影响。
  final bool compact;

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
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final displayValue = valueFormatter != null ? valueFormatter!(value) : '$value';
    final accent = this.accent ?? AppTheme.primary;

    if (compact) {
      // 一行式: [标签] [滑轨 flex] [数字] —— 滑轨缩到 40pt 高 (拇指 24 / 轨道 6),
      //   仍保留 ≥40pt 的触摸带 (整条滑轨可点可拖, 不是只有拇指能抓)。
      return Row(
        children: [
          SizedBox(
            width: AppSpace.s20,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.s4),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
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
          ),
          const SizedBox(width: AppSpace.s6),
          SizedBox(
            // 固定宽度 = 6 行滑块**对齐** (数字长短不同会让滑轨宽度抖动);
            // 走令牌而非字面量 (护栏 flutter.spacing 不许新硬编码)
            width: AppSpace.s64,
            child: Text(
              displayValue,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                fontWeight: FontWeight.w600,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      );
    }

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
  final bool compact;

  const FiveRatingSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.accent,
    this.compact = false,
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
      compact: compact,
    );
  }
}

/// 1-10 评分滑块 (疼痛程度, 1=不痛 10=剧痛)
class PainSlider extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  final Color? accent;
  final bool compact;

  const PainSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return RatingSlider(
      label: label,
      value: value,
      min: 1,
      max: 10,
      accent: accent,
      compact: compact,
      valueFormatter: (v) {
        if (v <= 3) return '$v 不痛';
        if (v <= 6) return '$v 有点痛';
        return '$v 剧痛';
      },
      onChanged: onChanged,
    );
  }
}