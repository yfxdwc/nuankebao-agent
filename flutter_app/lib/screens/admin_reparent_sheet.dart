// ============================================
// 协商处理 · 改上层 (管理员专用)
// ============================================
// 主人 2026-09-21 拍:
//   「「上层」= 点位父, 不一定是推荐码提供人。上层一旦有人不能撤换, 除非联系系统管理员协商处理。」
//   「给管理员一个『协商处理后强改上层』的后台功能」
//
// 什么时候用 (前端把这三种情形写给管理员看, 免得当成"日常改位置"乱点):
//   ① 上层填错了 (落位时选错人)
//   ② 现实里换了上级 (公司加盟体系调整)
//   ③ 两棵树其实是一棵 (把孤立的那棵挂到主树上)
//
// 这是唯一的人工例外通道 → 三层保护:
//   ① 入口只在「用户管理 → 图谱/列表 → 节点」里, 只有管理员能进
//   ② 必须填原因 (2-200 字, 后端强校验 → 写进她的备注 + 审计)
//   ③ 后端重判一切 (成环 / 那条线有人 / 没账号 → 拒), 前端算的只是体验
//
// 谁有资格当新上层 (与后端同一口径):
//   - 有账号 (节点 ⇒ 账号 不变量: 没账号的人当不了上层)
//   - 不是她自己, 也不在她自己的子树里 (否则成环, 树会断)
//   - 她那一边必须空着 (一个人的一层只有 A线 / B线 两个位置)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/admin_user.dart';
import '../core/providers/service_providers.dart';
import '../core/theme/app_theme.dart';

import '../core/theme/tokens.g.dart';
/// 弹出「改上层」弹层; 返回 true = 改成功了 (调用方去刷新)
Future<bool?> showReparentSheet(
  BuildContext context,
  WidgetRef ref, {
  required AdminNode move,
  required AdminUsersOverview data,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ReparentSheet(move: move, data: data),
  );
}

/// 某个节点的两条线现在谁占着 (fid -> 'left'/'right' -> 节点)
Map<String, Map<String, AdminNode>> _childrenByParent(List<AdminNode> nodes) {
  final map = <String, Map<String, AdminNode>>{};
  for (final n in nodes) {
    final p = n.parentFid;
    if (p == null) continue;
    final side = n.sideFromPath;
    if (side == null) continue;
    (map[p] ??= {})[side] = n;
  }
  return map;
}

/// 她是否在 move 的子树里 (path 前缀 + 同 rootFid; 与后端同一口径)
bool _inSubtreeOf(AdminNode move, AdminNode n) {
  if (n.rootFid != move.rootFid) return false;
  if (move.path.isEmpty) return true; // 她是树根 → 整棵树都是她的下线
  return n.path.startsWith(move.path);
}

class _ReparentSheet extends ConsumerStatefulWidget {
  const _ReparentSheet({required this.move, required this.data});

  final AdminNode move;
  final AdminUsersOverview data;

  @override
  ConsumerState<_ReparentSheet> createState() => _ReparentSheetState();
}

class _ReparentSheetState extends ConsumerState<_ReparentSheet> {
  final _search = TextEditingController();
  final _reason = TextEditingController();

  AdminNode? _newParent;
  String? _side;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _reason.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _reason.dispose();
    super.dispose();
  }

  List<AdminNode> get _candidates {
    final move = widget.move;
    final q = _search.text.trim();
    final list = widget.data.nodes.where((n) {
      if (n.fid == move.fid) return false;
      if (!n.hasAccount) return false; // 没账号的当不了上层
      if (_inSubtreeOf(move, n)) return false; // 会成环
      if (q.isNotEmpty && !n.name.contains(q)) return false;
      return true;
    }).toList();
    // 同树的排前面 (多数情形是树内换上层), 再按层号
    list.sort((a, b) {
      final sameA = a.rootFid == move.rootFid ? 0 : 1;
      final sameB = b.rootFid == move.rootFid ? 0 : 1;
      if (sameA != sameB) return sameA - sameB;
      if (a.depth != b.depth) return a.depth - b.depth;
      return a.name.compareTo(b.name);
    });
    return list;
  }

  Map<String, AdminNode?> _occupants(AdminNode parent) {
    final kids = _childrenByParent(widget.data.nodes)[parent.fid] ?? const {};
    return {'left': kids['left'], 'right': kids['right']};
  }

  String _sideLabel(String side) => side == 'left' ? 'A线 (左)' : 'B线 (右)';

  /// 她当前的位置一句人话
  String get _currentPosition {
    final move = widget.move;
    if (move.isRoot) return '现在是树根 (没有上层) —— 改上层 = 给她安一个';
    AdminNode? parent;
    for (final n in widget.data.nodes) {
      if (n.fid == move.parentFid) {
        parent = n;
        break;
      }
    }
    final side = move.sideFromPath;
    final where = side == null ? '' : ' 的${_sideLabel(side)}';
    return parent == null ? '现在的位置: 上层未知$where' : '现在在「${parent.name}」$where';
  }

  Future<void> _submit() async {
    final parent = _newParent;
    final side = _side;
    if (parent == null) {
      _toast('先选一位新的上层');
      return;
    }
    if (side == null) {
      _toast('再选她在这位上层下面走 A线 还是 B线');
      return;
    }
    if (_reason.text.trim().length < 2) {
      _toast('请写一句为什么改 (审计要留痕)');
      return;
    }

    setState(() => _busy = true);
    final r = await ref.read(adminUsersServiceProvider).reparentNode(
          fid: widget.move.fid,
          newParentFid: parent.fid,
          side: side,
          reason: _reason.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message, style: const TextStyle(fontSize: AppTheme.fontSm)),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      _toast(r.message);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: AppTheme.fontSm)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final move = widget.move;
    final candidates = _candidates;
    final occupants = _newParent == null ? null : _occupants(_newParent!);
    final canSubmit = _newParent != null &&
        _side != null &&
        _reason.text.trim().length >= 2 &&
        !_busy;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpace.s20,
          right: AppSpace.s20,
          top: AppSpace.s4,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '协商处理: 改上层',
              style: TextStyle(fontSize: AppTheme.fontMd, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpace.s6),
            Text(
              '给「${move.name}」换一位上层 (点位父)。\n'
              '上层一旦有人就不能自己撤换 —— 这条是管理员协商处理通道, 会留痕。',
              style: const TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpace.s8),
            Text(
              _currentPosition,
              style: const TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpace.s14),
            const Text(
              '① 选新的上层 (谁在她上面)',
              style: TextStyle(fontSize: AppTheme.fontSm, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpace.s6),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: AppSize.iconMd),
                hintText: '搜名字',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: AppTheme.fontSm),
            ),
            const SizedBox(height: AppSpace.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: candidates.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpace.s16),
                      child: Text(
                        '没有可选的上层: 树里其他人要么还没账号, 要么都是她的下线',
                        style: TextStyle(
                          fontSize: AppTheme.fontSm,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: candidates.length,
                      itemBuilder: (_, i) => _candidateTile(candidates[i], move),
                    ),
            ),
            const SizedBox(height: AppSpace.s10),
            const Text(
              '② 她在这位上层下面走哪条线',
              style: TextStyle(fontSize: AppTheme.fontSm, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpace.s6),
            Row(
              children: [
                _sideButton('left', occupants, occupants?['left']),
                const SizedBox(width: AppSpace.s10),
                _sideButton('right', occupants, occupants?['right']),
              ],
            ),
            const SizedBox(height: AppSpace.s14),
            TextField(
              controller: _reason,
              maxLength: 200,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: '③ 为什么改 (必填, 2-200 字)',
                hintText: '如: 她现实里的上级换成了张姐 / 落位时选错了人',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: AppTheme.fontSm),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canSubmit ? _submit : null,
                icon: _busy
                    ? const SizedBox(
                        width: AppSpace.s16,
                        height: AppSpace.s16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_tree_outlined),
                label: const Text('确认改上层'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _candidateTile(AdminNode n, AdminNode move) {
    final occ = _occupants(n);
    final free = <String>[
      if (occ['left'] == null) 'A线空',
      if (occ['right'] == null) 'B线空',
    ];
    final selected = _newParent?.fid == n.fid;
    final otherTree = n.rootFid != move.rootFid;
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: AppTheme.primary.withOpacity(0.10),
      onTap: () => setState(() {
        _newParent = n;
        _side = null; // 换人 → 线别要重选
      }),
      title: Row(
        children: [
          Flexible(
            child: Text(
              n.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: AppTheme.fontSm, fontWeight: FontWeight.w600),
            ),
          ),
          if (otherTree) ...[
            const SizedBox(width: AppSpace.s6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s6, vertical: 1),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(0.14),
                borderRadius: BorderRadius.circular(AppRadius.r8),
              ),
              child: const Text(
                '另一棵树',
                style: TextStyle(fontSize: AppType.micro, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '第 ${n.depth + 1} 层 · 编号 #${n.fid} · '
        '${free.isEmpty ? "两条线都有人" : free.join(" / ")}',
        style: const TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _sideButton(String side, Map<String, AdminNode?>? occ, AdminNode? taken) {
    final disabled = _newParent == null || taken != null;
    final selected = _side == side;
    return Expanded(
      child: OutlinedButton(
        onPressed: disabled ? null : () => setState(() => _side = side),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? AppTheme.primary.withOpacity(0.12) : null,
          side: BorderSide(
            color: selected ? AppTheme.primary : AppTheme.textSecondary.withOpacity(0.4),
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpace.s10, horizontal: AppSpace.s8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _sideLabel(side),
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: disabled ? AppTheme.textSecondary : null,
              ),
            ),
            if (taken != null)
              Text(
                '${taken.name} 占着',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: AppType.micro, color: AppTheme.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
