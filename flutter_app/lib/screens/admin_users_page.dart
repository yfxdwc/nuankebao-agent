// ============================================
// 用户管理 (管理员专用: 全部注册用户 · 列表 / 图谱)
// ============================================
// 主人 2026-09-21 拍:
//   「管理员的『我的』页面增加一个页面入口 → 全部注册用户管理页, 可切换列表和图谱 2 种视图;
//     图谱页要能显示 加盟 (接入了节点树的) / 未加盟 (独立节点);
//     付费会员要在头像上有会员标识以作区分」
//   「建根 = 先有账号, admin 能建根, 但要用户先注册」
//
// 为什么做在 APK 而不是 web admin: 同 admin_tools_page.dart —— web admin 冻结中
//   (ADR-0005), 而建根/看人主人在手机上就要能做。
// 权限: 入口只对 role=admin 显示 (客户端过滤); 服务端每个请求重新查 role。
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/admin_user.dart';
import '../core/providers/service_providers.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/member_avatar.dart';
import 'admin_reparent_sheet.dart';
import 'admin_users_graph.dart';

import '../core/theme/tokens.g.dart';
class AdminUsersPage extends ConsumerStatefulWidget {
  const AdminUsersPage({super.key});

  @override
  ConsumerState<AdminUsersPage> createState() => _AdminUsersPageState();
}

enum _View { list, graph }

class _AdminUsersPageState extends ConsumerState<AdminUsersPage> {
  _View _view = _View.list;
  bool _viewInitialized = false;
  String _busy = '';

  /// 图谱重置用的 key: 自增 = 重新挂载图谱 → 顺便重摆初始视图
  int _graphEpoch = 0;

  /// 图谱初始视图: true = 缩到装下整张画布 (主人 2026-09-21 拍: 「图谱默认进来要直接适应屏幕」)
  /// / false = 对准树根 1:1 (名字清楚, 靠「回到树根」按钮切)
  bool _graphFitAll = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // URL ?view=graph → 直接进图谱 (同客户页 /customers?view=graph 的口径; 也方便截图验证)
    if (!_viewInitialized) {
      if (GoRouterState.of(context).uri.queryParameters['view'] == 'graph') {
        _view = _View.graph;
      }
      _viewInitialized = true;
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(adminUsersProvider);
    await ref.read(adminUsersProvider.future);
  }

  // ---------- 建根 ----------
  Future<void> _buildRoot(AdminUser user) async {
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('设为根节点'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '把「${user.name}」建成一棵新的加盟树的根节点。\n'
                '根没有上级, 所以不需要三方确认 (后续节点照旧要走确认)。',
                style: const TextStyle(fontSize: AppTheme.fontSm),
              ),
              const SizedBox(height: AppSpace.s12),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: '为什么建这个根 (必填)',
                  hintText: '如: 杭州西湖店 店长',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('建根'),
            ),
          ],
        );
      },
    );
    if (note == null || !mounted) return;
    if (note.length < 2) {
      _toast('请填一句建根原因 (审计要留痕)');
      return;
    }

    setState(() => _busy = user.id);
    final r = await ref
        .read(adminUsersServiceProvider)
        .createRoot(userId: user.id, note: note);
    if (!mounted) return;
    setState(() => _busy = '');
    _toast(r.message);
    if (r.ok) await _refresh();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: AppTheme.fontSm)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ---------- 详情弹层 ----------
  void _showUserSheet(AdminUser u) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  MemberAvatar(
                    avatarUrl: u.avatarUrl,
                    name: u.name,
                    size: 56,
                    isMember: u.member.isMember,
                  ),
                  const SizedBox(width: AppSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          u.name,
                          style: const TextStyle(
                            fontSize: AppTheme.fontMd,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: AppSpace.s2),
                        Text(
                          _memberText(u),
                          style: TextStyle(
                            fontSize: AppTheme.fontSm,
                            color: u.member.isMember
                                ? kMemberGold
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.s16),
              _kv('手机号', u.phoneMasked.isEmpty ? '—' : u.phoneMasked),
              _kv('推荐码', u.referralCode ?? '—'),
              _kv('账号角色', u.isAdmin ? '系统管理员' : '销售员'),
              _kv('加盟状态', u.isJoined ? '已加盟 (节点 #${u.franchiseeId})' : '未加盟'),
              _kv('注册时间', u.createdDate.isEmpty ? '—' : u.createdDate),
              if (!u.isJoined) ...[
                const SizedBox(height: AppSpace.s16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _buildRoot(u);
                    },
                    icon: const Icon(Icons.park_outlined),
                    label: const Text('设为根节点'),
                  ),
                ),
              ],
              // 已加盟 → 节点操作 (改上层). 这里找不到节点行 (脏数据) 就不显示, 免得点了报错
              if (u.isJoined && _nodeOfUser(u) != null) ...[
                const SizedBox(height: AppSpace.s16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openReparent(_nodeOfUser(u)!);
                    },
                    icon: const Icon(Icons.swap_vert, size: 18),
                    label: const Text('协商处理: 改上层'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showNodeSheet(AdminNode n) {
    final parent = _parentOf(n);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.s20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                n.name,
                style: const TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpace.s12),
              _kv('节点编号', '#${n.fid}'),
              if (n.accountName != null) _kv('账号', n.accountName!),
              _kv(
                '上层点位',
                parent == null
                    ? (n.isRoot ? '无 (她是树根)' : '—')
                    : '${parent.name} 的${n.side == 'left' ? 'A线' : 'B线'}',
              ),
              _kv('位置', n.isRoot ? '根节点 (没有上级)' : '第 ${n.depth + 1} 层'),
              _kv('会员', n.member ? '会员' : '免费'),
              _kv('账号状态', n.hasAccount ? '有账号' : '无账号 (历史/脚本站的节点)'),
              const SizedBox(height: AppSpace.s8),
              if (n.hasAccount)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openReparent(n);
                    },
                    icon: const Icon(Icons.swap_vert, size: 18),
                    label: const Text('协商处理: 改上层'),
                  ),
                )
              else
                const Text(
                  '她没有账号 → 不能当节点被搬动。先让她用这个手机号注册登录 '
                  '(注册会自动认领这个节点), 再改上层。',
                  style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 按节点找她的点位父 (无 → null)
  AdminNode? _parentOf(AdminNode n) {
    if (n.parentFid == null) return null;
    for (final x in _lastData?.nodes ?? const <AdminNode>[]) {
      if (x.fid == n.parentFid) return x;
    }
    return null;
  }

  /// 按账号找她的节点行 (未加盟 / 脏数据 → null)
  AdminNode? _nodeOfUser(AdminUser u) {
    if (u.franchiseeId == null) return null;
    for (final x in _lastData?.nodes ?? const <AdminNode>[]) {
      if (x.fid == u.franchiseeId) return x;
    }
    return null;
  }

  Future<void> _openReparent(AdminNode n) async {
    final data = _lastData;
    if (data == null) return;
    final ok = await showReparentSheet(context, ref, move: n, data: data);
    if (ok == true) await _refresh();
  }

  String _memberText(AdminUser u) {
    if (u.member.permanent) return '管理员 · 永久会员';
    if (!u.member.isMember) return '免费版';
    final until = u.member.until;
    if (until == null || until.length < 10) return '会员';
    return '会员 · 有效至 ${until.substring(0, 10)}';
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.s8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: AppSpace.s76,
              child: Text(
                k,
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(v, style: const TextStyle(fontSize: AppTheme.fontSm)),
            ),
          ],
        ),
      );

  /// 最近一次拿到的总览 (弹层里要按 id 找节点/父节点; build 里顺手存一份)
  AdminUsersOverview? _lastData;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminUsersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('用户管理'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        // 403 (非管理员) 给一句人话, 不要笼统"网络不太好" —— 那会让人一直重试
        error: (e, _) => e.toString().contains('403')
            ? const EmptyState(
                icon: Icons.lock_outline,
                title: '只有管理员能看',
                hint: '这个页面是系统管理员专用的',
              )
            : ErrorState(error: e, onRetry: _refresh),
        data: (data) {
          _lastData = data;
          if (data.users.isEmpty) {
            return const EmptyState(
              icon: Icons.people_outline,
              title: '还没有注册用户',
              hint: '用户先注册, 你才能把他设为根节点',
            );
          }
          final s = data.summary;
          return Column(
            children: [
              _summaryBar(s),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.s16, 8, 16, 8),
                child: SegmentedButton<_View>(
                  segments: const [
                    ButtonSegment(
                      value: _View.list,
                      label: Text('列表', style: TextStyle(fontSize: AppTheme.fontSm)),
                    ),
                    ButtonSegment(
                      value: _View.graph,
                      label: Text('图谱', style: TextStyle(fontSize: AppTheme.fontSm)),
                    ),
                  ],
                  selected: {_view},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _view = v.first),
                ),
              ),
              // 多棵树时给一句方向提示: 中老年用户不会自己想到"往右拖还有树"
              if (_view == _View.graph && s.roots > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.s16, 0, 16, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.swipe_outlined,
                          size: 18, color: AppTheme.textSecondary),
                      const SizedBox(width: AppSpace.s6),
                      Expanded(
                        child: Text(
                          '图谱里有 ${s.roots} 棵加盟树 (不同系统 / 不同枝) · 左右拖动看其它树',
                          style: const TextStyle(
                            fontSize: AppTheme.fontSm,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _view == _View.list
                    ? _list(data)
                    : Stack(
                        // ⚠ 必须 expand: 只放 Positioned 子节点的 Stack 会缩成 0 尺寸
                        //   (截图实测: 图谱整片空白, 只剩重置按钮)
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(
                            child: AdminUsersGraph(
                              key: ValueKey('graph-$_graphEpoch-$_graphFitAll'),
                              data: data,
                              fitAll: _graphFitAll,
                              onTapNode: _showNodeSheet,
                              onTapUser: _showUserSheet,
                            ),
                          ),
                          // 两个视图按钮 (中老年用户不熟双指缩放复位, 得给按钮):
                          //   适应屏幕 = 看整张图 (结构) / 回到树根 = 回 1:1 看名字
                          Positioned(
                            right: AppSpace.s12,
                            bottom: AppSpace.s12,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FloatingActionButton.small(
                                  heroTag: 'admin-users-graph-fit',
                                  tooltip: '适应屏幕 (看整张图)',
                                  onPressed: () => setState(() {
                                    _graphFitAll = true;
                                    _graphEpoch += 1;
                                  }),
                                  child: const Icon(Icons.zoom_out_map),
                                ),
                                const SizedBox(height: AppSpace.s10),
                                FloatingActionButton.small(
                                  heroTag: 'admin-users-graph-root',
                                  tooltip: '回到树根 (1:1 看名字)',
                                  onPressed: () => setState(() {
                                    _graphFitAll = false;
                                    _graphEpoch += 1;
                                  }),
                                  child: const Icon(Icons.center_focus_strong),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryBar(AdminUsersSummary s) {
    final parts = <String>[
      '共 ${s.total} 人',
      '加盟 ${s.joined}',
      '未加盟 ${s.notJoined}',
      '会员 ${s.members}',
    ];
    // 加盟树可能不止一棵 (不同加盟系统 / 同一系统的不同枝, 暂未上溯到共同上层)
    //   → 主人数 1 时才不写, 免得常规情况多一句废话
    if (s.roots > 1) parts.add('加盟树 ${s.roots} 棵');
    if (s.nodesWithoutAccount > 0) parts.add('树里 ${s.nodesWithoutAccount} 个无账号节点');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(AppSpace.s16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s14, vertical: AppSpace.s10),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.r10),
      ),
      child: Text(
        parts.join(' · '),
        style: const TextStyle(
          fontSize: AppTheme.fontSm,
          color: AppTheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _list(AdminUsersOverview data) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        itemCount: data.users.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final u = data.users[i];
          return InkWell(
            onTap: () => _showUserSheet(u),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s12),
              child: Row(
                children: [
                  MemberAvatar(
                    avatarUrl: u.avatarUrl,
                    name: u.name,
                    size: 48,
                    isMember: u.member.isMember,
                  ),
                  const SizedBox(width: AppSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                u.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: AppTheme.fontMd,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (u.isAdmin) ...[
                              const SizedBox(width: AppSpace.s6),
                              _chip('管理员', AppTheme.danger),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpace.s4),
                        Text(
                          [
                            if (u.phoneMasked.isNotEmpty) u.phoneMasked,
                            if (u.referralCode != null) '推荐码 ${u.referralCode}',
                            if (u.createdDate.isNotEmpty) '注册 ${u.createdDate}',
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTheme.fontXs,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.s8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _chip(
                        u.isJoined ? '加盟' : '未加盟',
                        u.isJoined ? AppTheme.primary : AppTheme.textSecondary,
                      ),
                      if (!u.isJoined)
                        TextButton(
                          onPressed: _busy == u.id ? null : () => _buildRoot(u),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: _busy == u.id
                              ? const SizedBox(
                                  width: AppSpace.s16,
                                  height: AppSpace.s16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  '设为根节点',
                                  style: TextStyle(fontSize: AppTheme.fontXs),
                                ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8, vertical: AppSpace.s2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(AppRadius.r10),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: AppTheme.fontXs,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}
