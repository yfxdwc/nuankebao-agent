// ============================================
// 加盟二叉树 CustomPainter (Plan F3)
// 中老年大字 + 大节点 + 自定义布局
// ============================================

import 'package:flutter/material.dart';
import '../../../../core/models/franchisee.dart';
import '../../../../core/theme/app_theme.dart';

class TreeLayout {
  static const double nodeRadius = 44;       // 节点半径 (88pt 直径)
  static const double nodeSize = 88;         // 节点直径
  static const double levelHeight = 140;     // 层间距
  static const double minNodeSpacing = 220;  // 节点最小水平间距
  static const double padding = 24;          // 画布边距

  /// 计算每个节点的中心坐标 (相对于画布)
  static Map<String, Offset> computePositions(
    FranchiseeTreeNode root,
    Size canvas,
  ) {
    final positions = <String, Offset>{};
    final subtreeWidths = <String, double>{};

    // Step 1: post-order 计算每个子树所需宽度
    _computeSubtreeWidth(root, subtreeWidths, 0);

    // Step 2: pre-order 计算每个节点的实际坐标
    final canvasCenterX = canvas.width / 2;
    _computePositions(
      root,
      canvasCenterX,
      padding + nodeRadius, // 根节点 y 位置
      subtreeWidths,
      positions,
    );

    return positions;
  }

  static double _computeSubtreeWidth(
    FranchiseeTreeNode node,
    Map<String, double> widths,
    int depth,
  ) {
    if (node.children.isEmpty) {
      widths[node.id] = minNodeSpacing;
      return minNodeSpacing;
    }
    double totalWidth = 0;
    for (final child in node.children) {
      totalWidth += _computeSubtreeWidth(child, widths, depth + 1);
    }
    widths[node.id] = totalWidth.clamp(minNodeSpacing, double.infinity);
    return widths[node.id]!;
  }

  static void _computePositions(
    FranchiseeTreeNode node,
    double centerX,
    double centerY,
    Map<String, double> subtreeWidths,
    Map<String, Offset> positions,
  ) {
    positions[node.id] = Offset(centerX, centerY);

    if (node.children.isEmpty) return;

    final childY = centerY + levelHeight;
    final totalChildWidth = subtreeWidths[node.id]!;
    double currentX = centerX - totalChildWidth / 2;

    for (final child in node.children) {
      final childWidth = subtreeWidths[child.id]!;
      final childCenterX = currentX + childWidth / 2;
      _computePositions(
        child,
        childCenterX,
        childY,
        subtreeWidths,
        positions,
      );
      currentX += childWidth;
    }
  }

  /// 计算画布总尺寸 (基于节点数和深度)
  static Size computeCanvasSize(FranchiseeTreeNode root, int maxDepth) {
    final levels = _countLevels(root, 0);
    final maxNodesAtLevel = _maxNodesAtLevel(root, 0);
    final width = (maxNodesAtLevel * minNodeSpacing).clamp(400.0, double.infinity);
    final height = padding * 2 + (levels) * levelHeight + nodeSize;
    return Size(width, height);
  }

  static int _countLevels(FranchiseeTreeNode node, int current) {
    if (node.children.isEmpty) return current + 1;
    int max = current + 1;
    for (final child in node.children) {
      final childLevels = _countLevels(child, current + 1);
      if (childLevels > max) max = childLevels;
    }
    return max;
  }

  static int _maxNodesAtLevel(FranchiseeTreeNode node, int level) {
    final byLevel = <int, int>{};
    _countByLevel(node, 0, byLevel);
    int max = 0;
    byLevel.forEach((_, count) {
      if (count > max) max = count;
    });
    return max;
  }

  static void _countByLevel(
    FranchiseeTreeNode node,
    int level,
    Map<int, int> counts,
  ) {
    counts[level] = (counts[level] ?? 0) + 1;
    for (final child in node.children) {
      _countByLevel(child, level + 1, counts);
    }
  }
}

// ============================================
// Painter
// ============================================

class FranchiseTreePainter extends CustomPainter {
  final FranchiseeTreeNode root;
  final Map<String, Offset> positions;
  final String? highlightedNodeId;

  /// 搜索匹配节点 id 集合 (来自页面顶部搜索框).
  /// 与 highlightedNodeId 是独立的两条高亮路径, painter 取并集渲染.
  /// - null = 无搜索 (不参与高亮)
  /// - 空 Set = 有搜索但 0 匹配 (与 null 表现一致, 不污染)
  /// - 非空 Set = 这些 id 全部高亮
  final Set<String>? searchMatchedIds;

  final String? currentUserId; // 根节点标识 (绿色"我")

  FranchiseTreePainter({
    required this.root,
    required this.positions,
    this.highlightedNodeId,
    this.searchMatchedIds,
    this.currentUserId,
  });

  /// 判断某节点是否被「任何来源」高亮 (长按 / 搜索 / 并集)
  bool _isAnyHighlight(String nodeId) {
    if (highlightedNodeId != null && highlightedNodeId == nodeId) return true;
    if (searchMatchedIds != null && searchMatchedIds!.contains(nodeId)) return true;
    return false;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawEdges(canvas, root);
    _drawNodes(canvas, root);
  }

  void _drawEdges(Canvas canvas, FranchiseeTreeNode node) {
    final nodePos = positions[node.id];
    if (nodePos == null) return;

    for (final child in node.children) {
      final childPos = positions[child.id];
      if (childPos == null) continue;

      // 是否被搜索高亮 (任一端命中即加粗高亮, 否则淡化)
      final edgeHighlighted =
          _isAnyHighlight(node.id) || _isAnyHighlight(child.id);
      final color = edgeHighlighted
          ? AppTheme.accent.withOpacity(0.9)
          : AppTheme.primaryDark.withOpacity(0.35);
      final stroke = edgeHighlighted ? 3.5 : 2.0;

      // 父→子连线 (用柔和的曲线)
      final paint = Paint()
        ..color = color
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke;

      final path = Path();
      // 从父节点底部到子节点顶部
      final startY = nodePos.dy + TreeLayout.nodeRadius;
      final endY = childPos.dy - TreeLayout.nodeRadius;
      final midY = (startY + endY) / 2;
      path.moveTo(nodePos.dx, startY);
      path.quadraticBezierTo(nodePos.dx, midY, childPos.dx, endY);
      canvas.drawPath(path, paint);

      _drawEdges(canvas, child);
    }
  }

  void _drawNodes(Canvas canvas, FranchiseeTreeNode node) {
    final pos = positions[node.id];
    if (pos == null) return;

    final isCurrentUser = currentUserId != null && node.id == currentUserId;
    final isHighlighted = _isAnyHighlight(node.id);
    // 「有高亮但当前节点不在高亮集合内」 = 淡化 (长按 / 搜索只要触发, 整体淡化其余)
    final anyHighlightActive = highlightedNodeId != null ||
        (searchMatchedIds != null && searchMatchedIds!.isNotEmpty);
    final isFaded = anyHighlightActive && !isHighlighted;

    _drawNodeCircle(canvas, pos, node, isCurrentUser, isHighlighted, isFaded);
    _drawNodeLabel(canvas, pos, node, isCurrentUser, isFaded);

    for (final child in node.children) {
      _drawNodes(canvas, child);
    }
  }

  void _drawNodeCircle(
    Canvas canvas,
    Offset center,
    FranchiseeTreeNode node,
    bool isCurrentUser,
    bool isHighlighted,
    bool isFaded,
  ) {
    // 1. 阴影 (highlight 时加)
    if (isHighlighted) {
      canvas.drawCircle(
        center,
        TreeLayout.nodeRadius + 6,
        Paint()
          ..color = AppTheme.accent.withOpacity(0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // 2. 主圆 (当前用户=绿, 其他=紫; 淡化时用低饱和灰)
    final Color color;
    if (isFaded) {
      color = AppTheme.franchisee.withOpacity(0.35);
    } else if (isCurrentUser) {
      color = AppTheme.primary;
    } else {
      color = AppTheme.franchisee;
    }
    canvas.drawCircle(
      center,
      TreeLayout.nodeRadius,
      Paint()..color = color,
    );

    // 3. 内圆 (浅色)
    canvas.drawCircle(
      center,
      TreeLayout.nodeRadius - 4,
      Paint()..color = Colors.white.withOpacity(isFaded ? 0.1 : 0.2),
    );

    // 4. 首字母 (大字)
    final initial = node.name.isNotEmpty ? node.name[0] : '?';
    final tp = TextPainter(
      text: TextSpan(
        text: initial,
        style: TextStyle(
          fontSize: 32,
          color: isFaded ? Colors.white.withOpacity(0.5) : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  void _drawNodeLabel(
    Canvas canvas,
    Offset center,
    FranchiseeTreeNode node,
    bool isCurrentUser,
    bool isFaded,
  ) {
    // 姓名 (圆下方)
    final name = node.name;
    final tpName = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          fontSize: 16,
          color: isFaded
              ? AppTheme.textPrimary.withOpacity(0.4)
              : AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 100);
    tpName.paint(
      canvas,
      Offset(center.dx - tpName.width / 2, center.dy + TreeLayout.nodeRadius + 6),
    );

    // "我" 标记 (根节点)
    if (isCurrentUser) {
      final tpMe = TextPainter(
        text: TextSpan(
          text: '(我)',
          style: TextStyle(
            fontSize: 12,
            color: isFaded
                ? AppTheme.primary.withOpacity(0.5)
                : AppTheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tpMe.paint(
        canvas,
        Offset(center.dx - tpMe.width / 2, center.dy + TreeLayout.nodeRadius + 26),
      );
    }

    // 位置标签 (左/右)
    if (node.placementSide != null) {
      final tpSide = TextPainter(
        text: TextSpan(
          text: node.placementSide == 'left' ? '← 左线' : '右线 →',
          style: TextStyle(
            fontSize: 11,
            color: node.placementSide == 'left'
                ? (isFaded
                    ? AppTheme.primaryDark.withOpacity(0.4)
                    : AppTheme.primaryDark)
                : (isFaded
                    ? AppTheme.franchisee.withOpacity(0.4)
                    : AppTheme.franchisee),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tpSide.paint(
        canvas,
        Offset(center.dx - tpSide.width / 2, center.dy + TreeLayout.nodeRadius + 44),
      );
    }
  }

  @override
  bool shouldRepaint(covariant FranchiseTreePainter old) {
    if (old.root != root ||
        old.highlightedNodeId != highlightedNodeId ||
        old.currentUserId != currentUserId) {
      return true;
    }
    // searchMatchedIds: Set 默认 == 是 identity, 内容比较需手写
    final a = old.searchMatchedIds;
    final b = searchMatchedIds;
    if (identical(a, b)) return false;
    if (a == null || b == null) return true;
    if (a.length != b.length) return true;
    for (final id in a) {
      if (!b.contains(id)) return true;
    }
    return false;
  }
}