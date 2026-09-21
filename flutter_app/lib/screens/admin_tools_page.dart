// ============================================
// 管理员工具 (内测: 人工收款核销 + 设置收款码)
// ============================================
// 为什么做在 APK 里而不是 web admin:
//   主人 2026-09-19 内测用个人微信收款码, 用户在 App 里提交"我已支付" ——
//   主人必须能在**同一台手机**上核对并开通, 否则要开电脑敲 SQL。
//   web admin 现在冻结中 (ADR-0005), 走 APK 反而更快也更符合"销售员用手机"的现实。
//
// 入口可见性: 只有 role=admin 才显示入口 (客户端过滤; 服务端也会 403 拦)
// 安全: 所有写操作服务端都重新查 role, 不信任客户端

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../core/http/api_client.dart';
import '../core/providers/service_providers.dart';
import '../core/services/api.dart' show AdminPayRequest;
import '../core/theme/app_theme.dart';
import '../core/widgets/empty_state.dart';
import 'profile_widgets.dart';

class AdminToolsPage extends ConsumerStatefulWidget {
  const AdminToolsPage({super.key});

  @override
  ConsumerState<AdminToolsPage> createState() => _AdminToolsPageState();
}

class _AdminToolsPageState extends ConsumerState<AdminToolsPage> {
  String _status = 'pending';
  bool _busy = false;

  Future<void> _decide(AdminPayRequest req, bool approve) async {
    setState(() => _busy = true);
    final r = await ref.read(billingServiceProvider).adminDecidePayment(
          requestId: req.id,
          approve: approve,
          rejectReason: approve ? null : '没查到这笔到账',
        );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(r.message, style: const TextStyle(fontSize: AppTheme.fontMd))),
    );
    // 通过后刷新列表 (会员权益变化在用户侧体现)
    ref.invalidate(adminPaymentsProvider(_status));
  }

  Future<void> _pickQrCode() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 900,
        imageQuality: 90,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() => _busy = true);
      final url = await ref.read(photoServiceProvider).upload(
            base64Encode(bytes),
            mimeType: bytes.length > 8 && bytes[0] == 0x89 ? 'image/png' : 'image/jpeg',
            purpose: 'payment_qr',
          );
      final ok = await ref
          .read(billingServiceProvider)
          .adminSetPayInfo(qrUrl: url, enabled: true);
      if (!mounted) return;
      setState(() => _busy = false);
      ref.invalidate(manualPayInfoProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '收款码已更新' : '保存失败, 请重试',
              style: const TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('上传失败', style: TextStyle(fontSize: AppTheme.fontMd))),
        );
      }
    }
  }

  /// 编辑收款人名字 + 备注提示 (用户端「开通会员」弹层上显示的字)
  Future<void> _editPayInfoTexts() async {
    final payeeCtrl = TextEditingController();
    final hintCtrl = TextEditingController();
    // 先拉一次当前值
    try {
      final info = await ref.read(manualPayInfoProvider.future);
      payeeCtrl.text = info.payeeName;
      hintCtrl.text = info.noteHint;
    } catch (_) {
      // 拉不到就留空, 用户自己填
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('收款信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: payeeCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(
                labelText: '收款人显示名',
                hintText: '例: 张老师',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: hintCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(
                labelText: '付款备注提示',
                hintText: '付款备注请填写你的手机号后 4 位',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          ElevatedButton(
            onPressed: () async {
              final ok = await ref.read(billingServiceProvider).adminSetPayInfo(
                    payeeName: payeeCtrl.text.trim(),
                    noteHint: hintCtrl.text.trim(),
                  );
              if (!ctx.mounted) return;
              Navigator.of(ctx).pop();
              ref.invalidate(manualPayInfoProvider);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok ? '已保存' : '保存失败',
                      style: const TextStyle(fontSize: AppTheme.fontMd)),
                ),
              );
            },
            child: const Text('保存', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
    payeeCtrl.dispose();
    hintCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminPaymentsProvider(_status));

    return Scaffold(
      appBar: AppBar(title: const Text('管理员工具'), toolbarHeight: 64),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(adminPaymentsProvider(_status));
          await ref.read(adminPaymentsProvider(_status).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // 用户管理 (主人 2026-09-21 拍): 系统级功能, 收在管理员工具里,
            //   不散在「我的」主页 (那是每个用户都看得到的页面)
            ProfileSection(
              title: '用户与加盟',
              icon: Icons.people_alt_outlined,
              hint: '系统后台',
              children: [
                ProfileTile(
                  icon: Icons.people_alt_outlined,
                  title: '用户管理',
                  subtitle: '全部注册用户 · 加盟 / 未加盟 · 建根',
                  color: AppTheme.primary,
                  onTap: () => context.push('/profile/users'),
                ),
              ],
            ),
            profileSectionGap,
            ProfileSection(
              title: '收款设置',
              icon: Icons.qr_code_2,
              hint: '内测人工通道',
              children: [
                ProfileTile(
                  icon: Icons.badge_outlined,
                  title: '收款人名字 / 备注提示',
                  subtitle: '用户付款页上显示的两行字',
                  color: AppTheme.primaryDark,
                  onTap: _busy ? null : _editPayInfoTexts,
                ),
                ProfileTile(
                  icon: Icons.upload,
                  title: _busy ? '处理中...' : '上传/更换微信收款码',
                  subtitle: '从相册选一张收款码图片 (用户「开通会员」时显示)',
                  color: AppTheme.accent,
                  onTap: _busy ? null : _pickQrCode,
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '用户付完款会在 App 里点「我已支付」, 你在下面核对到账后点「通过」即可开通',
                    style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
            profileSectionGap,
            ProfileSection(
              title: '付款申请',
              icon: Icons.receipt_long,
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'pending', label: Text('待审')),
                  ButtonSegment(value: 'approved', label: Text('已开通')),
                  ButtonSegment(value: 'rejected', label: Text('已驳回')),
                ],
                selected: {_status},
                onSelectionChanged: (s) => setState(() => _status = s.first),
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
              children: [
                async.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(24),
                    child: LoadingState(),
                  ),
                  error: (e, _) => Padding(
                    padding: const EdgeInsets.all(12),
                    child: ErrorState(
                      error: e,
                      onRetry: () => ref.invalidate(adminPaymentsProvider(_status)),
                    ),
                  ),
                  data: (rows) {
                    if (rows.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          '暂时没有',
                          style: TextStyle(fontSize: AppTheme.fontMd, color: AppTheme.textSecondary),
                        ),
                      );
                    }
                    return Column(
                      children: rows.map((r) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.bgWarm,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '用户 #${r.userId} · ¥${(r.amountCents / 100).toStringAsFixed(0)}',
                                      style: const TextStyle(
                                        fontSize: AppTheme.fontMd,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    r.createdAt.length >= 16
                                        ? r.createdAt.substring(5, 16).replaceAll('T', ' ')
                                        : r.createdAt,
                                    style: const TextStyle(
                                        fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '备注: ${r.payerNote?.isNotEmpty == true ? r.payerNote : "(没填)"}',
                                style: const TextStyle(fontSize: AppTheme.fontSm),
                              ),
                              if (r.proofUrl != null) ...[
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () => showDialog<void>(
                                    context: context,
                                    builder: (_) => Dialog(
                                      child: InteractiveViewer(
                                        child: _ProofImage(url: r.proofUrl!),
                                      ),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 90,
                                      height: 90,
                                      child: _ProofImage(url: r.proofUrl!),
                                    ),
                                  ),
                                ),
                              ],
                              if (_status == 'pending') ...[
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton(
                                        onPressed: _busy ? null : () => _decide(r, true),
                                        child: const Text('通过并开通',
                                            style: TextStyle(fontSize: AppTheme.fontSm)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _busy ? null : () => _decide(r, false),
                                        child: const Text('驳回',
                                            style: TextStyle(fontSize: AppTheme.fontSm)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
            profileSectionGap,
            ProfileSection(
              title: '注意',
              icon: Icons.info_outline,
              children: const [
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    '· 通过 = 立刻给该账号 +30 天会员 (可追溯: 申请单 + 权益流水 + 审计日志)\n'
                    '· 只有 admin 角色能进出本页; 服务端每次都会重新校验\n'
                    '· 一笔付款只认一次: 重复点击「通过」会被服务端拒绝',
                    style: TextStyle(fontSize: AppTheme.fontXs, height: 1.6, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 付款截图 (本站上传 → 需要拼 origin)
class _ProofImage extends StatelessWidget {
  final String url;
  const _ProofImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final abs = url.startsWith('http') ? url : '${ApiClient.baseOrigin}$url';
    return Image.network(
      abs,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(
        color: Colors.black12,
        child: Center(child: Icon(Icons.broken_image, size: 24)),
      ),
    );
  }
}
