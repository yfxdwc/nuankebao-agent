// ============================================
// 加盟树 CustomPainter (Plan F3 → v2 双主线「对碰」布局)
//
// 布局规则 (主人 2026-09-17 拍):
//   1. 从「我」开始分左右两条主线, 两条主线是**自上而下的直线**且互相平行
//   2. 主线上每层: 同侧子节点续主线 (同侧断了用另一侧接, 主线不断)
//   3. 非主线节点往**这两条线的外侧**分裂 (左腿往左, 右腿往右), 一层一列
//   4. 左右主线同层节点**成对排列** (对碰奖视角: L1↔R1, L2↔R2 ...)
//
// 交互 (主人 2026-09-17 拍):
//   - 单击节点: 突显该节点 + 高亮 它→「我」整条线 + 弱化其他
//   - 长按节点: 跳加盟商详情
// ============================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../../core/models/franchisee.dart';
import '../../../../core/theme/app_theme.dart';

// ============================================
// 布局结果
// ============================================

class TreeLayoutResult {
  /// id → 节点中心坐标 (画布坐标系)
  final Map<String, Offset> positions;

  /// id → 列号 (0 = 主线列, k = 外侧第 k 列)
  final Map<String, int> columns;

  /// id → 层号 (0 = 根)
  final Map<String, int> depths;

  /// 两条主线上的节点 id (画连线时加粗)
  final Set<String> spineIds;

  /// A线 / B线 节点 id (从「我」左边/右边下去的整条腿, 含侧枝)
  final Set<String> aLineIds;
  final Set<String> bLineIds;

  /// 左/右腿各用了多少外侧列
  final int leftColumns;
  final int rightColumns;

  /// 内容总高度 (根圆顶 → 最下层名字底) — 「回到我」算初始缩放用
  final double contentHeight;

  final Size canvasSize;

  const TreeLayoutResult({
    required this.positions,
    required this.columns,
    required this.depths,
    required this.spineIds,
    required this.aLineIds,
    required this.bLineIds,
    required this.leftColumns,
    required this.rightColumns,
    required this.contentHeight,
    required this.canvasSize,
  });
}

// ============================================
// 布局算法 (双主线 + 外侧展开)
// ============================================

class TreeLayout {
  static const double nodeRadius = 44;       // 节点半径 (88pt 直径)
  static const double nodeSize = 88;         // 节点直径
  static const double levelHeight = 140;     // 层间距 (上下)
  static const double columnWidth = 180;     // 列间距 (外侧展开)
  static const double spineOffset = 90;      // 中轴 → 主线列距离 (左右主线相距 180)
  static const double padding = 40;          // 画布边距
  static const double labelMaxWidth = 160;   // 名字最大宽 (列距 - 20, 不左右串行)

  /// 计算双主线布局
  ///
  /// [maxDepth] 最深渲染层数 (0 = 只有根)
  static TreeLayoutResult compute(
    FranchiseeTreeNode root, {
    int maxDepth = 3,
  }) {
    final positions = <String, Offset>{};
    final columns = <String, int>{};
    final depths = <String, int>{};
    final spine = <String>{};
    final aLine = <String>{};
    final bLine = <String>{};

    double yOf(int depth) => padding + nodeRadius + depth * levelHeight;

    // 根: 中轴顶部 (不在 A/B 任一线上)
    positions[root.id] = Offset(0, yOf(0));
    columns[root.id] = 0;
    depths[root.id] = 0;
    spine.add(root.id);

    final leftHead = _childOn(root, 'left');
    final rightHead = _childOn(root, 'right');

    var leftNext = 1;
    var rightNext = 1;
    if (leftHead != null) {
      leftNext = _layoutChain(
        leftHead,
        side: 'left',
        sign: -1,
        startDepth: 1,
        column: 0,
        nextFree: 1,
        maxDepth: maxDepth,
        positions: positions,
        columns: columns,
        depths: depths,
        spine: spine,
        legIds: aLine,
      );
    }
    if (rightHead != null) {
      rightNext = _layoutChain(
        rightHead,
        side: 'right',
        sign: 1,
        startDepth: 1,
        column: 0,
        nextFree: 1,
        maxDepth: maxDepth,
        positions: positions,
        columns: columns,
        depths: depths,
        spine: spine,
        legIds: bLine,
      );
    }

    final leftColumns = leftNext - 1;
    final rightColumns = rightNext - 1;
    final maxColumn = math.max(leftColumns, rightColumns);
    final maxDepthSeen = depths.values.fold<int>(0, math.max);

    final halfWidth = spineOffset + maxColumn * columnWidth + nodeRadius + padding;
    final canvasSize = Size(
      math.max(400, halfWidth * 2),
      padding * 2 + (maxDepthSeen + 1) * levelHeight + nodeSize,
    );

    // 坐标从「中轴 = 0」平移到画布坐标系 [0, width]
    // (左腿 x 是负数, 不平移会被画到 SizedBox 外面 → 点击/命中失效)
    final canvasPositions = <String, Offset>{
      for (final e in positions.entries)
        e.key: Offset(e.value.dx + halfWidth, e.value.dy),
    };

    return TreeLayoutResult(
      positions: canvasPositions,
      columns: columns,
      depths: depths,
      spineIds: spine,
      aLineIds: aLine,
      bLineIds: bLine,
      leftColumns: leftColumns,
      rightColumns: rightColumns,
      // 内容高度: 根圆顶 → 最下层「A线/B线」标签底 (含名字 16pt + 标签 11pt)
      contentHeight: maxDepthSeen * levelHeight + nodeSize + 56,
      canvasSize: canvasSize,
    );
  }

  /// 沿主线链铺开一层层节点, 返回下一条可用的外侧列号
  ///
  /// 规则:
  ///   - 节点放 [column] 列 (主线列 = 0)
  ///   - 同侧子节点续主线 (继续同一列)
  ///   - 另一侧子节点 = 侧枝, 放到 [nextFree] 列 (外侧), 内部递归 (侧枝自己的主线 + 再外侧)
  ///   - 同侧断了但有另一侧 → 另一侧接主线 (主线不断)
  static int _layoutChain(
    FranchiseeTreeNode start, {
    required String side,
    required double sign,
    required int startDepth,
    required int column,
    required int nextFree,
    required int maxDepth,
    required Map<String, Offset> positions,
    required Map<String, int> columns,
    required Map<String, int> depths,
    required Set<String> spine,
    required Set<String> legIds,
  }) {
    final otherSide = side == 'left' ? 'right' : 'left';
    final x = sign * (spineOffset + column * columnWidth);

    var node = start;
    var depth = startDepth;
    var next = nextFree;

    while (depth <= maxDepth) {
      positions[node.id] = Offset(
        x,
        padding + nodeRadius + depth * levelHeight,
      );
      columns[node.id] = column;
      depths[node.id] = depth;
      spine.add(node.id);
      legIds.add(node.id);

      final same = _childOn(node, side);
      final other = _childOn(node, otherSide);

      if (same != null) {
        if (other != null) {
          // 另一侧 = 侧枝 → 外侧一列, 它的子树再往更外侧
          next = _layoutChain(
            other,
            side: side,
            sign: sign,
            startDepth: depth + 1,
            column: next,
            nextFree: next + 1,
            maxDepth: maxDepth,
            positions: positions,
            columns: columns,
            depths: depths,
            spine: spine,
            legIds: legIds,
          );
        }
        node = same;
      } else if (other != null) {
        // 同侧没有 → 另一侧接主线 (保持一条直线往下)
        node = other;
      } else {
        break; // 叶子, 主线到此结束
      }
      depth += 1;
    }

    return next;
  }

  /// 取某侧的子节点
  ///
  /// placementSide 缺失时兜底: 第 1 个孩子 = left, 第 2 个 = right
  static FranchiseeTreeNode? _childOn(FranchiseeTreeNode node, String side) {
    for (final c in node.children) {
      if (c.placementSide == side) return c;
    }
    final noSide = node.children.where((c) => c.placementSide == null).toList();
    if (noSide.isEmpty) return null;
    if (side == 'left') return noSide.first;
    return noSide.length >= 2 ? noSide[1] : null;
  }
}

// ============================================
// Painter
// ============================================

class FranchiseTreePainter extends CustomPainter {
  final FranchiseeTreeNode root;
  final Map<String, Offset> positions;

  /// 搜索匹配节点 id 集合 (来自页面顶部搜索框).
  /// - null / 空 = 无搜索
  /// - 非空 = 这些 id 高亮, 其余淡化
  final Set<String>? searchMatchedIds;

  /// 根节点标识 (绿色「我」)
  final String? currentUserId;

  /// 单击选中的节点 id (突显, 不在 = 无选中)
  final String? selectedNodeId;

  /// 选中节点 → 根 的整条路径 id (含两端); 这条线上的节点/连线高亮
  final Set<String> pathIds;

  /// 两条主线上的节点 id (主线连线加粗)
  final Set<String> spineIds;

  /// A线 / B线 节点 id (节点填充色区分: A=深蓝, B=紫)
  final Set<String> aLineIds;
  final Set<String> bLineIds;

  /// 节点 id → 关系 (直推=实心 / 下级引荐=空心 / 上级引荐=空心+外环)
  final Map<String, FranchiseeRelation> relations;

  /// 筛选命中节点 id (null = 无筛选; 非空 = 只亮这些, 其余淡化)
  final Set<String>? filterIds;

  FranchiseTreePainter({
    required this.root,
    required this.positions,
    this.searchMatchedIds,
    this.currentUserId,
    this.selectedNodeId,
    this.pathIds = const {},
    this.spineIds = const {},
    this.aLineIds = const {},
    this.bLineIds = const {},
    this.relations = const {},
    this.filterIds,
  });

  bool get _searchActive =>
      searchMatchedIds != null && searchMatchedIds!.isNotEmpty;

  bool _isSearchHit(String id) => searchMatchedIds?.contains(id) ?? false;

  bool get _filterActive => filterIds != null;

  bool _isFilterHit(String id) => filterIds?.contains(id) ?? false;

  /// 是否有任意高亮源 (选中 / 搜索 / 筛选) → 决定其余节点是否淡化
  bool get _anyHighlight =>
      selectedNodeId != null || _searchActive || _filterActive;

  bool _isNodeHighlighted(String id) =>
      id == selectedNodeId ||
      pathIds.contains(id) ||
      _isSearchHit(id) ||
      _isFilterHit(id);

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

      // 选中路径: 两端都在路径上 = 这条边属于「我 → 选中节点」的线
      final onPath = pathIds.contains(node.id) && pathIds.contains(child.id);
      // 搜索: 任一端命中即高亮
      final searchHit = _isSearchHit(node.id) || _isSearchHit(child.id);
      // 筛选: 任一端命中即保持可见
      final filterHit = _isFilterHit(node.id) || _isFilterHit(child.id);
      // 双主线: 两端都是主线节点 = 主线连线 (平时也加粗, 强调两条主线)
      final onSpine = spineIds.contains(node.id) && spineIds.contains(child.id);

      final Color color;
      final double stroke;
      if (onPath) {
        color = AppTheme.accent;
        stroke = 4.5;
      } else if (searchHit) {
        color = AppTheme.accent.withOpacity(0.9);
        stroke = 3.5;
      } else if (filterHit && _filterActive) {
        color = AppTheme.primaryDark.withOpacity(0.55);
        stroke = 2.5;
      } else if (_anyHighlight) {
        color = AppTheme.primaryDark.withOpacity(0.12);
        stroke = 1.5;
      } else if (onSpine) {
        color = AppTheme.primaryDark.withOpacity(0.7);
        stroke = 3.0;
      } else {
        color = AppTheme.primaryDark.withOpacity(0.35);
        stroke = 2.0;
      }

      final paint = Paint()
        ..color = color
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke;

      // 父→子连线 (柔和曲线; 侧枝是斜线, 控制点仍取父节点 x)
      final path = Path();
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
    final isSelected = selectedNodeId != null && node.id == selectedNodeId;
    final isOnPath = pathIds.contains(node.id);
    final isHit = _isSearchHit(node.id);
    final highlighted = _isNodeHighlighted(node.id);
    final isFaded = _anyHighlight && !highlighted;
    final relation = relations[node.id] ?? FranchiseeRelation.downline;

    _drawNodeCircle(
      canvas,
      pos,
      node,
      isCurrentUser: isCurrentUser,
      isSelected: isSelected,
      isOnPath: isOnPath || isHit,
      isFaded: isFaded,
      relation: relation,
      lineColor: _lineColorOf(node.id, isCurrentUser),
    );
    _drawNodeLabel(canvas, pos, node, isCurrentUser, isFaded);

    for (final child in node.children) {
      _drawNodes(canvas, child);
    }
  }

  /// 节点颜色: 我=绿, A线=深蓝, B线=紫
  Color _lineColorOf(String id, bool isCurrentUser) {
    if (isCurrentUser) return AppTheme.primary;
    if (aLineIds.contains(id)) return AppTheme.franchiseeA;
    return AppTheme.franchiseeB;
  }

  void _drawNodeCircle(
    Canvas canvas,
    Offset center,
    FranchiseeTreeNode node, {
    required bool isCurrentUser,
    required bool isSelected,
    required bool isOnPath,
    required bool isFaded,
    required FranchiseeRelation relation,
    required Color lineColor,
  }) {
    // 直推 = 实心; 非直推 = 空心 (浅底 + 描边). 我 = 实心
    final isDirect = isCurrentUser || relation == FranchiseeRelation.direct;
    final isUpline = relation == FranchiseeRelation.upline;

    // 1. 光晕 (选中最亮, 路径/搜索次之)
    if (isSelected) {
      canvas.drawCircle(
        center,
        TreeLayout.nodeRadius + 10,
        Paint()
          ..color = AppTheme.accent.withOpacity(0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    } else if (isOnPath) {
      canvas.drawCircle(
        center,
        TreeLayout.nodeRadius + 6,
        Paint()
          ..color = AppTheme.accent.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // 2. 主圆
    final Color fillColor;
    if (isFaded) {
      fillColor = lineColor.withOpacity(isDirect ? 0.35 : 0.12);
    } else {
      fillColor = isDirect ? lineColor : lineColor.withOpacity(0.16);
    }
    canvas.drawCircle(center, TreeLayout.nodeRadius, Paint()..color = fillColor);

    // 2.1 空心描边 (非直推)
    if (!isDirect) {
      canvas.drawCircle(
        center,
        TreeLayout.nodeRadius - 1.75,
        Paint()
          ..color = isFaded ? lineColor.withOpacity(0.3) : lineColor.withOpacity(0.9)
          ..strokeWidth = 3.5
          ..style = PaintingStyle.stroke,
      );
    }

    // 2.2 上级引荐: 额外细外环 (远看/全景也能区分)
    if (isUpline) {
      canvas.drawCircle(
        center,
        TreeLayout.nodeRadius + 6,
        Paint()
          ..color = isFaded ? lineColor.withOpacity(0.2) : lineColor.withOpacity(0.55)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }

    // 3. 内圆 (只有实心节点画装饰内圆)
    if (isDirect) {
      canvas.drawCircle(
        center,
        TreeLayout.nodeRadius - 4,
        Paint()..color = Colors.white.withOpacity(isFaded ? 0.1 : 0.2),
      );
    }

    // 4. 选中/路径环 (让「我 → 选中节点」这条线一眼看清)
    if (isSelected) {
      canvas.drawCircle(
        center,
        TreeLayout.nodeRadius + 5,
        Paint()
          ..color = AppTheme.accent
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke,
      );
    } else if (isOnPath && !isFaded) {
      canvas.drawCircle(
        center,
        TreeLayout.nodeRadius + 4,
        Paint()
          ..color = AppTheme.accent.withOpacity(0.85)
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
    }

    // 5. 首字母 (大字; 空心节点用线色, 实心节点用白字)
    final initial = node.name.isNotEmpty ? node.name[0] : '?';
    final tp = TextPainter(
      text: TextSpan(
        text: initial,
        style: TextStyle(
          fontSize: 32,
          color: isFaded
              ? lineColor.withOpacity(0.5)
              : (isDirect ? Colors.white : lineColor),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

    // 6. 角标: 直推「直」(橙) / 上级引荐「上」(灰); 下级引荐 (多数) 不加角标
    if (!isFaded && !isCurrentUser) {
      if (relation == FranchiseeRelation.direct) {
        _drawBadge(canvas, center, '直', AppTheme.accent);
      } else if (isUpline) {
        _drawBadge(canvas, center, '上', AppTheme.badgeNeutral);
      }
    }
  }

  /// 节点右上角小角标 (圆形 + 1 字)
  void _drawBadge(Canvas canvas, Offset center, String text, Color color) {
    final badgeCenter = Offset(
      center.dx + TreeLayout.nodeRadius * 0.74,
      center.dy - TreeLayout.nodeRadius * 0.74,
    );
    const double badgeRadius = 13;
    canvas.drawCircle(
      badgeCenter,
      badgeRadius,
      Paint()..color = Colors.white.withOpacity(0.95),
    );
    canvas.drawCircle(badgeCenter, badgeRadius, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 14,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(badgeCenter.dx - tp.width / 2, badgeCenter.dy - tp.height / 2),
    );
  }

  void _drawNodeLabel(
    Canvas canvas,
    Offset center,
    FranchiseeTreeNode node,
    bool isCurrentUser,
    bool isFaded,
  ) {
    // 姓名 (圆下方)
    // maxWidth = labelMaxWidth (列距 180 - 20): 相邻列名字不串行, 长名截断
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
    )..layout(maxWidth: TreeLayout.labelMaxWidth);
    final nameTop = center.dy + TreeLayout.nodeRadius + 8;
    // 名字底色 — 父→子连线从圆底中心向下画, 用画布同色块垫在文字下面 (连线从背后过)
    _drawLabelBackground(
      canvas,
      Rect.fromLTWH(
        center.dx - tpName.width / 2 - 5,
        nameTop - 2,
        tpName.width + 10,
        tpName.height + 4,
      ),
      isFaded,
    );
    tpName.paint(canvas, Offset(center.dx - tpName.width / 2, nameTop));

    // "我" 标记 (根节点) — 根节点名字下方
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
      final meTop = center.dy + TreeLayout.nodeRadius + 30;
      _drawLabelBackground(
        canvas,
        Rect.fromLTWH(
          center.dx - tpMe.width / 2 - 5,
          meTop - 2,
          tpMe.width + 10,
          tpMe.height + 4,
        ),
        isFaded,
      );
      tpMe.paint(canvas, Offset(center.dx - tpMe.width / 2, meTop));
    }

    // 位置标签 (左/右) — 子节点名字下方
    if (node.placementSide != null) {
      final tpSide = TextPainter(
        text: TextSpan(
          text: node.placementSide == 'left' ? '← A线' : 'B线 →',
          style: TextStyle(
            fontSize: 11,
            color: node.placementSide == 'left'
                ? (isFaded
                    ? AppTheme.franchiseeA.withOpacity(0.4)
                    : AppTheme.franchiseeA)
                : (isFaded
                    ? AppTheme.franchiseeB.withOpacity(0.4)
                    : AppTheme.franchiseeB),
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final sideTop = center.dy + TreeLayout.nodeRadius + 48;
      _drawLabelBackground(
        canvas,
        Rect.fromLTWH(
          center.dx - tpSide.width / 2 - 5,
          sideTop - 2,
          tpSide.width + 10,
          tpSide.height + 4,
        ),
        isFaded,
      );
      tpSide.paint(canvas, Offset(center.dx - tpSide.width / 2, sideTop));
    }
  }

  /// 标签底色 (盖住从圆底穿过的父子连线; 跟画布同色)
  void _drawLabelBackground(Canvas canvas, Rect rect, bool isFaded) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = AppTheme.bgWarm.withOpacity(isFaded ? 0.6 : 0.9),
    );
  }

  bool _mapChanged(
    Map<String, FranchiseeRelation> a,
    Map<String, FranchiseeRelation> b,
  ) {
    if (identical(a, b)) return false;
    if (a.length != b.length) return true;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return true;
    }
    return false;
  }

  bool _setChanged(Set<String>? a, Set<String>? b) {
    if (identical(a, b)) return false;
    if (a == null || b == null) return a != b;
    if (a.length != b.length) return true;
    for (final e in a) {
      if (!b.contains(e)) return true;
    }
    return false;
  }

  @override
  bool shouldRepaint(covariant FranchiseTreePainter old) {
    return old.root != root ||
        old.selectedNodeId != selectedNodeId ||
        old.currentUserId != currentUserId ||
        _setChanged(old.pathIds, pathIds) ||
        _setChanged(old.spineIds, spineIds) ||
        _setChanged(old.aLineIds, aLineIds) ||
        _setChanged(old.bLineIds, bLineIds) ||
        _mapChanged(old.relations, relations) ||
        _setChanged(old.filterIds, filterIds) ||
        _setChanged(old.searchMatchedIds, searchMatchedIds);
  }
}
