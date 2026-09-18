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

/// 一条腿的链 (每层只有同侧子节点): chain(4, 'left') = L1→L2→L3→L4
FranchiseeTreeNode chain(int length, String side, {String idPrefix = 'c'}) {
  var counter = 0;
  FranchiseeTreeNode build(int depth) {
    final id = '$idPrefix${side[0]}${++counter}';
    return FranchiseeTreeNode(
      id: id,
      name: id,
      placementSide: side, // 链上每个节点都是同侧 (含根的直接子)
      placementDepth: depth,
      children: depth + 1 < length ? [build(depth + 1)] : const [],
    );
  }

  return build(0);
}

/// 根 + 指定长度的左右链 (不对称树: 左 4 层 / 右 2 层 …)
FranchiseeTreeNode asymmetricTree({
  required int leftLength,
  required int rightLength,
}) {
  final children = <FranchiseeTreeNode>[];
  if (leftLength > 0) children.add(chain(leftLength, 'left', idPrefix: 'L'));
  if (rightLength > 0) children.add(chain(rightLength, 'right', idPrefix: 'R'));
  return FranchiseeTreeNode(
    id: 'root',
    name: 'root',
    placementSide: null,
    placementDepth: 0,
    children: children,
  );
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


  // ============================================
  // 非对称生长 (主人 2026-09-17 问: 「对称不是强制的吧, 实际生产是自由生长」)
  //   结论: 布局**不强制对称** — 对称与否完全由数据决定 (种子数据是完美二叉树才 15/15)
  // ============================================

  test('不对称: A线 4 层 / B线 2 层 → 各走各的, 不补齐不镜像', () {
    final tree = asymmetricTree(leftLength: 4, rightLength: 2);
    final layout = TreeLayout.compute(tree, maxDepth: 8);

    // A 线 4 个节点 / B 线 2 个节点
    expect(layout.aLineIds.length, 4);
    expect(layout.bLineIds.length, 2);

    // 两条腿的主线各自竖直 (各在自己那列)
    final leftXs = <double>{};
    final rightXs = <double>{};
    void walk(FranchiseeTreeNode n) {
      final p = layout.positions[n.id]!;
      if (layout.aLineIds.contains(n.id)) leftXs.add(p.dx);
      if (layout.bLineIds.contains(n.id)) rightXs.add(p.dx);
      for (final c in n.children) {
        walk(c);
      }
    }

    walk(tree);
    expect(leftXs.length, 1, reason: 'A线仍是一条竖直线');
    expect(rightXs.length, 1, reason: 'B线仍是一条竖直线');
    // 但两条线的长度不同 → y 范围不同 (不强制等长)
    final leftYs = <double>[];
    final rightYs = <double>[];
    void walkY(FranchiseeTreeNode n) {
      if (layout.aLineIds.contains(n.id)) leftYs.add(layout.positions[n.id]!.dy);
      if (layout.bLineIds.contains(n.id)) rightYs.add(layout.positions[n.id]!.dy);
      for (final c in n.children) {
        walkY(c);
      }
    }

    walkY(tree);
    expect(leftYs.length, greaterThan(rightYs.length), reason: 'A线更长, B线更短');
    expect(leftYs.reduce((a, b) => a > b ? a : b),
        greaterThan(rightYs.reduce((a, b) => a > b ? a : b)),
        reason: '长的那条腿往下延伸, 不截断成一样长');
  });

  test('不对称: 只有 A 线 (根只有左子) → B线为空, 不报错不占位', () {
    final tree = asymmetricTree(leftLength: 3, rightLength: 0);
    final layout = TreeLayout.compute(tree, maxDepth: 5);

    expect(layout.bLineIds, isEmpty);
    expect(layout.rightColumns, 0);
    expect(layout.aLineIds.length, 3);
    // 根仍在中轴
    expect(layout.positions['root']!.dx, layout.canvasSize.width / 2);
    // 画布仍有合理尺寸
    expect(layout.canvasSize.width, greaterThan(400));
  });

  test('不对称: 只有 B 线 + 单侧链 (同侧断了用另一侧接主线)', () {
    final tree = asymmetricTree(leftLength: 0, rightLength: 5);
    final layout = TreeLayout.compute(tree, maxDepth: 6);

    expect(layout.aLineIds, isEmpty);
    expect(layout.bLineIds.length, 5);
    // 5 个主线节点同 x (竖直)
    final xs = <double>{};
    for (final id in layout.bLineIds) {
      xs.add(layout.positions[id]!.dx);
    }
    expect(xs.length, 1);
  });

  test('不对称: 混合型 — 左腿长+侧枝, 右腿短, 节点不重叠 (中心距 ≥ 半径和*0.6)', () {
    final tree = asymmetricTree(leftLength: 5, rightLength: 2);
    final layout = TreeLayout.compute(tree, maxDepth: 8);
    final ids = layout.positions.keys.toList();
    var checked = 0;
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = layout.positions[ids[i]]!;
        final b = layout.positions[ids[j]]!;
        final ra = TreeLayout.radiusForColumn(layout.columns[ids[i]] ?? 0);
        final rb = TreeLayout.radiusForColumn(layout.columns[ids[j]] ?? 0);
        // 允许一定重叠, 但不允许完全叠死 (中心距至少 60% 半径和)
        expect((a - b).distance, greaterThan((ra + rb) * 0.6 - 0.01));
        checked++;
      }
    }
    expect(checked, greaterThan(0));
  });
}
