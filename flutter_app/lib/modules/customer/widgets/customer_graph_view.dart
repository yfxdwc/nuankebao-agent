// ============================================
// 客户推荐关系图 (客户页图谱视图)
// ============================================
// 设计:
//   - 节点 = 客户 (圆头像 + 名字首字母 + 名字)
//   - 边 = 推荐关系 (referrer → 被推荐人)
//   - 根节点 = 无推荐人的客户 (referrerId == null), 渲染为绿色「我」的源头
//     注意: 客户的「根」不是 sales 自己, 而是「自然到店的客户」, 多个根并存
//   - 长按节点 → 高亮该节点向上的所有祖先链 + 向下的所有子孙链 (其余淡化)
//   - 点击节点 → 进入客户详情
//   - InteractiveViewer 包装 → 支持双指缩放 + 单指拖动 (大网络需要)
// ============================================
// vibe: 中老年女性销售, 字号大, 节点 80pt+
// 不要 dashboard 复杂图表, 不要炫技动画
// ============================================

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../../../core/models/customer.dart';
import '../../../core/theme/app_theme.dart';

// ============================================
// 树节点 (从 CustomerGraphNode 派生, 兼容任意子树数)
// ============================================

class _GraphNode {
  final CustomerGraphNode data;
  final List<_GraphNode> children;
  _GraphNode({required this.data, required this.children});
}

// ============================================
// 图谱布局算法 (复用 TreeLayout 思路, 适配任意子树)
// ============================================

class _GraphLayout {
  static const double nodeSize = 80;         // 节点直径 (中老年可点击)
  static const double nodeRadius = 40;
  static const double levelHeight = 130;     // 层间距
  static const double minNodeSpacing = 140;  // 节点最小水平间距
  static const double edgePadding = 32;      // 画布边距

  /// 从节点列表构建一棵树 (可能有多个根)
  static List<_GraphNode> buildForest(List<CustomerGraphNode> nodes) {
    if (nodes.isEmpty) return [];
    final byId = <String, CustomerGraphNode>{};
    for (final n in nodes) {
      byId[n.id] = n;
    }
    // children map: parentId -> [child...]
    final childMap = <String?, List<CustomerGraphNode>>{};
    for (final n in nodes) {
      childMap.putIfAbsent(n.referrerId, () => []).add(n);
    }
    // 构建森林: 根 = referrerId == null 的节点, 或 referrerId 不在 nodes 里的节点
    final roots = nodes
        .where((n) => n.referrerId == null || !byId.containsKey(n.referrerId))
        .toList();
    // 也包括 referrerId 不在当前可见范围的节点 (孤儿, 视作根)
    final rootIds = roots.map((r) => r.id).toSet();
    return roots.map((r) => _buildNode(r, childMap)).toList();
  }

  static _GraphNode _buildNode(
    CustomerGraphNode data,
    Map<String?, List<CustomerGraphNode>> childMap,
  ) {
    final children = (childMap[data.id] ?? const [])
        .map((c) => _buildNode(c, childMap))
        .toList();
    return _GraphNode(data: data, children: children);
  }

  /// 计算每个节点在画布中的 (x, y) 坐标
  /// roots = 多个根, 水平铺开, 每个子树独立计算
  static Map<String, Offset> computePositions(List<_GraphNode> roots, Size canvas) {
    final positions = <String, Offset>{};
    if (roots.isEmpty) return positions;

    // Step 1: post-order 计算每个子树宽度
    final widths = <String, double>{};
    for (final r in roots) {
      _computeSubtreeWidth(r, widths);
    }

    // Step 2: pre-order 分配坐标
    // 多根: 水平铺, 第一个根从画布左边 padding 开始, 后续接续
    final totalWidth = widths.values.fold<double>(0, (a, b) => a + b);
    double currentX = (canvas.width - totalWidth) / 2;
    if (currentX < edgePadding) currentX = edgePadding;

    for (final r in roots) {
      final w = widths[r.data.id]!;
      final centerX = currentX + w / 2;
      _computePositions(
        r,
        centerX,
        edgePadding + nodeRadius,
        widths,
        positions,
      );
      currentX += w;
    }

    return positions;
  }

  static double _computeSubtreeWidth(_GraphNode node, Map<String, double> widths) {
    if (node.children.isEmpty) {
      widths[node.data.id] = minNodeSpacing;
      return minNodeSpacing;
    }
    double total = 0;
    for (final c in node.children) {
      total += _computeSubtreeWidth(c, widths);
    }
    widths[node.data.id] = total.clamp(minNodeSpacing, double.infinity);
    return widths[node.data.id]!;
  }

  static void _computePositions(
    _GraphNode node,
    double centerX,
    double centerY,
    Map<String, double> widths,
    Map<String, Offset> positions,
  ) {
    positions[node.data.id] = Offset(centerX, centerY);
    if (node.children.isEmpty) return;
    final childY = centerY + levelHeight;
    final totalChildWidth = widths[node.data.id]!;
    double currentX = centerX - totalChildWidth / 2;
    for (final c in node.children) {
      final cw = widths[c.data.id]!;
      _computePositions(c, currentX + cw / 2, childY, widths, positions);
      currentX += cw;
    }
  }

  /// 画布尺寸估算 (基于节点总数和深度)
  static Size estimateCanvasSize(List<_GraphNode> roots) {
    if (roots.isEmpty) return const Size(400, 300);
    int maxDepth = 0;
    int maxNodesAtAnyLevel = 0;
    final byLevel = <int, int>{};
    void walk(_GraphNode n, int d) {
      byLevel[d] = (byLevel[d] ?? 0) + 1;
      if (d > maxDepth) maxDepth = d;
      for (final c in n.children) {
        walk(c, d + 1);
      }
    }
    for (final r in roots) {
      walk(r, 0);
    }
    byLevel.forEach((_, c) {
      if (c > maxNodesAtAnyLevel) maxNodesAtAnyLevel = c;
    });
    final width = (maxNodesAtAnyLevel * minNodeSpacing + edgePadding * 2)
        .clamp(400.0, 2400.0);
    final height = edgePadding * 2 + (maxDepth + 1) * levelHeight + nodeSize;
    return Size(width, height);
  }
}

// ============================================
// 高亮路径计算 (向上祖先链 + 向下子孙链)
// ============================================

Set<String> _computeHighlightedPath(
  String rootId,
  Map<String, List<String>> childrenByParent,
) {
  final visited = <String>{};
  void dfs(String id) {
    if (visited.contains(id)) return;
    visited.add(id);
    for (final c in childrenByParent[id] ?? const <String>[]) {
      dfs(c);
    }
  }
  dfs(rootId);
  return visited;
}

// ============================================
// 主 widget
// ============================================

class CustomerGraphView extends StatefulWidget {
  final CustomerGraph graph;

  /// 搜索关键词 (来自页面顶部搜索框, 在图谱视图下高亮匹配节点)
  /// - 非空: 名字 contains(query) 的节点被标记为「搜索匹配」, 渲染上加 ring
  /// - 空 / null: 不影响, 长按高亮独立工作
  final String? searchQuery;

  const CustomerGraphView({
    super.key,
    required this.graph,
    this.searchQuery,
  });

  @override
  State<CustomerGraphView> createState() => _CustomerGraphViewState();
}

class _CustomerGraphViewState extends State<CustomerGraphView> {
  String? _highlightedId;
  final _transformController = TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  /// 计算搜索匹配的节点 id 集合 (大小写不敏感, 按名字 contains)
  /// 返回 null = 无搜索词 (不参与高亮); 空 Set = 有搜索词但 0 匹配
  Set<String>? _computeSearchMatches(
    List<CustomerGraphNode> nodes,
    String query,
  ) {
    if (query.isEmpty) return null;
    final q = query.toLowerCase();
    return {
      for (final n in nodes)
        if (n.name.toLowerCase().contains(q)) n.id,
    };
  }

  @override
  Widget build(BuildContext context) {
    final nodes = widget.graph.nodes;
    if (nodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.account_tree_outlined, size: 80, color: AppTheme.textSecondary),
            SizedBox(height: 16),
            Text(
              '还没有客户,无法生成图谱',
              style: TextStyle(fontSize: AppTheme.fontMd, color: AppTheme.textSecondary),
            ),
            SizedBox(height: 8),
            Text(
              '添加客户后, 在编辑客户时设置「推荐人」即可',
              style: TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    // 构建树
    final roots = _GraphLayout.buildForest(nodes);
    final canvasSize = _GraphLayout.estimateCanvasSize(roots);
    final positions = _GraphLayout.computePositions(roots, canvasSize);

    // 构建 parentId -> [childIds] 映射 (用于高亮路径)
    final childrenByParent = <String, List<String>>{};
    for (final n in nodes) {
      if (n.referrerId != null) {
        childrenByParent.putIfAbsent(n.referrerId!, () => []).add(n.id);
      }
    }

    // 长按高亮 = 单个节点 + 它向下的子孙链 (现有语义)
    final longPressHighlighted = _highlightedId == null
        ? null
        : _computeHighlightedPath(_highlightedId!, childrenByParent);

    // 搜索高亮 = 名字匹配的节点集合 (仅匹配节点本身, 不扩展链, 与长按区分)
    final searchMatches = _computeSearchMatches(nodes, widget.searchQuery ?? '');

    // 合并: 两者任一为高亮即高亮; 任一触发即视为「有高亮 → 淡出未高亮」
    Set<String>? highlighted;
    if (longPressHighlighted != null || (searchMatches != null && searchMatches.isNotEmpty)) {
      highlighted = <String>{
        ...?longPressHighlighted,
        ...?searchMatches,
      };
    }

    return InteractiveViewer(
      transformationController: _transformController,
      minScale: 0.5,
      maxScale: 2.5,
      boundaryMargin: const EdgeInsets.all(200),
      child: SizedBox(
        width: canvasSize.width,
        height: canvasSize.height,
        child: Stack(
          children: [
            // Layer 1: 边
            Positioned.fill(
              child: CustomPaint(
                painter: _CustomerGraphPainter(
                  nodes: nodes,
                  positions: positions,
                  highlighted: highlighted,
                  childrenByParent: childrenByParent,
                ),
              ),
            ),
            // Layer 2: 节点 (可点击 + 长按)
            ...nodes.map((n) {
              final pos = positions[n.id];
              if (pos == null) return const SizedBox.shrink();
              final isLongPressHit = longPressHighlighted?.contains(n.id) ?? false;
              final isSearchHit = searchMatches?.contains(n.id) ?? false;
              final isHighlighted = isLongPressHit || isSearchHit;
              final isFaded = highlighted != null && !isHighlighted;
              return Positioned(
                left: pos.dx - _GraphLayout.nodeRadius,
                top: pos.dy - _GraphLayout.nodeRadius,
                child: _GraphNodeWidget(
                  node: n,
                  isHighlighted: isHighlighted,
                  isFaded: isFaded,
                  isRoot: n.referrerId == null,
                  onTap: () => context.push('/customers/${n.id}'),
                  onLongPress: () {
                    setState(() {
                      _highlightedId = _highlightedId == n.id ? null : n.id;
                    });
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ============================================
// Painter (边)
// ============================================

class _CustomerGraphPainter extends CustomPainter {
  final List<CustomerGraphNode> nodes;
  final Map<String, Offset> positions;
  final Set<String>? highlighted;
  final Map<String, List<String>> childrenByParent;

  _CustomerGraphPainter({
    required this.nodes,
    required this.positions,
    required this.highlighted,
    required this.childrenByParent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in nodes) {
      final fromPos = positions[n.id];
      if (fromPos == null) continue;
      if (n.referrerId == null) continue;
      final toPos = positions[n.referrerId!];
      if (toPos == null) continue;

      final inHighlight = highlighted?.contains(n.id) ?? true;
      final color = !inHighlight
          ? AppTheme.textSecondary.withOpacity(0.15)
          : AppTheme.primary.withOpacity(0.7);
      final stroke = !inHighlight ? 1.5 : 3.0;

      final paint = Paint()
        ..color = color
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      final startY = toPos.dy + _GraphLayout.nodeRadius;
      final endY = fromPos.dy - _GraphLayout.nodeRadius;
      final midY = (startY + endY) / 2;
      path.moveTo(toPos.dx, startY);
      path.quadraticBezierTo(toPos.dx, midY, fromPos.dx, endY);
      canvas.drawPath(path, paint);

      // 箭头 (highlight 时显示)
      if (inHighlight && highlighted != null) {
        _drawArrowhead(canvas, toPos, fromPos, paint..color);
      }
    }
  }

  void _drawArrowhead(Canvas canvas, Offset from, Offset to, Paint basePaint) {
    // 箭头尖在 to 附近 (小圆点, 避免复杂三角计算)
    final dx = to.dx - from.dx;
    final dy = to.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist == 0) return;
    final ux = dx / dist;
    final uy = dy / dist;
    // 箭头尖位置: 从 to 沿反方向退一些, 落在节点边缘附近
    final tipX = to.dx - ux * _GraphLayout.nodeRadius * 0.5;
    final tipY = to.dy - uy * _GraphLayout.nodeRadius * 0.5;
    final p = Paint()..color = basePaint.color;
    canvas.drawCircle(Offset(tipX, tipY), 4, p);
  }

  @override
  bool shouldRepaint(covariant _CustomerGraphPainter old) {
    return old.nodes != nodes ||
        old.highlighted != highlighted ||
        old.childrenByParent != childrenByParent;
  }
}

// ============================================
// 节点 widget (头像 + 名字 + 触摸交互)
// ============================================

class _GraphNodeWidget extends StatelessWidget {
  final CustomerGraphNode node;
  final bool isHighlighted;
  final bool isFaded;
  final bool isRoot;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GraphNodeWidget({
    required this.node,
    required this.isHighlighted,
    required this.isFaded,
    required this.isRoot,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final initial = node.name.isNotEmpty ? node.name[0] : '?';
    final ringColor = isHighlighted
        ? AppTheme.accent
        : isRoot
            ? AppTheme.primary
            : AppTheme.franchisee;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isFaded ? 0.35 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头像圆 + 名字首字母
            Container(
              width: _GraphLayout.nodeSize,
              height: _GraphLayout.nodeSize,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                shape: BoxShape.circle,
                border: Border.all(
                  color: ringColor,
                  width: isHighlighted ? 4 : 2,
                ),
                boxShadow: isHighlighted
                    ? [
                        BoxShadow(
                          color: AppTheme.accent.withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: ringColor,
                ),
              ),
            ),
            const SizedBox(height: 4),
            // 名字
            Container(
              constraints: const BoxConstraints(maxWidth: 100),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isHighlighted ? ringColor : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Text(
                node.name,
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
