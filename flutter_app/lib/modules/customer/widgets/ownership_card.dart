import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/customer_ownership.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';

// ============================================
// 「归属」卡 (管理 Tab, P7, 主人 2026-09-23)
// ============================================
// 背景: 主人指出「管理维度相当粗糙」。核实后管理维度**唯一的真缺口就是归属** ——
//   编辑表单已覆盖 姓名/手机/生日/生日提醒/健康标签/病史/过敏/备注,
//   类型卡 + 身份卡也都在; 但**详情页看不到"这是谁的客户", 也没法认领**。
//
// 为什么这不是"锦上添花"而是缺一块:
//   `customer.owner_id` 是「谁的客户列表」的**唯一真相源** (ADR-0015 Q11),
//   客户列表 / 胶囊计数 / 图谱行级过滤全按它算。
//   一个没有 owner_id 的客户, 在任何人列表里都不是"我的客户" ——
//   而 L0 会弹行动「认领为我的客户」(那条目前是死路, 见 backlog 挂起项)。
//
// 设计取舍:
//   · **只做认领, 不做转移** —— 转移要改别人的归属, 涉及"先到先得要不要破例",
//     是产品决策 (ADR-0015 Q15), 不该由 agent 顺手实现。归属别人时明确说
//     "已被 X 先认领", 而不是给一个点了会 409 的按钮。
//   · **按钮可用性直接用后端的 canClaim** —— 不在这里重算规则。
//     口径只有一处 (getCustomerOwnership), UI 只是显示; 否则又是"两处判定迟早不一致"。
//   · 认领成功 → invalidate 归属 + 客户详情 + 客户列表; 归属变了这三处都会变。
// ============================================

class CustomerOwnershipCard extends ConsumerStatefulWidget {
  final String customerId;
  const CustomerOwnershipCard({super.key, required this.customerId});

  @override
  ConsumerState<CustomerOwnershipCard> createState() =>
      _CustomerOwnershipCardState();
}

class _CustomerOwnershipCardState
    extends ConsumerState<CustomerOwnershipCard> {
  bool _busy = false;

  Future<void> _claim() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(customerServiceProvider).claim(widget.customerId);
      // 归属变了 → 这三处都受影响 (归属卡自己 / 详情 / 列表的"我的客户"口径)
      ref.invalidate(customerOwnershipProvider(widget.customerId));
      ref.invalidate(customerDetailProvider(widget.customerId));
      ref.invalidate(customersProvider);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('已加为我的客户'),
        ),
      );
    } catch (e) {
      // 409/400 都有业务含义 (被别人抢先 / 是自己) —— 直接把后端的话给用户
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_humanError(e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final async = ref.watch(customerOwnershipProvider(widget.customerId));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.s16, AppSpace.s12, AppSpace.s16, AppSpace.s12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_pin_circle_outlined,
                    size: AppSize.iconMd, color: t.textSecondary),
                const SizedBox(width: AppSpace.s6),
                Text(
                  '归属',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpace.s8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
              error: (e, _) => Text(
                '归属读取失败: $e',
                style: TextStyle(fontSize: AppTheme.fontSm, color: t.danger),
              ),
              data: (o) => _body(context, o),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, CustomerOwnership o) {
    final t = context.tokens;

    // 状态色: 有归属(我的)=好 / 无归属=要处理 / 归属别人=不可动
    final (icon, color, bg) = o.hasNoOwner
        ? (Icons.error_outline, t.warning, t.warningSurface)
        : o.isMine
            ? (Icons.check_circle_outline, t.success, t.successSurface)
            : (Icons.lock_outline, t.textTertiary, t.surfaceSubtle);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpace.s10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.r8),
          ),
          child: Row(
            children: [
              Icon(icon, size: AppSize.iconLg, color: color),
              const SizedBox(width: AppSpace.s8),
              Expanded(
                child: Text(
                  o.statusLabel.isEmpty ? '未知' : o.statusLabel,
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 无归属: 说清后果 (不讲清"为什么该管", 用户不会点)
        if (o.hasNoOwner) ...[
          const SizedBox(height: AppSpace.s6),
          Text(
            '没有归属人的客户不在任何人的「我的客户」列表里, 也拿不到行动提醒。\n'
            '认领后归你管理 (先到先得)。',
            style: TextStyle(
                fontSize: AppTheme.fontXs, color: t.textSecondary, height: 1.5),
          ),
        ],

        // 归属别人: 说明为什么不能点 (而不是给一个点了会报错的按钮)
        if (!o.canClaim && o.blockedReason != null && !o.hasNoOwner) ...[
          const SizedBox(height: AppSpace.s6),
          Text(
            o.blockedReason!,
            style: TextStyle(
                fontSize: AppTheme.fontXs, color: t.textSecondary, height: 1.5),
          ),
        ],

        const SizedBox(height: AppSpace.s10),
        if (o.canClaim)
          SizedBox(
            width: double.infinity,
            height: AppSize.controlLg,
            child: FilledButton.icon(
              onPressed: _busy ? null : _claim,
              icon: _busy
                  ? SizedBox(
                      width: AppSize.iconSm,
                      height: AppSize.iconSm,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_business_outlined,
                      size: AppSize.iconLg),
              label: Text(
                // 已经是我的 → 按钮改成"确认归属"没意义, 直接提示已归我管
                o.hasNoOwner ? '认领为我的客户' : '已经是我的客户',
                style: const TextStyle(fontSize: AppTheme.fontMd),
              ),
            ),
          )
        else
          Row(
            children: [
              Icon(Icons.info_outline, size: AppSize.iconSm, color: t.textTertiary),
              const SizedBox(width: AppSpace.s4),
              Expanded(
                child: Text(
                  '想转移归属请联系对方协商',
                  style: TextStyle(
                      fontSize: AppTheme.fontXs, color: t.textTertiary),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 把后端业务错误翻成人话 (409/400 都是有含义的, 不该甩 DioException 字符串)
String _humanError(Object e) {
  final s = e.toString();
  if (s.contains('409')) return '已被别人先认领 (先到先得)';
  if (s.contains('400')) return '不能把自己加为客户';
  if (s.contains('404')) return '客户不存在';
  return '认领失败: $e';
}
