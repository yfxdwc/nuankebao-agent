// ============================================
// 字号档位选择 chips —— 「我的」+「设置」两页共用 (单行布局)
// ============================================
// 提取原因: 字号 chip 必须**两处行为一致**。两处单独写 = 必然漂一份。
//   把"按档位缩放的标签字号"集中到这里一份, 颜色交给 chipTheme.labelStyle.color
//   (主主人 2026-09-22 真机 chip 白字事故防线 —— 见 app_theme.dart chipTheme 注释)。
//
// 2026-09-25 主人追加要求: 4 档必须**排在同一行** (新行 / 换行 = 不合格):
//   - Row + 4 个 Expanded 均分宽
//   - 间距 8 (用 SizedBox; Flutter 3.24 Row 没有 spacing 参数)
//   - label 字号仍按档位自己缩放 (给用户预览), 但**单行不裁字**:
//     Text(maxLines:1, overflow:ellipsis, textAlign:center) + FittedBox(scaleDown) 兜底
//   - 不允许过度缩小点击热区 (中年用户); ChoiceChip 自身 Material 触摸区 ≈ 48,
//     Expanded 等分后单 chip ≈ (屏宽-2*16-3*8)/4 ≈ 76px, 触摸区够用
//   - 硬性验收 393 + 320 窄屏 + 特大字号档位: 4 chip dy 相同 + 不溢出 + 不裁字
//
// 历史 (2026-09-22 → 2026-09-25): 原 _DisplaySettingsCardState.build 内的 ChoiceChip。
//   等价搬运: 仅把实现抽成共享 widget, 不改任何一个属性。
//
// 行为: 用户切档 → onChanged(v) → 调用方写 settingsProvider (持久化到 prefs)。
//
// 用法:
//   ```dart
//   FontSizePicker(
//     selected: ref.watch(settingsProvider).fontSize,
//     onChanged: (v) => ref.read(settingsProvider.notifier).setFontSize(v),
//   );
//   ```

import 'package:flutter/material.dart';

import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.g.dart';

class FontSizePicker extends StatelessWidget {
  const FontSizePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AppFontSize selected;
  final ValueChanged<AppFontSize> onChanged;

  @override
  Widget build(BuildContext context) {
    final values = AppFontSize.values;
    return Row(
      // Row children 必填 5 项: [SizedBox(s8), Expanded, SizedBox(s8), Expanded, ...]
      // 这里用 for + if 简洁展开; spacing 走 AppSpace 令牌 (硬编码护栏)
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpace.s8),
          Expanded(
            child: _buildChip(values[i]),
          ),
        ],
      ],
    );
  }

  Widget _buildChip(AppFontSize v) {
    return ChoiceChip(
      label: SizedBox(
        // 兜底高宽: chip 触摸区 ≥ 48 (中老年标准); Expanded 已经约束宽
        width: double.infinity,
        child: Center(
          child: FittedBox(
            // ⚠ 关键防线: 不裁字。FittedBox + scaleDown 让"特大"在窄屏/小屏
            //   也能完整显示, 而不是溢出被 ellipsis 吃掉 ("特大" 两字没了变 "...")
            fit: BoxFit.scaleDown,
            child: Text(
              v.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              // ⚠ color **不**在这里显式设 —— 由 chipTheme.labelStyle.color
              //   (AppTheme.light() → textPrimary) 提供。详见 chipTheme 注释
              //   + chip_label_color_test.dart (主人 2026-09-22 真机白字事故防线)。
              style: TextStyle(
                // 档位名自己就体现大小 (小 < 标准 < 大 < 特大), 不让用户看倍率数字
                fontSize: AppTheme.fontMd +
                    switch (v) {
                      AppFontSize.small => -2,
                      AppFontSize.standard => 0,
                      AppFontSize.large => 2,
                      AppFontSize.xlarge => 4,
                    },
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      selected: selected == v,
      onSelected: (_) => onChanged(v),
    );
  }
}
