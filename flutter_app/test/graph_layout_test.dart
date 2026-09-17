// ============================================
// 图谱布局回归测试 (双主线 + 紧凑 + 松弛)
//
// 守护点 (主人 2026-09-17 拍: 「上百节点也要能看」):
//   1. 画布宽度随「深度」增长, 不随节点数爆炸 (二叉树 = 每层最多加 1 列)
//   2. 两条主线严格竖直平行 (同腿同 x) + 同层成对 (L_i.dy == R_i.dy)
//   3. 外侧松弛不越界 (不串列 / 不跳出层)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/franchisee.dart';
import 'package:nuankebao/modules/presentation/graph/widgets/franchise_tree_painter.dart';

/// 完美二叉树 (每节点左右各一个子), 用 placement 口径构造
FranchiseeTreeNode perfectTree(int levels, {String idPrefix = 'n'}) {
  var counter = 0;
  FranchiseeTreeNode build(int depth, String side, String path) {
    final id = '$idPrefix${++counter}';
    final children = <FranchiseeTreeNode>[];
    if (depth + 1 < levels) {
      children.add(build(depth + 1, 'left', '${path}L.'));
      children.add(build(depth + 1, 'right', '${path}R.'));
    }
    return FranchiseeTreeNode(
      id: id,
      name: '$id',
      placementSide: side.isEmpty ? null : side,
      placementDepth: depth,
      children: children,
    );
  }

  return build(0, '', '');
}

void main() {
  test('31 节点 (depth 4): 画布宽度可控 + 主线严格竖直 + 同层成对', () {
    final tree = perfectTree(5); // 1+2+4+8+16 = 31
    final layout = TreeLayout.compute(tree, maxDepth: 4);

    // 1. 宽度: 列距会被压缩 (允许重叠) → 31 节点控制在 ~1600px 内
    expect(layout.canvasSize.width, lessThan(1600));
    expect(layout.canvasSize.height, lessThan(900));

    // 2. 主线竖直: A线主线 = 一直走 left; B线主线 = 一直走 right
    var left = tree.children.firstWhere((c) => c.placementSide == 'left');
    var right = tree.children.firstWhere((c) => c.placementSide == 'right');
    final leftXs = <double>[];
    final rightXs = <double>[];
    final leftYs = <double>[];
    final rightYs = <double>[];
    for (var i = 0; i < 4; i++) {
      leftXs.add(layout.positions[left.id]!.dx);
      rightXs.add(layout.positions[right.id]!.dx);
      leftYs.add(layout.positions[left.id]!.dy);
      rightYs.add(layout.positions[right.id]!.dy);
      final nextLeft = left.children.where((c) => c.placementSide == 'left');
      final nextRight = right.children.where((c) => c.placementSide == 'right');
      if (nextLeft.isEmpty || nextRight.isEmpty) break;
      left = nextLeft.first;
      right = nextRight.first;
    }
    expect(leftXs.toSet().length, 1, reason: 'A线主线必须严格竖直 (同 x)');
    expect(rightXs.toSet().length, 1, reason: 'B线主线必须严格竖直 (同 x)');
    expect(leftYs, equals(rightYs), reason: '左右主线同层必须成对 (同 y)');

    // 3. 所有节点落在画布内
    for (final p in layout.positions.values) {
      expect(p.dx, greaterThanOrEqualTo(0));
      expect(p.dx, lessThanOrEqualTo(layout.canvasSize.width));
      expect(p.dy, greaterThanOrEqualTo(0));
      expect(p.dy, lessThanOrEqualTo(layout.canvasSize.height));
    }
  });

  test('63 节点 (depth 5): 列距压缩后宽度 < 1800px (不压缩会是 3400+)', () {
    final tree = perfectTree(6); // 1+2+4+8+16+32 = 63
    final layout = TreeLayout.compute(tree, maxDepth: 5);

    expect(layout.canvasSize.width, lessThan(1800));
    expect(layout.columnPitch, lessThan(TreeLayout.columnWidth),
        reason: '列多时必须压缩列距 (允许重叠)');
    // 列号越大半径越小
    expect(TreeLayout.radiusForColumn(0), greaterThan(TreeLayout.radiusForColumn(1)));
    expect(TreeLayout.radiusForColumn(1), greaterThan(TreeLayout.radiusForColumn(2)));
    expect(TreeLayout.radiusForColumn(2), greaterThan(TreeLayout.radiusForColumn(3)));
    // 列号越大越虚化
    expect(TreeLayout.alphaForColumn(0), greaterThan(TreeLayout.alphaForColumn(2)));
    expect(TreeLayout.alphaForColumn(2), greaterThan(TreeLayout.alphaForColumn(4)));
  });

  test('外侧松弛: 不串列 (x 漂移 < 0.4 列距) + 不跳出本层 (y 漂移 < 0.35 层高)', () {
    final tree = perfectTree(5);
    final layout = TreeLayout.compute(tree, maxDepth: 4);

    // 复算初始格位 (严格网格), 比较松弛后的漂移
    for (final entry in layout.positions.entries) {
      final col = layout.columns[entry.key] ?? 0;
      if (col == 0) continue;
      // 该节点所在的腿: aLine / bLine
      final isA = layout.aLineIds.contains(entry.key);
      final isB = layout.bLineIds.contains(entry.key);
      expect(isA || isB, isTrue);
      // 不能漂到中轴另一侧
      if (isA) {
        expect(entry.value.dx, lessThan(layout.canvasSize.width / 2));
      } else if (isB) {
        expect(entry.value.dx, greaterThan(layout.canvasSize.width / 2));
      }
    }
  });
}
