// ============================================
// 落位「三方确认」待办页 (主人 2026-09-18 拍)
//
// 两个 tab:
//   - 待我确认: 我是三方之一 (目标父节点 / 新加盟商本人) 还没拍板的
//   - 我发起的: 我作为设置者发起的 (可撤回)
// 动作: 同意 / 拒绝 / 撤回
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/placement_request.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';

class PlacementRequestsPage extends ConsumerStatefulWidget {
  const PlacementRequestsPage({super.key});

  @override
  ConsumerState<PlacementRequestsPage> createState() =>
      _PlacementRequestsPageState();
}

class _PlacementRequestsPageState extends ConsumerState<PlacementRequestsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  List<PlacementRequest> _toConfirm = [];
  List<PlacementRequest> _mine = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(franchiseeServiceProvider);
      final results = await Future.wait([
        svc.listPlacementRequests(scope: 'to_confirm'),
        svc.listPlacementRequests(scope: 'mine'),
      ]);
      if (!mounted) return;
      setState(() {
        _toConfirm = results[0];
        _mine = results[1];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 同意 / 拒绝
  ///   - [side] 只有「认领上级 (promote) 单里的上级本人」要传: 主人拍
  ///     「我在我的上级是处于 a线还是 b线由我的上级自己决定」→ 由她在这里挑
  Future<void> _decide(PlacementRequest r, bool approve, {String? side}) async {
    try {
      await ref
          .read(franchiseeServiceProvider)
          .decidePlacementRequest(r.id, approve: approve, side: side);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? '已同意 (等其余方确认)' : '已拒绝',
            style: const TextStyle(fontSize: AppTheme.fontMd),
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  /// 同意前先挑线 (只有 promote 单的**上级本人** + 她两条线都空时)
  ///
  /// 主人原话: 「『我在上级的 A线/B线』不在我的考虑范围, 由我的上级自己决定」
  /// → 所以挑线这一步落在**上级**这边; 只剩一条空位时服务端自动落那一条, 不问。
  Future<void> _approveWithSidePick(PlacementRequest r) async {
    final sides = r.availableSides.isEmpty
        ? const ['left', 'right']
        : r.availableSides;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgWarm,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '这位下线放在您的哪条线?',
                style: TextStyle(
                  fontSize: AppTheme.fontLg,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${r.initiatorName} 认领您为上级, 她整棵树会接在您选的那条线下面。'
                '接上以后不能撤换 (确需调整请联系系统管理员)。',
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              for (final sd in sides) ...[
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(sd),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                  child: Text(
                    sd == 'left' ? '放在我的 A线 (左)' : '放在我的 B线 (右)',
                    style: const TextStyle(fontSize: AppTheme.fontMd),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56)),
                child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await _decide(r, true, side: picked);
  }

  Future<void> _cancel(PlacementRequest r) async {
    try {
      await ref.read(franchiseeServiceProvider).cancelPlacementRequest(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已撤回', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('撤回失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('加盟落位确认'),
        toolbarHeight: 64,
        bottom: TabBar(
          controller: _tab,
          labelStyle: const TextStyle(fontSize: AppTheme.fontMd),
          tabs: [
            Tab(text: '待我确认 (${_toConfirm.length})'),
            Tab(text: '我发起的 (${_mine.length})'),
          ],
        ),
      ),
      body: _loading
          ? const LoadingState()
          : (_error != null
              ? ErrorState(error: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tab,
                  children: [
                    _buildList(_toConfirm, mine: false),
                    _buildList(_mine, mine: true),
                  ],
                )),
    );
  }

  Widget _buildList(List<PlacementRequest> items, {required bool mine}) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            EmptyState(
              icon: Icons.check_circle_outline,
              title: mine ? '没有进行中的申请' : '没有等我确认的申请',
              hint: mine
                  ? '在图谱里点节点 →「加下线到此点位」发起的申请会出现在这里'
                  : '别人设置加盟节点后, 需要你确认时会出现在这里',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        itemCount: items.length,
        itemBuilder: (context, i) => _buildCard(items[i], mine: mine),
      ),
    );
  }

  Widget _buildCard(PlacementRequest r, {required bool mine}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  r.kind == 'create'
                      ? Icons.person_add_alt
                      : Icons.link_off,
                  size: 22,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.summary,
                    style: const TextStyle(
                      fontSize: AppTheme.fontSm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${r.progressText} · 状态 ${_statusLabel(r.status)}',
              style: const TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.textSecondary,
              ),
            ),
            if (r.expiresAt != null && r.isPending) ...[
              const SizedBox(height: 2),
              Text(
                '${_hoursLeft(r.expiresAt!)} 小时内未确认将自动失效',
                style: const TextStyle(
                  fontSize: AppTheme.fontXs,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            if (r.needsSidePick && r.awaitingMe) ...[
              const SizedBox(height: 4),
              const Text(
                '同意时请挑一条线: 她接在您的 A线 还是 B线, 由您决定',
                style: TextStyle(
                  fontSize: AppTheme.fontXs,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (!mine && r.awaitingMe)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          r.needsSidePick ? _approveWithSidePick(r) : _decide(r, true),
                      icon: const Icon(Icons.check, size: 22),
                      label: const Text('同意', style: TextStyle(fontSize: AppTheme.fontMd)),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _decide(r, false),
                      icon: const Icon(Icons.close, size: 22),
                      label: const Text('拒绝', style: TextStyle(fontSize: AppTheme.fontMd)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                    ),
                  ),
                ],
              )
            else if (!mine)
              Text(
                r.myDecision == 'approve' ? '你已同意, 等其余方确认' : '你已拒绝',
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _cancel(r),
                icon: const Icon(Icons.undo, size: 22),
                label: const Text('撤回', style: TextStyle(fontSize: AppTheme.fontMd)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 56),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return '待确认';
      case 'executed':
        return '已生效';
      case 'rejected':
        return '已拒绝';
      case 'expired':
        return '已超时';
      case 'cancelled':
        return '已撤回';
      default:
        return status;
    }
  }

  String _hoursLeft(DateTime expiresAt) {
    final d = expiresAt.difference(DateTime.now());
    if (d.isNegative) return '0';
    return d.inHours.toString();
  }
}
