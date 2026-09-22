// 图谱上层链模型单测 (ADR-0015 Q13, 主人 2026-09-22 拍「上行最多 3 层直系」)
//
// 关注点 (跟前两次「copyWith 漏带字段」的历史 bug 同款):
//   1. 新后端 uplines 数组 → 由近到远 3 条
//   2. 老后端只有单条 upline → 退化成 1 条 (不崩, 不空白)
//   3. 树根 (都没有) → 空列表
//   4. **copyWith (懒加载合并) 不能丢 uplines** —— 丢了 = 展开下级后上层格整条消失
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/franchisee.dart';

Map<String, dynamic> _up(String id, String name, int depth) => {
      'id': id,
      'name': name,
      'side': 'right',
      'depth': depth,
      'member': depth == 1,
    };

FranchiseeTreeNode _tree(Map<String, dynamic> json) =>
    FranchiseeTreeNode.fromJson({
      'id': '93',
      'name': '我',
      'placementSide': 'right',
      'placementDepth': 4,
      'relation': 'root',
      'children': const [],
      ...json,
    });

void main() {
  group('FranchiseeTreeNode.uplines', () {
    test('新后端: uplines 3 条, 由近到远 (level 语义由后端给)', () {
      final t = _tree({
        'uplines': [
          _up('81', '冯晓燕', 3),
          _up('78', '陈大壮', 2),
          _up('70', '李建国', 1),
        ],
        'upline': _up('81', '冯晓燕', 3),
      });
      expect(t.uplines.length, 3);
      expect(t.uplines.map((u) => u.name).toList(), ['冯晓燕', '陈大壮', '李建国']);
      expect(t.uplines.map((u) => u.depth).toList(), [3, 2, 1]);
      expect(t.uplines[0].member, isFalse); // depth=3 → member false (见 _up)
    });

    test('老后端: 只有单条 upline → 退化为 1 条 (旧字段兼容)', () {
      final t = _tree({'upline': _up('81', '冯晓燕', 3)});
      expect(t.uplines.length, 1);
      expect(t.uplines.single.name, '冯晓燕');
      expect(t.upline?.name, '冯晓燕'); // 旧字段仍在
    });

    test('树根: 两个字段都没有 → 空列表 (前端画「虚位以待」)', () {
      final t = _tree(const {});
      expect(t.uplines, isEmpty);
      expect(t.upline, isNull);
    });

    test('copyWith (懒加载合并) 不丢 uplines', () {
      final t = _tree({
        'uplines': [_up('81', 'A', 3), _up('78', 'B', 2)],
      });
      final copy = t.copyWith(children: const [], hasChildren: true);
      expect(copy.uplines.length, 2);
      expect(copy.uplines.map((u) => u.name).toList(), ['A', 'B']);
      expect(copy.uplineRequest, isNull);
    });

    test('脏数据 (uplines 里混非对象) → 跳过不崩', () {
      final t = _tree({
        'uplines': [
          _up('81', 'A', 3),
          'oops',
          42,
        ],
      });
      expect(t.uplines.length, 1);
      expect(t.uplines.single.name, 'A');
    });
  });
}
