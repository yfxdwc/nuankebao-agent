// ============================================
// 客户健康提示卡 (管理 Tab, 2026-09-24 建议 #9)
//
// 为什么独立成卡 (原来塞在大头像卡里):
//   · 过敏史/病史是**安全信息**, 跟"性别/年龄/头像提示"混在一起会被淹没;
//   · 做项目前先看到"她对什么过敏", 比看到头像重要得多 (同建议 #1:
//     还把它带进了「添加养生记录」页顶部);
//   · 没填时给一条轻提示 —— AI 话术 / 效果分析都要吃这两项 (数据完整性)。
//
// 颜色语义 (ui-principles 原则 5): 过敏 = accent 暖橙警示, 病史 = danger 红;
//   空态 = 中性灰 (不是错误, 别用红色吓人)。
// ============================================

import 'package:flutter/material.dart';

import '../../../core/models/customer.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';

class CustomerHealthCard extends StatelessWidget {
  const CustomerHealthCard({super.key, required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final allergy = customer.allergyHistory?.trim() ?? '';
    final disease = customer.diseaseHistory?.trim() ?? '';

    if (allergy.isEmpty && disease.isEmpty) {
      // 空态: 中性提示 (不是错误态; 不填也能用, 只是 AI / 效果分析会打折)
      return B2NoChrome(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.health_and_safety_outlined,
                  size: AppSize.iconMd, color: t.textTertiary),
              const SizedBox(width: AppSpace.s8),
              Expanded(
                child: Text(
                  '还没填健康信息 —— 补上过敏史 / 既往病史, 做项目和 AI 解读都用得上',
                  style: TextStyle(fontSize: AppType.sm, color: t.textSecondary),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (allergy.isNotEmpty)
          _HealthAlertBox(
            icon: Icons.warning_amber_rounded,
            label: '过敏史',
            body: allergy,
            bg: t.accentSurfaceWarm,
            border: t.accent,
            fg: t.textPrimary,
            iconColor: t.accent,
          ),
        if (allergy.isNotEmpty && disease.isNotEmpty)
          const SizedBox(height: AppSpace.s8),
        if (disease.isNotEmpty)
          _HealthAlertBox(
            icon: Icons.medical_information_outlined,
            label: '既往病史',
            body: disease,
            bg: t.dangerSurface,
            border: t.danger,
            fg: t.textPrimary,
            iconColor: t.danger,
          ),
      ],
    );
  }
}

class _HealthAlertBox extends StatelessWidget {
  const _HealthAlertBox({
    required this.icon,
    required this.label,
    required this.body,
    required this.bg,
    required this.border,
    required this.fg,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final String body;
  final Color bg;
  final Color border;
  final Color fg;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.s12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.r10),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: AppSize.iconMd, color: iconColor),
          const SizedBox(width: AppSpace.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppType.xs,
                    fontWeight: AppWeight.semibold,
                    color: iconColor,
                  ),
                ),
                const SizedBox(height: AppSpace.s2),
                Text(
                  body,
                  style: TextStyle(fontSize: AppType.sm, color: fg, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
