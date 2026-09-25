import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/customer_ownership.dart';
import '../../../core/models/customer_share.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/services/api.dart' show ReferralLookup;
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';

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
  /// 我发出的 active 推送 (「已推送给 X」+ 撤销入口; 懒加载, 见 build)
  Future<List<CustomerShareEntry>>? _sharesFuture;

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
          content: Text(humanClaimError(e)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 推送给下级 (Phase D §6.5): 选人 + 备注 → 推送
  ///   语义: 只授可见性 (owner_id 不变), 被推送人列表出现「上级推送 · X」, 手机号明文 (D8)
  Future<void> _pushShare() async {
    final picked = await showModalBottomSheet<_PushShareInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PushShareSheet(customerId: widget.customerId),
    );
    if (picked == null) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(customerServiceProvider)
          .pushShare(widget.customerId, picked.toUserId, note: picked.note);
      ref.invalidate(customerOwnershipProvider(widget.customerId));
      // R-10 L1 (2026-09-26): 推送后被推送人列表里要出现这位客户 (归属态可能变 'upline');
      //   推送不改变归属人, 所以 customerTypeCountsProvider 的 `franchisee/normal` 计数**不变**,
      //   但列表数据本身变了 → 刷 customersProvider (列表行级过滤走 owner_id,
      //   被推送人不影响此人的列表, 但**推送人**的列表行级与计数都按 viewer 口径过滤 → 安全刷一次)
      ref.invalidate(customersProvider);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('已推送给 ${picked.toName}')),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(humanShareError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 撤销推送 (必须填原因; S5 四方撤销, 这里是「推送人」视角)
  Future<void> _revokeShare(CustomerShareEntry entry) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => const _RevokeReasonDialog(),
    );
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(customerServiceProvider).revokeShare(
            widget.customerId,
            entry.toUserId,
            reason: reason.trim(),
          );
      ref.invalidate(customerOwnershipProvider(widget.customerId));
      // R-10 L1 (2026-09-26): 撤销推送后被推送人列表里这位客户**马上消失** (信任崩塌点)。
      //   跟后端 idx_customer_share_to_active 索引协同保证"立即过滤";
      //   客户端必须 invalidate 列表 + 计数, 否则用户看到的是缓存的旧数据。
      ref.invalidate(customersProvider);
      ref.invalidate(customerTypeCountsProvider);
      if (mounted) {
        setState(() {
          _sharesFuture =
              ref.read(customerServiceProvider).sharesOfCustomer(widget.customerId);
        });
      }
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('已撤销对 ${entry.toName} 的推送')),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(humanShareError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 转给同事: 先弹「输邀请码 → 识别 → 确认」, 确认后真转
  Future<void> _transfer() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => _TransferDialog(customerId: widget.customerId),
    );
    if (code == null) return; // 用户取消

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(customerServiceProvider)
          .transfer(widget.customerId, toReferralCode: code);
      // 归属变了 → 三处受影响 (对方列表不在本机, 靠下次拉取)
      ref.invalidate(customerOwnershipProvider(widget.customerId));
      ref.invalidate(customerDetailProvider(widget.customerId));
      ref.invalidate(customersProvider);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('已转出，她不再在你的客户列表')),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(_humanTransferError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 「已推送给」列表 (仅归属人可见; 空则不占位)
  Widget _buildSharedList() {
    final t = context.tokens;
    _sharesFuture ??=
        ref.read(customerServiceProvider).sharesOfCustomer(widget.customerId);
    return FutureBuilder<List<CustomerShareEntry>>(
      future: _sharesFuture,
      builder: (context, snap) {
        final items = snap.data ?? const <CustomerShareEntry>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpace.s10),
            Text('已推送给',
                style: TextStyle(
                    fontSize: AppTheme.fontXs, color: t.textSecondary)),
            const SizedBox(height: AppSpace.s4),
            for (final e in items)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      e.note == null || e.note!.isEmpty
                          ? e.toName
                          : '${e.toName} · ${e.note}',
                      style: const TextStyle(fontSize: AppTheme.fontSm),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _revokeShare(e),
                    child: const Text('撤销'),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final async = ref.watch(customerOwnershipProvider(widget.customerId));

    return B2NoChrome(
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

        // 说明文案 —— 三种情况分开写, **不能只看 hasNoOwner**:
        //   ⚠ 「自己的档案」也是 hasNoOwner=true 但 canClaim=false ——
        //     按 hasNoOwner 写会显示"认领后归你管理"(错) 并给出一个点了会 400 的按钮。
        if (!o.canClaim && o.blockedReason != null) ...[
          // ① 不能认领 (自己的档案 / 归属别人): 说清为什么
          const SizedBox(height: AppSpace.s6),
          Text(
            o.blockedReason!,
            style: TextStyle(
                fontSize: AppTheme.fontXs, color: t.textSecondary, height: 1.5),
          ),
        ] else if (o.hasNoOwner) ...[
          // ② 无归属且可认领: 讲清后果 (不讲清"为什么该管", 用户不会点)
          const SizedBox(height: AppSpace.s6),
          Text(
            '没有归属人的客户不在任何人的「我的客户」列表里, 也拿不到行动提醒。\n'
            '认领后归你管理 (先到先得)。',
            style: TextStyle(
                fontSize: AppTheme.fontXs, color: t.textSecondary, height: 1.5),
          ),
        ],

        const SizedBox(height: AppSpace.s10),
        if (o.canClaim && o.hasNoOwner)
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
              label: const Text('认领为我的客户',
                  style: TextStyle(fontSize: AppTheme.fontMd)),
            ),
          )
        else if (o.isMine)
          // 已经是我的 → 两个有意义的动作:
          //   ① 推送给下级 (可见性授予, **不**转移归属; Phase D §6.5 / D-PRIV-3 一期仅 Flutter)
          //   ② 转给我的同事 (真转移归属)
          Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: AppSize.controlLg,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pushShare,
                  icon: _busy
                      ? SizedBox(
                          width: AppSize.iconSm,
                          height: AppSize.iconSm,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share, size: AppSize.iconLg),
                  label: const Text('推送给下级',
                      style: TextStyle(fontSize: AppTheme.fontMd)),
                ),
              ),
              const SizedBox(height: AppSpace.s8),
              SizedBox(
                width: double.infinity,
                height: AppSize.controlLg,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _transfer,
                  icon: const Icon(Icons.swap_horiz, size: AppSize.iconLg),
                  label: const Text('转给我的同事',
                      style: TextStyle(fontSize: AppTheme.fontMd)),
                ),
              ),
              _buildSharedList(),
            ],
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

// ============================================
// 「转给同事」弹层
// ============================================
// 两段式: 输邀请码 → 识别出**是哪个人** → 才给确认按钮。
//
// 为什么非要让用户先看到"张三 138****8000"再确认:
//   归属转移是**不可逆的权限动作** (转出去就不在你自己列表里了),
//   而邀请码是一串随机字符 —— 光看码根本没把握是转给谁。
//   ADR-0015 Q10 也正是为此授权了「按推荐码查人」接口 (只返回姓名 +
//   打码手机号 + 会员标识, 限流 + 审计)。
//
// 为什么把 code 交回给调用方、由调用方再发 transfer:
//   弹层只管"选人", 业务动作 (转 + 刷三处 provider + snackbar) 留在卡片里,
//   状态管理不乱。
class _TransferDialog extends ConsumerStatefulWidget {
  final String customerId;
  const _TransferDialog({required this.customerId});

  @override
  ConsumerState<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<_TransferDialog> {
  final _codeCtrl = TextEditingController();
  ReferralLookup? _found;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _found = null;
    });
    try {
      final r = await ref.read(billingServiceProvider).lookupReferralCode(code);
      if (!mounted) return;
      setState(() {
        if (!r.found) {
          _error = '邀请码不存在, 请核对后重试';
        } else if (r.claimState == 'self') {
          // 转给自己没意义 —— 后端也会拦, 这里先说清
          _error = '这是你自己的邀请码';
        } else {
          _found = r;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '识别失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final f = _found;
    return AlertDialog(
      title: const Text('转给同事', style: TextStyle(fontSize: AppTheme.fontLg)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '输入对方的邀请码（她可以在「我的」页看到自己的码）。\n'
              '转移后她会出现在对方的「我的客户」列表里，你这边就不再有这位客户。',
              style: TextStyle(fontSize: AppTheme.fontXs, color: t.textSecondary, height: 1.6),
            ),
            const SizedBox(height: AppSpace.s12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontSize: AppTheme.fontMd),
                    decoration: const InputDecoration(
                      hintText: '例如 SRFTF7',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _lookup(),
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
                SizedBox(
                  height: AppSize.controlLg,
                  child: OutlinedButton(
                    onPressed: _loading ? null : _lookup,
                    child: _loading
                        ? const SizedBox(
                            width: AppSize.iconSm,
                            height: AppSize.iconSm,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('识别'),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.s8),
              Text(_error!,
                  style: TextStyle(fontSize: AppTheme.fontXs, color: t.danger)),
            ],
            if (f != null) ...[
              const SizedBox(height: AppSpace.s12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.s10),
                decoration: BoxDecoration(
                  color: t.successSurface,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: AppSize.iconLg, color: t.success),
                    const SizedBox(width: AppSpace.s8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.name,
                              style: TextStyle(
                                  fontSize: AppTheme.fontMd,
                                  fontWeight: FontWeight.w600,
                                  color: t.textPrimary)),
                          Text(
                            '${f.phoneMasked}${f.isMember ? " · 会员" : ""}',
                            style: TextStyle(
                                fontSize: AppTheme.fontXs, color: t.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
        FilledButton(
          // 没识别出人就禁用 —— 防"盲转"
          onPressed: f == null ? null : () => Navigator.pop(context, f.code),
          child: const Text('确认转移', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      ],
    );
  }
}

/// 把**转移**失败的业务错误翻成人话
///
/// 后端 `FAILURE_MESSAGE` 已经给了人话, 但 Dio 把它包在 response 里 ——
/// 这里优先取后端那句, 取不到才退回通用文案。
/// (与 `humanClaimError` 分开: 两者错误集合不同, 混在一起会互相污染)
String _humanTransferError(Object e) {
  final s = e.toString();
  for (final m in [
    '只有当前归属人 (或系统管理员) 能转出客户',
    '这位客户还没有归属人 —— 该用「认领」, 不是转移',
    '不能转给自己',
    '不能把客户转给她本人',
    '这位客户已经是她的了',
    '邀请码不存在或对方账号已停用',
    '客户不存在',
  ]) {
    if (s.contains(m)) return m;
  }
  if (s.contains('403')) return '只有当前归属人 (或系统管理员) 能转出客户';
  return '转移失败: $e';
}


// ============================================
// 「推送给下级」弹层 (Phase D §6.5; 一期仅 Flutter)
// ============================================

class _PushShareInput {
  final String toUserId;
  final String toName;
  final String? note;
  const _PushShareInput({
    required this.toUserId,
    required this.toName,
    this.note,
  });
}

class _PushShareSheet extends ConsumerStatefulWidget {
  final String customerId;
  const _PushShareSheet({required this.customerId});

  @override
  ConsumerState<_PushShareSheet> createState() => _PushShareSheetState();
}

class _PushShareSheetState extends ConsumerState<_PushShareSheet> {
  List<ShareCandidate>? _items;
  String? _selectedId;
  Object? _error;
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items =
          await ref.read(customerServiceProvider).shareCandidates(widget.customerId);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final maxH = MediaQuery.of(context).size.height * 0.7;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpace.s16,
            right: AppSpace.s16,
            top: AppSpace.s16,
            bottom: AppSpace.s16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('推送给下级',
                  style: TextStyle(
                      fontSize: AppTheme.fontLg, fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.s4),
              Text(
                '推送只授予可见性 (归属不变): 她列表里会出现「上级推送」标识, 可以帮你跟进。',
                style: TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: t.textSecondary,
                    height: 1.5),
              ),
              const SizedBox(height: AppSpace.s12),
              if (_error != null)
                Text(humanShareError(_error!),
                    style: TextStyle(
                        fontSize: AppTheme.fontSm, color: t.danger))
              else if (_items == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpace.s20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_items!.isEmpty)
                Text('你的枝上暂无下级同事可推送',
                    style: TextStyle(
                        fontSize: AppTheme.fontSm, color: t.textSecondary))
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _items!.length,
                    itemBuilder: (_, i) {
                      final c = _items![i];
                      final selected = c.userId == _selectedId;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.name,
                            style: const TextStyle(fontSize: AppTheme.fontMd)),
                        trailing: selected
                            ? Icon(Icons.check_circle,
                                size: AppSize.iconLg, color: t.primary)
                            : const Icon(Icons.circle_outlined,
                                size: AppSize.iconLg),
                        onTap: () => setState(() => _selectedId = c.userId),
                      );
                    },
                  ),
                ),
              const SizedBox(height: AppSpace.s8),
              TextField(
                controller: _note,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: '备注 (选填)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: AppSpace.s8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: AppSpace.s8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selectedId == null
                          ? null
                          : () {
                              final name = _items!
                                  .firstWhere((e) => e.userId == _selectedId)
                                  .name;
                              Navigator.pop(
                                context,
                                _PushShareInput(
                                  toUserId: _selectedId!,
                                  toName: name,
                                  note: _note.text,
                                ),
                              );
                            },
                      child: const Text('推送'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// 撤销推送必须填原因 (S5 + 审计留痕); 空 = 取消
class _RevokeReasonDialog extends StatefulWidget {
  const _RevokeReasonDialog();

  @override
  State<_RevokeReasonDialog> createState() => _RevokeReasonDialogState();
}

class _RevokeReasonDialogState extends State<_RevokeReasonDialog> {
  final _reason = TextEditingController();
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _reason.addListener(() {
      final v = _reason.text.trim().isNotEmpty;
      if (v != _valid) setState(() => _valid = v);
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('撤销推送',
          style: TextStyle(fontSize: AppTheme.fontLg)),
      content: TextField(
        controller: _reason,
        maxLength: 200,
        decoration: const InputDecoration(
          labelText: '原因 (必填, 会写进审计)',
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed:
              _valid ? () => Navigator.pop(context, _reason.text.trim()) : null,
          child: const Text('确认撤销'),
        ),
      ],
    );
  }
}
