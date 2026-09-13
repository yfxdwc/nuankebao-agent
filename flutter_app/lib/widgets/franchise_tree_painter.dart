// ============================================
// 加盟二叉树 CustomPainter (Plan F3)
// 中老年大字 + 大节点 + 自定义布局
// ============================================

import 'package:flutter/material.dart';
import '../models/franchisee.dart';
import '../theme/app_theme.dart';

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
  final String? currentUserId; // 根节点标识 (绿色"我")

  FranchiseTreePainter({
    required this.root,
    required this.positions,
    this.highlightedNodeId,
    this.currentUserId,
  });

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

      // 父→子连线 (用柔和的曲线)
      final paint = Paint()
        ..color = AppTheme.primaryDark.withOpacity(0.6)
        ..strokeWidth = 2
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
    final isHighlighted = node.id == highlightedNodeId;

    _drawNodeCircle(canvas, pos, node, isCurrentUser, isHighlighted);
    _drawNodeLabel(canvas, pos, node, isCurrentUser);

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

    // 2. 主圆 (当前用户=绿, 其他=紫)
    final color = isCurrentUser ? AppTheme.primary : AppTheme.franchisee;
    canvas.drawCircle(
      center,
      TreeLayout.nodeRadius,
      Paint()..color = color,
    );

    // 3. 内圆 (浅色)
    canvas.drawCircle(
      center,
      TreeLayout.nodeRadius - 4,
      Paint()..color = Colors.white.withOpacity(0.2),
    );

    // 4. 首字母 (大字)
    final initial = node.name.isNotEmpty ? node.name[0] : '?';
    final tp = TextPainter(
      text: TextSpan(
        text: initial,
        style: const TextStyle(
          fontSize: 32,
          color: Colors.white,
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
  ) {
    // 姓名 (圆下方)
    final name = node.name;
    final tpName = TextPainter(
      text: TextSpan(
        text: name,
        style: const TextStyle(
          fontSize: 16,
          color: AppTheme.textPrimary,
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
        text: const TextSpan(
          text: '(我)',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.primary,
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
                ? AppTheme.primaryDark
                : AppTheme.franchisee,
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
    return old.root != root ||
        old.highlightedNodeId != highlightedNodeId ||
        old.currentUserId != currentUserId;
  }
}