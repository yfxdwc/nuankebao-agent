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
import '../../../../core/widgets/member_avatar.dart';

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

  /// 实际列间距 (列多时会压缩 < columnWidth, 允许相邻节点一定重叠)
  final double columnPitch;

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
    required this.columnPitch,
    required this.canvasSize,
  });
}

// ============================================
// 布局算法 (双主线 + 外侧展开)
// ============================================

class TreeLayout {
  static const double nodeRadius = 44;       // 主线节点半径 (88pt 直径)
  static const double nodeSize = 88;         // 主线节点直径
  // fix-graph-compact (2026-09-17 主人拍): 节点上百也能看 — 外侧压紧 + 允许重叠 + 虚化
  static const double levelHeight = 122;     // 层间距 (140 → 122, 上下压紧)
  static const double columnWidth = 104;     // 列间距 (180 → 104, 外侧压紧, 允许相邻轻微重叠)
  static const double spineOffset = 84;      // 中轴 → 主线列距离
  static const double padding = 28;          // 画布边距
  static const double labelMaxWidth = 150;   // 主线名字最大宽

  /// 外侧第 [col] 列节点半径 (越外侧越小 → 前后立体)
  static double radiusForColumn(int col) {
    if (col <= 0) return nodeRadius;
    if (col == 1) return 33;
    if (col == 2) return 27;
    return 23;
  }

  /// 外侧第 [col] 列名字最大宽 (允许相邻轻微重叠)
  static double labelMaxWidthForColumn(int col) =>
      col <= 0 ? labelMaxWidth : columnWidth - 6;

  /// 外侧第 [col] 列整体透明度 (主线 1.0 → 越外侧越虚化)
  static double alphaForColumn(int col) {
    if (col <= 0) return 1.0;
    if (col == 1) return 0.92;
    if (col == 2) return 0.78;
    return 0.64;
  }

  /// 外侧节点松弛 (主人: 可不对齐 + 一点斥力/弹簧)。主线严格不动。
  static const int _relaxIterations = 32;

  /// 列很多时的目标半宽 (超过就把列距压缩, 允许相邻节点一定比例重叠)
  static const double targetHalfWidth = 760;
  /// 最小压缩比 (0.42 → 相邻列最多压到 44px, 允许 50%+ 重叠)
  static const double minPitchRatio = 0.42;

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
    final parents = <String, String>{};

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
        parentId: root.id,
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
        parents: parents,
      );
    }
    if (rightHead != null) {
      rightNext = _layoutChain(
        rightHead,
        parentId: root.id,
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
        parents: parents,
      );
    }

    final leftColumns = leftNext - 1;
    final rightColumns = rightNext - 1;
    final maxColumn = math.max(leftColumns, rightColumns);
    final maxDepthSeen = depths.values.fold<int>(0, math.max);

    // 列很多 → 压缩列距 (允许一定比例重叠): 主人 2026-09-17「上百节点也要能看」
    final neededHalfWidth = spineOffset + maxColumn * columnWidth + 80;
    final pitch = neededHalfWidth <= targetHalfWidth
        ? columnWidth
        : math.max(
            columnWidth * minPitchRatio,
            columnWidth * targetHalfWidth / neededHalfWidth,
          );

    // 用最终 pitch 重排 x (根恒在中轴 0)
    for (final id in positions.keys.toList()) {
      final col = columns[id] ?? 0;
      final sign = aLine.contains(id)
          ? -1.0
          : (bLine.contains(id) ? 1.0 : 0.0);
      positions[id] = Offset(sign * (spineOffset + col * pitch), positions[id]!.dy);
    }

    final halfWidth = spineOffset + maxColumn * pitch + nodeRadius + padding;
    final canvasWidth = math.max(400.0, halfWidth * 2);
    // 宽度兜底 (400) 生效时把内容居中, 别让根节点偏在左边
    final centerOffsetX = canvasWidth / 2 - halfWidth;
    final canvasSize = Size(
      canvasWidth,
      padding * 2 + (maxDepthSeen + 1) * levelHeight + nodeSize,
    );

    // 外侧节点松弛: 允许不对齐 + 轻微重叠 (主线严格竖直不动)
    _relax(
      positions: positions,
      columns: columns,
      depths: depths,
      parents: parents,
      pitch: pitch,
    );

    // 坐标从「中轴 = 0」平移到画布坐标系 [0, width]
    // (左腿 x 是负数, 不平移会被画到 SizedBox 外面 → 点击/命中失效)
    final canvasPositions = <String, Offset>{
      for (final e in positions.entries)
        e.key: Offset(e.value.dx + halfWidth + centerOffsetX, e.value.dy),
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
      columnPitch: pitch,
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
    required String parentId,
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
    required Map<String, String> parents,
  }) {
    final otherSide = side == 'left' ? 'right' : 'left';
    final x = sign * (spineOffset + column * columnWidth);

    var node = start;
    var depth = startDepth;
    var next = nextFree;
    var parentOfCurrent = parentId;

    while (depth <= maxDepth) {
      positions[node.id] = Offset(
        x,
        padding + nodeRadius + depth * levelHeight,
      );
      columns[node.id] = column;
      depths[node.id] = depth;
      spine.add(node.id);
      legIds.add(node.id);
      parents[node.id] = parentOfCurrent;

      final same = _childOn(node, side);
      final other = _childOn(node, otherSide);

      if (same != null) {
        if (other != null) {
          // 另一侧 = 侧枝 → 外侧一列, 它的子树再往更外侧
          next = _layoutChain(
            other,
            parentId: node.id,
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
            parents: parents,
          );
        }
        parentOfCurrent = node.id;
        node = same;
      } else if (other != null) {
        // 同侧没有 → 另一侧接主线 (保持一条直线往下)
        parentOfCurrent = node.id;
        node = other;
      } else {
        break; // 叶子, 主线到此结束
      }
      depth += 1;
    }

    return next;
  }

  /// 外侧节点松弛: 斥力 (防叠死, 允许轻微重叠) + 弹簧 (回父节点 / 回初始格位)
  /// 主线 (col == 0) 与根严格不动 → 两条主线始终竖直平行 + 同层成对
  static void _relax({
    required Map<String, Offset> positions,
    required Map<String, int> columns,
    required Map<String, int> depths,
    required Map<String, String> parents,
    required double pitch,
  }) {
    if (positions.length < 3) return;

    // 按层分桶: 只跟上下 2 层内的节点互斥 (省算力, 上百节点也快)
    final byDepth = <int, List<String>>{};
    for (final id in positions.keys) {
      byDepth.putIfAbsent(depths[id] ?? 0, () => []).add(id);
    }
    final anchors = Map<String, Offset>.from(positions);

    for (var iter = 0; iter < _relaxIterations; iter++) {
      final delta = <String, Offset>{};
      for (final entry in byDepth.entries) {
        final depth = entry.key;
        for (final id in entry.value) {
          final col = columns[id] ?? 0;
          if (col == 0) continue; // 主线不动
          final pa = positions[id]!;
          final ra = radiusForColumn(col);
          var d = Offset.zero;

          // 斥力: 只和 ±2 层内的邻居比
          for (var dd = depth - 2; dd <= depth + 2; dd++) {
            final list = byDepth[dd];
            if (list == null) continue;
            for (final other in list) {
              if (identical(other, id)) continue;
              final pb = positions[other]!;
              final rb = radiusForColumn(columns[other] ?? 0);
              // 允许轻微重叠: 只推开到 minGap (压缩后用更小的 gap, 别把列又撑开)
              final minGap = math.min(ra + rb + 4, pitch * 0.9);
              var diff = pa - pb;
              var dist = diff.distance;
              if (dist >= minGap) continue;
              if (dist < 0.01) {
                diff = const Offset(1, 0.5);
                dist = 1;
              }
              d += (diff / dist) * ((minGap - dist) * 0.32);
            }
          }

          // 弹簧: 回父节点 (保持树形)
          final parentId = parents[id];
          final parentPos = parentId == null ? null : positions[parentId];
          if (parentPos != null) {
            d += (parentPos - pa) * 0.02;
          }
          // 弹簧: 回初始格位 (保持整体扇形)
          d += (anchors[id]! - pa) * 0.07;

          if (d.distance > 5) d = d / d.distance * 5;
          delta[id] = d;
        }
      }

      for (final e in delta.entries) {
        final id = e.key;
        final anchor = anchors[id]!;
        final p = positions[id]! + e.value;
        // 夹紧: 不串列 (x ±0.38 列距), 不跳出本层 (y ±0.32 层高)
        positions[id] = Offset(
          p.dx.clamp(anchor.dx - pitch * 0.38, anchor.dx + pitch * 0.38),
          p.dy.clamp(anchor.dy - levelHeight * 0.32, anchor.dy + levelHeight * 0.32),
        );
      }
    }
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

/// 图谱最上方「上层点位」那一格 (主人 2026-09-21 拍)
///   - 有人: 画成正常节点 (关系标成「上」, 加外环) + 一条连到「我」的线
///   - 没人 (我是树根): 虚线虚位 + 「点此认领」→ 全 app 唯一能往上发展的入口
///   - 已发起认领: 虚线 + 「待她确认」
class UplineCap {
  /// 要画的节点 (虚位时用哨兵 id; 位置由页面塞进 positions)
  final FranchiseeTreeNode node;
  /// true = 虚线 (虚位待认领 / 待上级确认)
  final bool ghost;
  /// 虚线格圆下方的说明文字
  final String? hint;

  const UplineCap({required this.node, this.ghost = false, this.hint});
}

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

  /// 节点 id → 列号 (0=主线; 越外侧半径越小 / 越虚化 → 前后立体)
  final Map<String, int> columns;

  /// 当前视图缩放 (页面从 TransformationController 传):
  ///   缩小看全局时少画外侧名字/角标, 放大看细节时补上
  final double scale;

  /// 实际列间距 (列多时压缩): 外侧名字宽度跟着收, 允许相邻轻微重叠
  final double columnPitch;

  /// 子树内「待确认」的落位点位 (三方确认工作流; 画成虚线虚位)
  final List<PendingPlacement> pendingPlacements;

  /// 最上方「上层点位」那一格 (主人 2026-09-21 拍; null = 不画)
  final UplineCap? uplineCap;

  /// 上层格的中心 (画布坐标; 页面已把 tree 整体下移一层, 这一格在原来根的位置)
  final Offset? uplineCapCenter;

  FranchiseTreePainter({
    required this.root,
    required this.positions,
    this.columns = const {},
    this.scale = 1.0,
    this.columnPitch = TreeLayout.columnWidth,
    this.pendingPlacements = const [],
    this.uplineCap,
    this.uplineCapCenter,
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

  /// 选中节点的**一层**子节点 id (主人 2026-09-19 拍: 单击后一层也突出显示)
  /// 从树里实时算 → 懒加载展开出新节点时, 下一次 repaint 就自动纳入高亮
  late final Set<String> selectedChildIds = _computeSelectedChildren();

  Set<String> _computeSelectedChildren() {
    final sel = selectedNodeId;
    if (sel == null) return const <String>{};
    FranchiseeTreeNode? found;
    void walk(FranchiseeTreeNode n) {
      if (found != null) return;
      if (n.id == sel) {
        found = n;
        return;
      }
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(root);
    final node = found;
    if (node == null) return const <String>{};
    return node.children.map((c) => c.id).toSet();
  }

  bool _isNodeHighlighted(String id) =>
      id == selectedNodeId ||
      pathIds.contains(id) ||
      selectedChildIds.contains(id) ||
      _isSearchHit(id) ||
      _isFilterHit(id);

  int _columnOf(String id) => columns[id] ?? 0;

  /// 按列给颜色上透明度 (越外侧越虚化)
  Color _tint(Color c, int col, [double extra = 1.0]) =>
      c.withOpacity((TreeLayout.alphaForColumn(col) * extra).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    _drawEdges(canvas, root);

    // 前后立体: 外侧列先画 (在底层), 主线最后画 (在最上层)
    final nodes = <FranchiseeTreeNode>[];
    void collect(FranchiseeTreeNode n) {
      nodes.add(n);
      for (final c in n.children) {
        collect(c);
      }
    }

    collect(root);
    nodes.sort((a, b) => _columnOf(b.id).compareTo(_columnOf(a.id)));
    for (final n in nodes) {
      _drawNode(canvas, n);
    }

    // 待确认虚位 (主人 2026-09-18 拍): 虚线圆 + 「待确认」, 在最上层
    _drawPendingGhosts(canvas, size);

    // 上层点位 (主人 2026-09-21 拍): 最上面那一格 + 连到「我」的线
    _drawUplineCap(canvas);
  }

  /// 上层点位那一格
  void _drawUplineCap(Canvas canvas) {
    final cap = uplineCap;
    final center = uplineCapCenter;
    if (cap == null || center == null) return;
    final myRoot = positions[root.id];

    final boost = (1.0 / scale).clamp(1.0, 4.0);
    final capColor = AppTheme.primary;

    // 1. 连线 (上层 → 我): 有人 = 实线; 虚位 = 虚线 (还没接上)
    if (myRoot != null) {
      final from = Offset(center.dx, center.dy + TreeLayout.nodeRadius);
      final to = Offset(myRoot.dx, myRoot.dy - TreeLayout.nodeRadius);
      final paint = Paint()
        ..color = cap.ghost
            ? AppTheme.accent.withOpacity(0.75)
            : capColor.withOpacity(0.75)
        ..strokeWidth = (cap.ghost ? 2.2 : 3.0) * boost
        ..style = PaintingStyle.stroke;
      if (cap.ghost) {
        _drawDashedLine(
          canvas,
          from,
          to,
          paint,
          dash: 7 * boost,
          gap: 5 * boost,
        );
      } else {
        canvas.drawLine(from, to, paint);
      }
    }

    if (!cap.ghost) {
      // 有上层: 跟别的节点同一套画法 (含会员金环/角标)
      _drawNode(canvas, cap.node);
      return;
    }

    // 虚位 / 待确认: 浅底 + 虚线圆 + 圆内提示 + 圆下说明
    canvas.drawCircle(
      center,
      TreeLayout.nodeRadius,
      Paint()..color = AppTheme.accent.withOpacity(0.10),
    );
    _drawDashedCircle(
      canvas,
      center,
      TreeLayout.nodeRadius,
      Paint()
        ..color = AppTheme.accent.withOpacity(0.85)
        ..strokeWidth = 2.4 * boost
        ..style = PaintingStyle.stroke,
      dash: 7 * boost,
      gap: 5 * boost,
    );
    final inside = TextPainter(
      text: TextSpan(
        text: '＋',
        style: TextStyle(
          fontSize: 34 * boost,
          color: AppTheme.accent.withOpacity(0.9),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    inside.paint(
      canvas,
      Offset(center.dx - inside.width / 2, center.dy - inside.height / 2),
    );

    final label = cap.node.name;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 12 * boost,
          color: AppTheme.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      maxLines: 2,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: TreeLayout.labelMaxWidth + 40);
    // 名字放**圆上方** (圆下面 78px 就是「我」那个节点, 放下面会和它压在一起)
    final labelTop = center.dy - TreeLayout.nodeRadius - tp.height - 4;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          center.dx - tp.width / 2 - 5,
          labelTop - 2,
          tp.width + 10,
          tp.height + 4,
        ),
        const Radius.circular(6),
      ),
      Paint()..color = AppTheme.bgWarm.withOpacity(0.92),
    );
    tp.paint(canvas, Offset(center.dx - tp.width / 2, labelTop));

    final hint = cap.hint;
    if (hint != null && hint.isNotEmpty) {
      final tpHint = TextPainter(
        text: TextSpan(
          text: hint,
          style: TextStyle(
            fontSize: 11 * boost,
            color: AppTheme.textSecondary,
          ),
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: TreeLayout.labelMaxWidth + 40);
      // 提示放圆下方 (那一行离「我」还有 12px 余量)
      tpHint.paint(
        canvas,
        Offset(
          center.dx - tpHint.width / 2,
          center.dy + TreeLayout.nodeRadius + 4,
        ),
      );
    }
  }

  /// 画虚线 (跟 _drawDashedCircle 同一套 PathMetrics 切段)
  void _drawDashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    double dash = 7,
    double gap = 5,
  }) {
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final next = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, next), paint);
        d = next + gap;
      }
    }
  }

  /// 待确认虚位中心点 (与点击区共用同一份公式 —— 主人 2026-09-19: 虚位可点)
  static Offset pendingGhostCenter({
    required Offset parentPos,
    required bool parentIsA,
    required bool parentIsB,
    required int parentCol,
    required double columnPitch,
    required String targetSide,
  }) {
    final sign = parentIsA ? -1.0 : (parentIsB ? 1.0 : -1.0);
    final continuing = parentIsA ? 'left' : 'right';
    final sameSide = targetSide == continuing;
    final x = sameSide ? parentPos.dx : parentPos.dx + sign * columnPitch;
    return Offset(x, parentPos.dy + TreeLayout.levelHeight);
  }

  /// 待确认虚位: 父节点正下方 (同侧续线) 或外侧一列 (异侧) 画虚线圆
  void _drawPendingGhosts(Canvas canvas, Size size) {
    if (pendingPlacements.isEmpty) return;
    for (final p in pendingPlacements) {
      final parentPos = positions[p.targetParentFid];
      if (parentPos == null) continue;
      final isA = aLineIds.contains(p.targetParentFid);
      final isB = bLineIds.contains(p.targetParentFid);
      final parentCol = columns[p.targetParentFid] ?? 0;
      final center = pendingGhostCenter(
        parentPos: parentPos,
        parentIsA: isA,
        parentIsB: isB,
        parentCol: parentCol,
        columnPitch: columnPitch,
        targetSide: p.targetSide,
      );
      // 该腿的「续线侧」: A线 = left / B线 = right; 同侧 → 正下方同列, 异侧 → 外侧一列
      final continuing = isA ? 'left' : 'right';
      final radius =
          TreeLayout.radiusForColumn(p.targetSide == continuing ? parentCol : parentCol + 1);
      final ghostColor = AppTheme.accent.withOpacity(0.85);
      // 全景缩小视图里虚位也要看得见 → 线宽/字号/虚线间隔按 1/scale 补偿 (上限 4x)
      final boost = (1.0 / scale).clamp(1.0, 4.0);

      // 浅底 + 虚线边
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = AppTheme.accent.withOpacity(0.10),
      );
      _drawDashedCircle(
        canvas,
        center,
        radius,
        Paint()
          ..color = ghostColor
          ..strokeWidth = 2.4 * boost
          ..style = PaintingStyle.stroke,
        dash: 7 * boost,
        gap: 5 * boost,
      );

      // 「待确认」+ 名字 (小字, 圆下方)
      final tp = TextPainter(
        text: TextSpan(
          text: '⏳ ${p.label}',
          style: TextStyle(
            fontSize: 12 * boost,
            color: ghostColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: columnPitch + 40);
      final labelTop = center.dy + radius + 4;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            center.dx - tp.width / 2 - 5,
            labelTop - 2,
            tp.width + 10,
            tp.height + 4,
          ),
          const Radius.circular(6),
        ),
        Paint()..color = AppTheme.bgWarm.withOpacity(0.92),
      );
      tp.paint(canvas, Offset(center.dx - tp.width / 2, labelTop));
    }
  }

  /// 画虚线圆 (用 PathMetrics 切段)
  void _drawDashedCircle(
    Canvas canvas,
    Offset center,
    double radius,
    Paint paint, {
    double dash = 7,
    double gap = 5,
  }) {
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final next = math.min(d + dash, metric.length);
        canvas.drawPath(metric.extractPath(d, next), paint);
        d = next + gap;
      }
    }
  }

  void _drawEdges(Canvas canvas, FranchiseeTreeNode node) {
    final nodePos = positions[node.id];
    if (nodePos == null) return;

    for (final child in node.children) {
      final childPos = positions[child.id];
      if (childPos == null) continue;

      // 选中路径: 两端都在路径上 = 这条边属于「我 → 选中节点」的线
      final onPath = pathIds.contains(node.id) && pathIds.contains(child.id);
      // 选中节点 → 它的一层子节点 (主人 2026-09-19: 一层也突出; 比路径线略细)
      final childOfSelected = selectedNodeId != null &&
          node.id == selectedNodeId &&
          selectedChildIds.contains(child.id);
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
      } else if (childOfSelected) {
        color = AppTheme.accent;
        stroke = 3.5;
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

  void _drawNode(Canvas canvas, FranchiseeTreeNode node) {
    final pos = positions[node.id];
    if (pos == null) return;

    final isCurrentUser = currentUserId != null && node.id == currentUserId;
    final isSelected = selectedNodeId != null && node.id == selectedNodeId;
    final isOnPath =
        pathIds.contains(node.id) || selectedChildIds.contains(node.id);
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
  }

  /// 节点颜色: 我=绿, A线=深蓝, B线=紫, 上层格=绿
  Color _lineColorOf(String id, bool isCurrentUser) {
    if (isCurrentUser) return AppTheme.primary;
    if (uplineCap?.node.id == id) return AppTheme.primary;
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
    final col = _columnOf(node.id);
    final radius = TreeLayout.radiusForColumn(col);
    // 直推 = 实心; 非直推 = 空心 (浅底 + 描边). 我 = 实心
    final isDirect = isCurrentUser || relation == FranchiseeRelation.direct;
    final isUpline = relation == FranchiseeRelation.upline;
    final fillAlpha = isFaded ? 0.35 : 1.0;
    final ringAlpha = isFaded ? 0.3 : 1.0;

    // 1. 光晕 (选中最亮, 路径/搜索次之)
    if (isSelected) {
      canvas.drawCircle(
        center,
        radius + 10,
        Paint()
          ..color = AppTheme.accent.withOpacity(0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    } else if (isOnPath) {
      canvas.drawCircle(
        center,
        radius + 6,
        Paint()
          ..color = AppTheme.accent.withOpacity(0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // 2. 主圆 (越外侧越虚化: _tint 已按列乘透明度)
    final fillColor = isDirect
        ? _tint(lineColor, col, fillAlpha)
        : _tint(lineColor, col, 0.16 * fillAlpha);
    canvas.drawCircle(center, radius, Paint()..color = fillColor);

    // 2.1 空心描边 (非直推)
    if (!isDirect) {
      canvas.drawCircle(
        center,
        radius - 1.6,
        Paint()
          ..color = _tint(lineColor, col, 0.9 * ringAlpha)
          ..strokeWidth = math.max(2.0, radius * 0.09)
          ..style = PaintingStyle.stroke,
      );
    }

    // 2.2 上级引荐: 额外细外环
    if (isUpline) {
      canvas.drawCircle(
        center,
        radius + 5,
        Paint()
          ..color = _tint(lineColor, col, 0.55 * ringAlpha)
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke,
      );
    }

    // 3. 内圆 (只有实心节点画装饰内圆)
    if (isDirect) {
      canvas.drawCircle(
        center,
        radius - 4,
        Paint()..color = Colors.white.withOpacity(isFaded ? 0.1 : 0.2),
      );
    }

    // 4. 选中/路径环 (让「我 → 选中节点」这条线一眼看清)
    if (isSelected) {
      canvas.drawCircle(
        center,
        radius + 5,
        Paint()
          ..color = AppTheme.accent
          ..strokeWidth = 5
          ..style = PaintingStyle.stroke,
      );
    } else if (isOnPath && !isFaded) {
      canvas.drawCircle(
        center,
        radius + 4,
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
          fontSize: math.max(12, radius * 0.72),
          color: isFaded
              ? _tint(lineColor, col, 0.5)
              : (isDirect ? Colors.white : _tint(lineColor, col)),
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));

    // 6. 角标: 直推「直」(橙) / 上级引荐「上」(灰); 缩小看全局时不画 (减噪)
    if (!isFaded && !isCurrentUser && scale >= 0.5) {
      if (relation == FranchiseeRelation.direct) {
        _drawBadge(canvas, center, '直', AppTheme.accent, radius);
      } else if (isUpline) {
        _drawBadge(canvas, center, '上', AppTheme.badgeNeutral, radius);
      }
    }

    // 7. 会员标识 (主人 2026-09-21 拍): 金色外环 + 👑
    //   环在**所有**缩放下都画 (细环不占地方, 缩小看全局也要能一眼扫出会员);
    //   👑 只在 scale >= 0.5 画 (跟关系角标同一减噪口径)。
    //   位置: 金环在圆外 (radius + 8), 👑 在**右下角** —— 右上角被「直/上」占了,
    //   错开一角两个信息都看得见 (与列表行「👑 右上 / 类型 右下」是同一套避让原则)。
    if (node.member && !isFaded) {
      canvas.drawCircle(
        center,
        radius + 8,
        Paint()
          ..color = kMemberGold
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke,
      );
      if (scale >= 0.5) {
        _drawMemberCrown(canvas, center, radius);
      }
    }
  }

  /// 👑 会员角标 (右下角; 与客户类型/关系角标错位)
  void _drawMemberCrown(Canvas canvas, Offset center, double nodeRadius) {
    final badgeCenter = Offset(
      center.dx + nodeRadius * 0.74,
      center.dy + nodeRadius * 0.74,
    );
    final badgeRadius = math.max(9.0, nodeRadius * 0.32);
    canvas.drawCircle(
      badgeCenter,
      badgeRadius,
      Paint()..color = Colors.white.withOpacity(0.95),
    );
    canvas.drawCircle(badgeCenter, badgeRadius, Paint()..color = kMemberGold);
    final tp = TextPainter(
      text: TextSpan(
        text: '👑',
        style: TextStyle(fontSize: math.max(10, badgeRadius * 1.25), height: 1.0),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(badgeCenter.dx - tp.width / 2, badgeCenter.dy - tp.height / 2),
    );
  }

  /// 节点右上角小角标 (圆形 + 1 字)
  void _drawBadge(
    Canvas canvas,
    Offset center,
    String text,
    Color color,
    double nodeRadius,
  ) {
    final badgeCenter = Offset(
      center.dx + nodeRadius * 0.76,
      center.dy - nodeRadius * 0.76,
    );
    final badgeRadius = math.max(8.0, nodeRadius * 0.32);
    canvas.drawCircle(
      badgeCenter,
      badgeRadius,
      Paint()..color = Colors.white.withOpacity(0.95),
    );
    canvas.drawCircle(badgeCenter, badgeRadius, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: math.max(9, badgeRadius * 1.05),
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
    final col = _columnOf(node.id);
    final radius = TreeLayout.radiusForColumn(col);

    // 缩小看全局时: 外侧名字先省掉 (减噪); 主线/选中/搜索命中始终画
    final isSelected = selectedNodeId != null && node.id == selectedNodeId;
    final alwaysShow =
        col == 0 || isSelected || pathIds.contains(node.id) || _isSearchHit(node.id);
    if (!alwaysShow) {
      final minScale = col == 1 ? 0.34 : 0.58;
      if (scale < minScale) return;
    }

    // 姓名 (圆下方): 字号/宽度随列缩小, 允许相邻轻微重叠
    final fontSize = math.max(
      11.0,
      16.0 * (radius / TreeLayout.nodeRadius).clamp(0.7, 1.0),
    );
    final name = node.name;
    final tpName = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          fontSize: fontSize,
          color: isFaded
              ? AppTheme.textPrimary.withOpacity(0.35)
              : _tint(AppTheme.textPrimary, col),
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: TextAlign.center,
      maxLines: 1,
      ellipsis: '…',
      textDirection: TextDirection.ltr,
    )..layout(
        maxWidth: math.max(
          44.0,
          math.min(
            TreeLayout.labelMaxWidthForColumn(col),
            col == 0 ? TreeLayout.labelMaxWidth : columnPitch - 4,
          ),
        ),
      );
    final nameTop = center.dy + radius + 6;
    // 名字底色 — 父→子连线从圆底中心向下画, 用画布同色块垫在文字下面 (连线从背后过)
    _drawLabelBackground(
      canvas,
      Rect.fromLTWH(
        center.dx - tpName.width / 2 - 4,
        nameTop - 2,
        tpName.width + 8,
        tpName.height + 4,
      ),
      isFaded,
      col,
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
      final meTop = center.dy + radius + 28;
      _drawLabelBackground(
        canvas,
        Rect.fromLTWH(
          center.dx - tpMe.width / 2 - 4,
          meTop - 2,
          tpMe.width + 8,
          tpMe.height + 4,
        ),
        isFaded,
        col,
      );
      tpMe.paint(canvas, Offset(center.dx - tpMe.width / 2, meTop));
    }

    // 位置标签 (A线/B线) — 只在主线列画 (外侧节点太小, 画了更乱)
    if (node.placementSide != null && col == 0) {
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
      final sideTop = center.dy + radius + 44;
      _drawLabelBackground(
        canvas,
        Rect.fromLTWH(
          center.dx - tpSide.width / 2 - 4,
          sideTop - 2,
          tpSide.width + 8,
          tpSide.height + 4,
        ),
        isFaded,
        col,
      );
      tpSide.paint(canvas, Offset(center.dx - tpSide.width / 2, sideTop));
    }
  }

  /// 标签底色 (盖住从圆底穿过的父子连线; 跟画布同色)
  void _drawLabelBackground(
    Canvas canvas,
    Rect rect,
    bool isFaded,
    int col,
  ) {
    final a = (isFaded ? 0.6 : 0.9) * (col == 0 ? 1.0 : 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..color = AppTheme.bgWarm.withOpacity(a),
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

  bool _samePending(List<PendingPlacement> other) {
    for (var i = 0; i < other.length; i++) {
      if (other[i].requestId != pendingPlacements[i].requestId ||
          other[i].targetParentFid != pendingPlacements[i].targetParentFid ||
          other[i].targetSide != pendingPlacements[i].targetSide) {
        return false;
      }
    }
    return true;
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
        old.uplineCap != uplineCap ||
        old.uplineCapCenter != uplineCapCenter ||
        old.pendingPlacements.length != pendingPlacements.length ||
        !_samePending(old.pendingPlacements) ||
        _setChanged(old.searchMatchedIds, searchMatchedIds);
  }
}
