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

import '../core/theme/tokens.g.dart';
class AdminUsersGraph extends StatefulWidget {
  final AdminUsersOverview data;
  final void Function(AdminNode node) onTapNode;
  final void Function(AdminUser user) onTapUser;

  /// 初始视图: false (默认) = 对准树根 1:1 (名字看得清, 大树要自己拖);
  ///           true = 缩到装下整张画布 (看结构, 字会变小)。
  /// 页面用「回到树根 / 适应屏幕」两个按钮重挂载本组件来切换 (见 _graphEpoch)。
  final bool fitAll;

  const AdminUsersGraph({
    super.key,
    required this.data,
    required this.onTapNode,
    required this.onTapUser,
    this.fitAll = false,
  });

  @override
  State<AdminUsersGraph> createState() => _AdminUsersGraphState();
}

// ---------- 布局常量 ----------
const double _nodeW = 108; // 节点槽宽
const double _nodeH = 112; // 节点高 (头像 48 + 名字 + 提示)
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

  /// 首次布局后把视图居中到树根 (否则从画布左上角开始 = 一大片空白,
  /// 截图实测: 根看不见, 用户以为"图没出来")
  bool _centered = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  // ---------- 加盟树布局 ----------
  ({List<_Box> roots, Map<String, Offset> pos, Size size, double topPad})
      _layoutTree() {
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

    // 多棵树时在最上面留一行放「第 N 棵」标号 (单棵树不占地方)
    final topPad = roots.length > 1 ? 26.0 : 0.0;

    void place(_Box b, double left, double depth) {
      b.x = left;
      b.y = topPad + depth * _levelH;
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
      topPad: topPad,
      size: Size(
        w + _padX * 2,
        topPad + (maxDepth + 1) * _levelH + _padY * 2,
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
    // 未加盟带**跟着画布居中**: 贴左边的话, 视图居中到树根后它整条都在屏幕外
    // (2026-09-21 截图实测: 4 个未加盟只看得见最右 1 个)
    final isoRowW =
        (isolated.length < isoPerRow ? isolated.length : isoPerRow) * _isoSlotW;
    final isoLeft = (canvasW - isoRowW) / 2;

    // 首次挂载 (或点两个视图按钮重挂载后) → 摆好初始视图。
    // 不摆的话 viewport 从画布左上角开始, 根节点看不见 = 用户以为"图没出来"。
    if (!_centered) {
      _centered = true;
      final rootX = tree.roots.isEmpty
          ? canvasW / 2
          : (tree.pos[tree.roots.first.node.fid]?.dx ?? canvasW / 2);
      _applyInitialView(
        rootCenterX: rootX,
        canvasW: canvasW,
        viewportW: MediaQuery.of(context).size.width,
        fitAll: widget.fitAll,
      );
    }

    return ClipRect(
      child: InteractiveViewer(
        transformationController: _transform,
        // ⚠ 必须 false: 默认 true 会把画布压成视口大小 → Stack 裁掉画布中心的
        //   根节点 → 整页空白 (2026-09-21 截图实测)。false = 子节点按自身尺寸布局。
        constrained: false,
        minScale: 0.4,
        maxScale: 2.5,
        boundaryMargin: const EdgeInsets.all(AppSpace.s80),
        child: SizedBox(
          width: canvasW,
          height: canvasH,
          child: Stack(
            children: [
              // 1) 边
              Positioned.fill(
                child: CustomPaint(
                  painter: _EdgePainter(pos: tree.pos, nodes: data.nodes),
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
                      avatarUrl: n.avatarUrl,
                      isMember: n.member,
                      noAccount: !n.hasAccount,
                      onTap: () => widget.onTapNode(n),
                    ),
                  ),
              // 2.5) 多棵树的标号 (不同加盟系统 / 同一系统的不同枝)
              if (tree.roots.length > 1)
                for (var i = 0; i < tree.roots.length; i++)
                  if (tree.pos[tree.roots[i].node.fid] != null)
                    Positioned(
                      left: tree.pos[tree.roots[i].node.fid]!.dx - 70,
                      top: tree.topPad - 24,
                      width: 140,
                      child: Text(
                        '第 ${i + 1} 棵',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: AppTheme.fontSm,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
              // 3) 未加盟带 (分隔线 + 标题 + 独立节点)
              if (isolated.isNotEmpty) ...[
                Positioned(
                  left: _padX,
                  right: _padX,
                  top: tree.size.height + 4,
                  height: 1,
                  child: Container(color: AppColors.divider),
                ),
                Positioned(
                  left: AppSpace.s0,
                  width: canvasW,
                  top: tree.size.height + 12,
                  child: Text(
                    '未加盟 · 独立节点 (${isolated.length})',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: AppTheme.fontSm,
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (var i = 0; i < isolated.length; i++)
                  Positioned(
                    left: isoLeft + (i % isoPerRow) * _isoSlotW,
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

  /// 摆初始视图 (首次挂载 / 点「回到树根」「适应屏幕」都走这里)
  ///
  /// 两种模式, 因为一张 2000pt 宽的树**装不进手机屏**:
  ///   - 1:1 对准树根 (默认): 名字看得清, 但只看得到根附近 —— 大树要靠拖动/双指缩放
  ///   - 适应屏幕: 整张画布缩到屏幕里 (看结构; 20+ 节点的树字会小到看不清)
  /// 硬要"又全又清楚"是做不到的, 所以给两个按钮让用户自己选, 别替他决定
  void _applyInitialView({
    required double rootCenterX,
    required double canvasW,
    required double viewportW,
    required bool fitAll,
  }) {
    if (viewportW <= 0) return;
    if (fitAll) {
      // 0.15 下限: 防止极端宽的画布算出接近 0 的缩放 (整张图变一个点)
      final scale = ((viewportW - 16) / canvasW).clamp(0.15, 1.0);
      final dx = (viewportW - canvasW * scale) / 2;
      _transform.value = Matrix4.identity()
        ..translate(dx, 24.0)
        ..scale(scale);
      return;
    }
    // 1:1 对准树根: 根横向居中, 纵向留 24pt 顶
    _transform.value = Matrix4.identity()
      ..translate(viewportW / 2 - rootCenterX, 24.0);
  }
}

// ---------- 单个节点卡 ----------
class _NodeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? avatarUrl;
  final bool isMember;
  final bool noAccount;
  final VoidCallback onTap;

  const _NodeCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.avatarUrl,
    this.isMember = false,
    this.noAccount = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.r12),
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
          const SizedBox(height: AppSpace.s6),
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
      ..color = AppColors.border
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
