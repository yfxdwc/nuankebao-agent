// ============================================
// 用户管理 · 图谱视图 (加盟树 + 未加盟独立节点)
// ============================================
// 主人 2026-09-21 拍:
//   「图谱页中要能显示加盟 (接入了节点树的)、未加盟 (独立节点), 付费会员头像上有会员标识」
//
// 画什么:
//   上半部分 = **加盟树** (placement 二叉树; 边 = 上下级关系)
//     - 有账号的节点: 头像 + 名称 + 会员标识
//     - **没有账号的节点**(历史/脚本造的): 灰圈 + 名称 + 「无账号」
//       ⚠ 必须画出来: dev 库 32 个节点里 29 个没账号, 不画 = 树断成孤岛
//   下半部分 = **未加盟** 的注册账号 (独立节点, 不成树, 平铺)
//
// 复用 customer_graph_view 的思路 (InteractiveViewer + CustomPainter 画边 + Positioned 放节点),
// 但布局自己算: 那棵树是"客户推荐关系 + 单一根", 这里是"加盟树 + 多根 + 独立节点带"
// vibe: 中老年女性销售 —— 节点大、字大、不炫技、颜色只在"会员/状态"上花
// ============================================

import 'package:flutter/material.dart';

import '../core/models/admin_user.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/member_avatar.dart';

class AdminUsersGraph extends StatefulWidget {
  final AdminUsersOverview data;
  final void Function(AdminNode node) onTapNode;
  final void Function(AdminUser user) onTapUser;

  const AdminUsersGraph({
    super.key,
    required this.data,
    required this.onTapNode,
    required this.onTapUser,
  });

  @override
  State<AdminUsersGraph> createState() => _AdminUsersGraphState();
}

// ---------- 布局常量 ----------
const double _nodeW = 108; // 节点槽宽
const double _nodeH = 104; // 节点高 (头像 48 + 名字 + 提示)
const double _levelH = 132; // 层高
const double _gapX = 12; // 兄弟间距
const double _padX = 40; // 画布左右留白
const double _padY = 32; // 画布上下留白
const double _isoSlotW = 116; // 未加盟节点槽宽
const double _isoSlotH = 124;

class _Box {
  final AdminNode node;
  final List<_Box> children = [];
  double x = 0; // 子树左上角
  double y = 0;
  double width = _nodeW;
  _Box(this.node);
}

class _AdminUsersGraphState extends State<AdminUsersGraph> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  // ---------- 加盟树布局 ----------
  ({List<_Box> roots, Map<String, Offset> pos, Size size}) _layoutTree() {
    final nodes = widget.data.nodes;
    final byFid = <String, _Box>{for (final n in nodes) n.fid: _Box(n)};
    final roots = <_Box>[];
    for (final n in nodes) {
      final parent = n.parentFid == null ? null : byFid[n.parentFid];
      // 父节点不在（孤儿/被删）→ 当根画, 否则整棵子树会消失
      if (parent == null) {
        roots.add(byFid[n.fid]!);
      } else {
        parent.children.add(byFid[n.fid]!);
      }
    }

    double measure(_Box b) {
      if (b.children.isEmpty) {
        b.width = _nodeW;
        return b.width;
      }
      double w = 0;
      for (final c in b.children) {
        w += measure(c);
      }
      w += _gapX * (b.children.length - 1);
      b.width = w < _nodeW ? _nodeW : w;
      return b.width;
    }

    void place(_Box b, double left, double depth) {
      b.x = left;
      b.y = depth * _levelH;
      double cursor = left + (b.width - _childrenWidth(b)) / 2;
      for (final c in b.children) {
        place(c, cursor, depth + 1);
        cursor += c.width + _gapX;
      }
    }

    double total = 0;
    for (final r in roots) {
      total += measure(r) + _gapX * 2;
    }
    double cursor = 0;
    for (final r in roots) {
      place(r, cursor, 0);
      cursor += r.width + _gapX * 2;
    }

    final maxDepth = nodes.fold<int>(0, (m, n) => n.depth > m ? n.depth : m);
    final pos = <String, Offset>{};
    for (final n in nodes) {
      final b = byFid[n.fid];
      if (b == null) continue;
      // 节点在子树槽里居中
      pos[n.fid] = Offset(b.x + b.width / 2, b.y + _nodeH / 2);
    }
    final w = total <= 0 ? _nodeW : total;
    return (
      roots: roots,
      pos: pos,
      size: Size(
        w + _padX * 2,
        (maxDepth + 1) * _levelH + _padY * 2,
      ),
    );
  }

  double _childrenWidth(_Box b) {
    if (b.children.isEmpty) return 0;
    double w = 0;
    for (final c in b.children) {
      w += c.width;
    }
    return w + _gapX * (b.children.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final tree = _layoutTree();
    final isolated = data.notJoinedUsers;

    // 未加盟带: 按画布宽度分行平铺
    const isoPerRow = 5;
    final canvasW = tree.size.width < _isoSlotW * isoPerRow + _padX * 2
        ? _isoSlotW * isoPerRow + _padX * 2
        : tree.size.width;
    final isoRows = (isolated.length / isoPerRow).ceil();
    final isoTop = tree.size.height + (isolated.isEmpty ? 0 : 24);
    final canvasH = isoTop + isoRows * _isoSlotH + _padY;

    return ClipRect(
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 0.4,
        maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(80),
        child: SizedBox(
          width: canvasW,
          height: canvasH,
          child: Stack(
            children: [
              // 1) 边
              Positioned.fill(
                child: CustomPaint(
                  painter: _EdgePainter(
                    pos: tree.pos,
                    nodes: data.nodes,
                  ),
                ),
              ),
              // 2) 加盟节点
              for (final n in data.nodes)
                if (tree.pos[n.fid] != null)
                  Positioned(
                    left: tree.pos[n.fid]!.dx - _nodeW / 2,
                    top: tree.pos[n.fid]!.dy - _nodeH / 2,
                    width: _nodeW,
                    height: _nodeH,
                    child: _NodeCard(
                      title: n.name,
                      subtitle: n.hasAccount
                          ? (n.isRoot ? '根节点' : '第 ${n.depth + 1} 层')
                          : '无账号',
                      accountName: n.accountName,
                      avatarUrl: n.avatarUrl,
                      isMember: n.member,
                      noAccount: !n.hasAccount,
                      onTap: () => widget.onTapNode(n),
                    ),
                  ),
              // 3) 未加盟带 (分隔线 + 标题 + 独立节点)
              if (isolated.isNotEmpty) ...[
                Positioned(
                  left: _padX,
                  right: _padX,
                  top: tree.size.height + 4,
                  height: 1,
                  child: Container(color: const Color(0xFFE6E9E5)),
                ),
                Positioned(
                  left: _padX,
                  top: tree.size.height + 12,
                  child: Text(
                    '未加盟 · 独立节点 (${isolated.length})',
                    style: const TextStyle(
                      fontSize: AppTheme.fontSm,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (var i = 0; i < isolated.length; i++)
                  Positioned(
                    left: _padX + (i % isoPerRow) * _isoSlotW,
                    top: isoTop + 24 + (i ~/ isoPerRow) * _isoSlotH,
                    width: _isoSlotW,
                    height: _isoSlotH,
                    child: _NodeCard(
                      title: isolated[i].name,
                      subtitle: '未加盟',
                      avatarUrl: isolated[i].avatarUrl,
                      isMember: isolated[i].member.isMember,
                      onTap: () => widget.onTapUser(isolated[i]),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- 单个节点卡 ----------
class _NodeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? accountName;
  final String? avatarUrl;
  final bool isMember;
  final bool noAccount;
  final VoidCallback onTap;

  const _NodeCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accountName,
    this.avatarUrl,
    this.isMember = false,
    this.noAccount = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          MemberAvatar(
            avatarUrl: avatarUrl,
            name: title,
            size: 48,
            isMember: isMember,
            noAccount: noAccount,
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTheme.fontSm,
              fontWeight: FontWeight.w600,
              color: noAccount ? AppTheme.textSecondary : AppTheme.textPrimary,
            ),
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: AppTheme.fontXs,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- 连线 ----------
class _EdgePainter extends CustomPainter {
  final Map<String, Offset> pos;
  final List<AdminNode> nodes;

  _EdgePainter({required this.pos, required this.nodes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFC3CDC6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final n in nodes) {
      if (n.parentFid == null) continue;
      final from = pos[n.parentFid];
      final to = pos[n.fid];
      if (from == null || to == null) continue;
      // 竖直到层间中点再折——避免长斜线穿过其他节点
      final midY = from.dy + (to.dy - from.dy) / 2;
      final path = Path()
        ..moveTo(from.dx, from.dy + _nodeH / 2)
        ..lineTo(from.dx, midY)
        ..lineTo(to.dx, midY)
        ..lineTo(to.dx, to.dy - _nodeH / 2);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.nodes != nodes || old.pos != pos;
}
