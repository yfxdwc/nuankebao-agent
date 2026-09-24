import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/customer.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';

// ============================================
// 「危险操作」卡 (管理 Tab 底部, P8, 主人 2026-09-23)
// ============================================
// 放的是**不可逆 / 影响归属**的操作。集中一处而不是散在页面里, 理由:
//   ① 用户心理上需要"这是危险区"的信号, 混在普通卡片里会被误点;
//   ② 以后再加危险操作 (合并/转移) 有明确的家, 不用每次找地方。
//
// 归档口径 (必须对用户诚实):
//   后端 `DELETE /api/customers/[id]` = **软删** (`deleted_at` 打时间戳),
//   数据行还在库里 —— 但 **App 里没有任何恢复入口** (全仓 grep 无 undelete)。
//   所以确认框**不能写"可恢复"** —— 那是骗人。写清"要找管理员从数据库恢复"。
// ============================================

class CustomerDangerZoneCard extends ConsumerStatefulWidget {
  final String customerId;
  final String customerName;
  const CustomerDangerZoneCard({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  @override
  ConsumerState<CustomerDangerZoneCard> createState() =>
      _CustomerDangerZoneCardState();
}

class _CustomerDangerZoneCardState
    extends ConsumerState<CustomerDangerZoneCard> {
  bool _busy = false;

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('归档「${widget.customerName}」？',
            style: const TextStyle(fontSize: AppTheme.fontLg)),
        content: const Text(
          '归档后她不会出现在任何客户列表里，也不会再有跟进提醒。\n\n'
          '养生记录、跟进任务、互动记录**都不会删除**，但 App 里'
          '没有恢复入口 —— 要恢复得联系系统管理员从数据库处理。\n\n'
          '确定归档吗？',
          style: TextStyle(fontSize: AppTheme.fontSm, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('再想想', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('确定归档', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(customerServiceProvider).delete(widget.customerId);
      ref.invalidate(customersProvider);
      ref.invalidate(customerTypeCountsProvider);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('已归档「${widget.customerName}」')),
      );
      // 客户已不在列表里, 停在详情页没有意义 → 退回上一页 (列表)
      navigator.pop();
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('归档失败: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _merge() async {
    // 第一步: 选一条"保留哪条"
    final target = await showDialog<Customer>(
      context: context,
      builder: (_) => const _PickCustomerDialog(),
    );
    if (target == null) return;

    // 第二步: 把**要搬什么 / 不可逆**说清楚再确认
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('合并客户？', style: TextStyle(fontSize: AppTheme.fontLg)),
        content: Text(
          '把「${widget.customerName}」的记录合并进「${target.name}」，'
          '之后只保留「${target.name}」这条档案。\n\n'
          '会搬过去：养生记录、联系记录、跟进任务。\n'
          '不会搬：姓名/生日/健康标签等档案字段（以「${target.name}」为准）。\n\n'
          '⚠ 合并后「${widget.customerName}」这条档案会被归档，App 里无法撤销。',
          style: const TextStyle(fontSize: AppTheme.fontSm, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('确定合并', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final r = await ref
          .read(customerServiceProvider)
          .merge(widget.customerId, intoCustomerId: target.id);
      ref.invalidate(customersProvider);
      ref.invalidate(customerTypeCountsProvider);
      final moved = (r['movedRecords'] as num?)?.toInt() ?? 0;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('已合并进「${target.name}」（搬走 $moved 条养生记录）')),
      );
      navigator.pop(); // 本档案已归档 → 退回列表
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(_humanMergeError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return B2NoChrome(
      margin: EdgeInsets.zero,
      // 危险区视觉: 淡红底 (B 档「边框坚决不要」+ 危险语义靠 surface color 表达)
      color: t.dangerSurface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: AppSize.iconMd, color: t.danger),
                const SizedBox(width: AppSpace.s6),
                Text(
                  '危险操作',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                    color: t.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s6),
            Text(
              '归档后她从客户列表消失，且 App 内无法撤销。',
              style: TextStyle(fontSize: AppTheme.fontXs, color: t.textSecondary),
            ),
            const SizedBox(height: AppSpace.s10),
            SizedBox(
              width: double.infinity,
              height: AppSize.controlLg,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _archive,
                icon: _busy
                    ? SizedBox(
                        width: AppSize.iconSm,
                        height: AppSize.iconSm,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.archive_outlined, size: AppSize.iconLg),
                label: const Text('归档这位客户',
                    style: TextStyle(fontSize: AppTheme.fontMd)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.danger,
                  side: BorderSide(color: t.danger.withOpacity(0.5)),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s8),
            SizedBox(
              width: double.infinity,
              height: AppSize.controlLg,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _merge,
                icon: const Icon(Icons.merge_type, size: AppSize.iconLg),
                label: const Text('合并重复客户',
                    style: TextStyle(fontSize: AppTheme.fontMd)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.danger,
                  side: BorderSide(color: t.danger.withOpacity(0.5)),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s6),
            Text(
              '同一个人被建了两条档案时用（记录会搬过去，两条并成一条）。',
              style: TextStyle(fontSize: AppTheme.fontXs, color: t.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// 「选一条保留的客户」弹层 (合并用)
// ============================================
// 搜索 + 点选。搜索结果来自现成的 `GET /api/customers?search=` (客户列表页同一条路),
// 所以**永远只搜得到我有权看的客户** —— 不用在这里重复做权限过滤。
//
// 为什么不用下拉框: 客户可能几百个, 下拉框没法按姓名/手机号找。
class _PickCustomerDialog extends ConsumerStatefulWidget {
  const _PickCustomerDialog();

  @override
  ConsumerState<_PickCustomerDialog> createState() =>
      _PickCustomerDialogState();
}

class _PickCustomerDialogState extends ConsumerState<_PickCustomerDialog> {
  final _ctrl = TextEditingController();
  List<Customer> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref.read(customerServiceProvider).list(search: q, limit: 20);
      if (mounted) {
        setState(() {
          // 显式取 .customer: 列表接口返回的是 CustomerWithFollowUp (客户 + 跟进信息),
          //   这里只要客户本体 —— 别依赖泛型协变, 类型写明确更好读
          _results = r.items.map((x) => x.customer).toList();
          _searched = true;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '搜索失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return AlertDialog(
      title: const Text('保留哪条客户？', style: TextStyle(fontSize: AppTheme.fontLg)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '查出"同一个人"的另一条档案，点它 = 保留那一条。',
              style: TextStyle(fontSize: AppTheme.fontXs, color: t.textSecondary),
            ),
            const SizedBox(height: AppSpace.s10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style: const TextStyle(fontSize: AppTheme.fontMd),
                    decoration: const InputDecoration(
                      hintText: '姓名或手机号',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
                SizedBox(
                  height: AppSize.controlLg,
                  child: OutlinedButton(
                    onPressed: _loading ? null : _search,
                    child: _loading
                        ? const SizedBox(
                            width: AppSize.iconSm,
                            height: AppSize.iconSm,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('搜索'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.s8),
              Text(_error!,
                  style: TextStyle(fontSize: AppTheme.fontXs, color: t.danger)),
            ],
            if (_searched && _results.isEmpty) ...[
              const SizedBox(height: AppSpace.s10),
              Text('没找到匹配的客户',
                  style: TextStyle(fontSize: AppTheme.fontSm, color: t.textSecondary)),
            ],
            if (_results.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final c = _results[i];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_outline,
                          size: AppSize.iconLg, color: t.textSecondary),
                      title: Text(c.name,
                          style: TextStyle(
                              fontSize: AppTheme.fontMd, color: t.textPrimary)),
                      subtitle: Text(
                        '建档 ${c.createdAt.toIso8601String().substring(0, 10)}'
                        '${c.hasAccount ? " · 已注册" : ""}',
                        style: TextStyle(
                            fontSize: AppTheme.fontXs, color: t.textSecondary),
                      ),
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      ],
    );
  }
}

/// 把**合并**失败的业务错误翻成人话
String _humanMergeError(Object e) {
  final s = e.toString();
  for (final m in [
    '两条档案都绑了 app 账号',
    '不能合并到自己',
    '目标客户不存在或已归档',
    '没有权限操作这条客户',
  ]) {
    if (s.contains(m)) return m;
  }
  if (s.contains('403')) return '没有权限操作这条客户';
  return '合并失败: $e';
}
