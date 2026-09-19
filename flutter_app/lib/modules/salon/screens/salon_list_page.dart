// ============================================
// 沙龙列表页 (v0.1.5 Phase 7, 底部导航「沙龙」tab)
// ============================================
// 2 个 tab: 我受邀的 (role=invited) / 我主理的 (role=organizing)
// 进行中的在上, 已结束/已取消折叠到下方小标题后 (历史可回看)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/salon.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/big_fab.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/salon_providers.dart';
import '../widgets/salon_card.dart';

class SalonListPage extends ConsumerStatefulWidget {
  const SalonListPage({super.key});

  @override
  ConsumerState<SalonListPage> createState() => _SalonListPageState();
}

class _SalonListPageState extends ConsumerState<SalonListPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('沙龙'),
        toolbarHeight: 64,
        bottom: TabBar(
          controller: _tab,
          labelColor: AppTheme.primaryDark,
          unselectedLabelColor: AppTheme.textSecondary,
          indicatorColor: AppTheme.primary,
          indicatorWeight: 3,
          labelStyle: const TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: AppTheme.fontMd),
          tabs: const [
            Tab(text: '我受邀的'),
            Tab(text: '我主理的'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildList('invited'),
          _buildList('organizing'),
        ],
      ),
      // 纯图标 FAB (主人 2026-09-19 拍: 不要文字, 跟客户页一致)
      // 用 core/widgets/big_fab.dart (BigFab 80pt 圆形, 中老年友好);
      // tooltip 保留 = 长按/无障碍仍有说明
      floatingActionButton: BigFab(
        onPressed: () => context.push('/salons/new'),
        tooltip: '创建沙龙',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildList(String role) {
    final asyncSalons = ref.watch(salonsProvider(role));

    return asyncSalons.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(salonsProvider(role)),
      ),
      data: (salons) {
        if (salons.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => ref.refresh(salonsProvider(role).future),
            child: LayoutBuilder(
              builder: (context, constraints) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: constraints.maxHeight,
                    child: const EmptyState(
                      icon: Icons.event_outlined,
                      title: '还没有沙龙',
                      hint: '点右下角 + 创建一个',
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 进行中 (含草稿/报名中/已截止/进行中) 在上, 历史在下
        final active = <Salon>[];
        final past = <Salon>[];
        for (final salon in salons) {
          if (salon.status == SalonStatus.finished ||
              salon.status == SalonStatus.cancelled) {
            past.add(salon);
          } else {
            active.add(salon);
          }
        }

        return RefreshIndicator(
          onRefresh: () => ref.refresh(salonsProvider(role).future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 96),
            children: [
              ...active.map(_buildCard),
              if (past.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    '已结束/已取消',
                    style: TextStyle(
                      fontSize: AppTheme.fontSm,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                ...past.map(_buildCard),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildCard(Salon salon) {
    return SalonCard(
      salon: salon,
      onTap: () => context.push('/salons/${salon.id}'),
    );
  }
}
