// ============================================
// 我推荐的人 (B1: 推荐人确认「这是我朋友」)
// ============================================
// 主人 2026-09-20: 新用户凭推荐码自助注册, 但**推荐人点确认后才发 15 天权益**
//   → 防"码被转发到群里, 陌生人拿码白嫖会员"; 推荐人也要为自己的码负责
//
// 谁能看: 只有本人 (服务端按 session 过滤); 列表里手机号打码 (推荐人知道是谁就行)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/service_providers.dart';
import '../core/services/api.dart' show MyReferral;
import '../core/theme/app_theme.dart';
import '../core/widgets/empty_state.dart';
import 'profile_widgets.dart';

class MyReferralsPage extends ConsumerStatefulWidget {
  const MyReferralsPage({super.key});

  @override
  ConsumerState<MyReferralsPage> createState() => _MyReferralsPageState();
}

class _MyReferralsPageState extends ConsumerState<MyReferralsPage> {
  bool _busy = false;

  Future<void> _decide(MyReferral r, bool confirm) async {
    setState(() => _busy = true);
    final res = await ref.read(billingServiceProvider).decideReferral(
          rewardId: r.id,
          confirm: confirm,
          reason: confirm ? null : '我不认识这个人',
        );
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.message, style: const TextStyle(fontSize: AppTheme.fontMd))),
    );
    ref.invalidate(myReferralsProvider);
    ref.invalidate(meProfileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myReferralsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我推荐的人'), toolbarHeight: 64),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myReferralsProvider);
          await ref.read(myReferralsProvider.future);
        },
        child: async.when(
          loading: () => const LoadingState(),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ErrorState(error: e, onRetry: () => ref.invalidate(myReferralsProvider)),
            ],
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: const [
                  SizedBox(height: 60),
                  EmptyState(
                    icon: Icons.group_outlined,
                    title: '还没有人用你的推荐码注册',
                    hint: '把你的 6 位推荐码发给朋友, 对方注册时填上;\n'
                        '确认后对方得 15 天会员, 你在他成为加盟者后也得 15 天',
                  ),
                ],
              );
            }

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                ProfileSection(
                  title: '好友申请',
                  icon: Icons.group_add,
                  hint: '共 ${rows.length} 人',
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        '朋友填了你的推荐码注册。确认「这是我朋友」后, 他立刻得到 15 天会员; '
                        '不认识就驳回 (不会有任何权益)。',
                        style: TextStyle(
                          fontSize: AppTheme.fontXs,
                          height: 1.6,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    ...rows.map((r) {
                      // 只有"自助注册 + 未处理"才需要推荐人动手 (管理员代建的已生效)
                      final pending = r.needsMyConfirmation;
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
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: AppTheme.primaryLight,
                                  child: Text(
                                    r.name.isNotEmpty ? r.name.characters.first : '?',
                                    style: const TextStyle(
                                      color: AppTheme.primaryDark,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        r.name,
                                        style: const TextStyle(
                                          fontSize: AppTheme.fontMd,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        '${r.phoneMasked} · ${r.statusLabel}',
                                        style: const TextStyle(
                                          fontSize: AppTheme.fontXs,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (pending) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: _busy ? null : () => _decide(r, true),
                                      child: const Text('这是我朋友',
                                          style: TextStyle(fontSize: AppTheme.fontSm)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _busy ? null : () => _decide(r, false),
                                      child: const Text('不认识',
                                          style: TextStyle(fontSize: AppTheme.fontSm)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
