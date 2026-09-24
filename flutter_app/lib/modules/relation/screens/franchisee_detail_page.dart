// ============================================
// 加盟商详情页 (Plan F3.5)
// 仿 customer_detail_page.dart 结构 + 加盟域特有字段
// 上级 + 位置标签 + 联系 + 编辑 + 软删
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/franchisee.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';

import '../../../core/widgets/app_empty.dart';
import '../lib/franchisee_detail_provider.dart';
import '../../../core/widgets/franchise_chip.dart';

import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';
class FranchiseeDetailPage extends ConsumerWidget {
  final String franchiseeId;
  const FranchiseeDetailPage({super.key, required this.franchiseeId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncFranchisee = ref.watch(franchiseeDetailProvider(franchiseeId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('加盟商详情'),
        toolbarHeight: AppSize.appBarHeight,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, size: AppSize.iconXl),
            tooltip: '编辑',
            onPressed: () => context.push('/franchisees/$franchiseeId/edit'),
          ),
          // admin 强删 (主人 2026-09-18 拍): 死账兜底, 绕过三方确认
          if (ref.watch(meProfileProvider).valueOrNull?.user?.role == 'admin')
            IconButton(
              icon: const Icon(Icons.delete_forever, size: AppSize.iconXl),
              tooltip: '管理强删 (admin)',
              onPressed: () => _confirmForceUnjoin(context, ref),
            ),
        ],
      ),
      body: asyncFranchisee.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (f) => _buildBody(context, ref, f),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, Franchisee f) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 16, 16, 32),
      children: [
        // 头部
        _buildHeader(context, ref, f),
        const SizedBox(height: AppSpace.s16),

        // 上级信息 (「上级加盟商」= **点位父** placement_parent_id, 不是推荐人 referrer_id;
        //   拆栏 2026-09-21 见 ADR-0014 §3.9)
        if (f.placementParentId != null)
          _referrerCard(context, ref, f.placementParentId!),

        // 位置信息
        _positionCard(f),

        const SizedBox(height: AppSpace.s16),

        // 联系按钮
        FilledButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '拨号: ${f.phone} (TODO 后续)',
                  style: const TextStyle(fontSize: AppTheme.fontMd),
                ),
              ),
            );
          },
          icon: const Icon(Icons.phone_in_talk, size: AppSize.iconLg),
          label: const Text('联系'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, AppSize.buttonLgHeight),
          ),
        ),

        const SizedBox(height: AppSpace.s16),

        // 二叉树位置可视化（文字版）
        _treePositionCard(f),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, Franchisee f) {
    return B2NoChrome(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s20),
        child: Column(
          children: [
            CircleAvatar(
              radius: 56,
              backgroundColor: AppTheme.franchisee.withOpacity(0.2),
              child: Text(
                f.name.isNotEmpty ? f.name[0] : '?',
                style: const TextStyle(
                  fontSize: AppType.xxl,
                  color: AppTheme.franchisee,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            Text(
              f.name,
              style: const TextStyle(
                fontSize: AppTheme.fontXl,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpace.s8),
            // 解除加盟入口 = 长按「加盟」标签 (主人 2026-09-19 拍:
            //   不再放右上角图标; 点位不能直接移动 —— 必须先解除, 再重新加盟落位)
            Semantics(
              button: true,
              // container: true → 标签独立成一个语义节点 (不只合并进整张卡), 无障碍/自动化都能定位
              container: true,
              label: '加盟标签, 长按可解除加盟',
              child: GestureDetector(
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  _confirmUnjoin(context, ref);
                },
                child: Tooltip(
                  message: '长按可解除加盟',
                  child: const FranchiseChip(type: 'franchisee', fontSize: AppTheme.fontMd),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.s8),
            Text(
              _maskPhone(f.phone),
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 「上级加盟商」卡 —— 数据源 = **点位父** (调用方传 f.placementParentId)
  Widget _referrerCard(BuildContext context, WidgetRef ref, String uplineFid) {
    final asyncReferrer = ref.watch(franchiseeDetailProvider(uplineFid));
    return asyncReferrer.maybeWhen(
      data: (r) {
        return B2NoChrome(
          margin: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s8),
            leading: CircleAvatar(
              backgroundColor: AppTheme.franchisee.withOpacity(0.2),
              child: Text(
                r.name.isNotEmpty ? r.name[0] : '?',
                style: const TextStyle(color: AppTheme.franchisee),
              ),
            ),
            title: const Text(
              '上级加盟商',
              style: TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
            ),
            subtitle: Text(
              r.name,
              style: const TextStyle(fontSize: AppTheme.fontMd, fontWeight: FontWeight.w500),
            ),
            trailing: const Icon(Icons.chevron_right, size: AppSize.iconXl),
            onTap: () => context.push('/franchisees/${r.id}'),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _positionCard(Franchisee f) {
    return B2NoChrome(
      margin: const EdgeInsets.only(top: AppSpace.s12),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '位置信息',
              style: TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            _row('层级', f.placementDepth == 0 ? '顶级 (root)' : '第 ${f.placementDepth} 层'),
            _row('位置', f.placementSide == null ? '顶级' : (f.placementSide == 'left' ? 'A线' : 'B线')),
            _row('路径', f.placementPath.isEmpty ? '(顶级)' : f.placementPath),
            _row('加入时间', f.joinedAt != null
                ? '${f.joinedAt!.year}-${f.joinedAt!.month.toString().padLeft(2, '0')}-${f.joinedAt!.day.toString().padLeft(2, '0')}'
                : '-'),
            _row('状态', f.isActive ? '活跃' : '已停用'),
          ],
        ),
      ),
    );
  }

  Widget _treePositionCard(Franchisee f) {
    // 二叉树位置可视化（用缩进 + 箭头表示）
    final indent = '  ' * f.placementDepth;
    final sideArrow = f.placementSide == 'left'
        ? '←'
        : f.placementSide == 'right'
            ? '→'
            : '*';

    return B2NoChrome(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '在二叉树中的位置',
              style: TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            Container(
              padding: const EdgeInsets.all(AppSpace.s12),
              decoration: BoxDecoration(
                color: AppTheme.bgWarm,
                borderRadius: BorderRadius.circular(AppRadius.r8),
              ),
              child: Text(
                '$indent$sideArrow ${f.name}',
                style: const TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
        child: Row(
          children: [
            SizedBox(
              width: AppSpace.s80,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );

  String _maskPhone(String phone) {
    if (phone.length == 11) {
      return '${phone.substring(0, 3)}****${phone.substring(7)}';
    }
    return phone;
  }

  /// admin 强删 (主人 2026-09-18 拍): 绕过三方确认; 仅 admin; 仍有下线会被拒
  Future<void> _confirmForceUnjoin(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('管理强删 (admin)'),
        content: const Text(
          '绕过三方确认，直接把这位加盟商的加盟关系解除（软删）。\n'
          '· 会写审计日志\n'
          '· 仍有下线时会被拒绝（先处理完下线）\n'
          '· 仅用于本人账号失效 / 无法完成确认的死账',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('确认强删', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(franchiseeServiceProvider).forceUnjoinFranchisee(franchiseeId);
      ref.invalidate(myFranchiseeTreeProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已强删 (审计已记录)', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('强删失败: $e')),
      );
    }
  }

  /// 解除加盟 (主人 2026-09-18 拍 Q2/Q3):
  ///   正式流程 = 三方确认 (设置者/发起人 + 该加盟商本人 + 其上级); 有下线不允许解除
  ///   —— 不再直接软删 (旧版 removeRelation 一键删, 没有确认也没有审计语义)
  Future<void> _confirmUnjoin(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('解除加盟?'),
        content: const Text(
          '解除需要三方确认: 你 (发起) + 该加盟商本人 + 他的上级。\n'
          '三方都同意后才真正解除 (点位释放, 该客户退回 种子/普通)。\n'
          '有下线的加盟商不能解除 (要先处理完下线)。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('提交解除申请', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final req = await ref
          .read(franchiseeServiceProvider)
          .createPlacementRequest(
            targetParentId: franchiseeId,
            side: 'left',
            unjoinFid: franchiseeId,
          );
      if (!context.mounted) return;
      final done = req.status == 'executed';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            done ? '已解除加盟 (管理员操作, 立即生效)' : '已提交解除申请, 等三方确认',
            style: const TextStyle(fontSize: AppTheme.fontMd),
          ),
        ),
      );
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提交失败: $e')),
      );
    }
  }
}
