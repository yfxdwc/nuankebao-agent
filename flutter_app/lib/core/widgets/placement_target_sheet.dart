// ============================================
// 选上级点位弹层 (通用) — 主人 2026-09-18 拍
//   「发展为加盟商」(普通/种子 → 加盟) 和「移动点位」都用它
// ============================================

import 'package:flutter/material.dart';

import '../models/franchisee.dart';
import '../theme/app_theme.dart';

// ============================================
// 「发展为加盟商」选点位弹层 (主人 2026-09-18 拍 Q1)
// 先选上级节点 → 再选 A线/B线 → 返回 PlacementTarget 供上层发起三方确认
// ============================================

class PlacementTarget {
  final String parentId;
  final String parentName;
  final String side; // left | right
  const PlacementTarget(this.parentId, this.parentName, this.side);
}

/// 选上级点位 (+ A线/B线) 的通用弹层
///   - 客户详情「发展为加盟商」: title = 发展「张三」为加盟商
///   - 加盟商详情「移动点位」: title = 把「李四」挪到新的点位
class PlacementTargetSheet extends StatefulWidget {
  final FranchiseeTreeNode tree;
  final String title;
  final String hint;
  const PlacementTargetSheet({
    required this.tree,
    required this.title,
    this.hint = '选一个上级点位 (你的图谱里任意节点) → 需要三方确认才生效',
  });

  @override
  State<PlacementTargetSheet> createState() => PlacementTargetSheetState();
}

class PlacementTargetSheetState extends State<PlacementTargetSheet> {
  String _search = '';
  FranchiseeTreeNode? _picked;
  String _side = 'left';

  List<({FranchiseeTreeNode node, int depth})> _flatten(
    FranchiseeTreeNode root,
  ) {
    final out = <({FranchiseeTreeNode node, int depth})>[];
    void walk(FranchiseeTreeNode n, int d) {
      out.add((node: n, depth: d));
      for (final c in n.children) {
        walk(c, d + 1);
      }
    }

    walk(root, 0);
    return out;
  }

  /// A线一层 + B线一层都有人 → 不能再挂新下线 (主人 2026-09-19 拍:
  ///   例: 高建军 左=彭桂英 右=邓国华 → 他就不能出现在「选上级点位」列表里)
  bool _slotsFull(FranchiseeTreeNode n) {
    final hasLeft = n.children.any((c) => c.placementSide == 'left');
    final hasRight = n.children.any((c) => c.placementSide == 'right');
    return hasLeft && hasRight;
  }

  @override
  Widget build(BuildContext context) {
    final flat = _flatten(widget.tree);
    // 两层已满的节点不进列表 (列表只给「还有空位」的上级)
    final all = flat.where((e) => !_slotsFull(e.node)).toList();
    final hiddenCount = flat.length - all.length;
    final q = _search.trim().toLowerCase();
    final list = q.isEmpty
        ? all
        : all.where((e) => e.node.name.toLowerCase().contains(q)).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: AppTheme.fontLg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.hint,
                  style: const TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (hiddenCount > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '已隐藏 $hiddenCount 个「两层已满」的节点（要挂到更深的位置，请先在该节点下级腾位置）',
                    style: const TextStyle(
                      fontSize: AppTheme.fontXs,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_picked == null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                  hintText: '搜上级姓名',
                  prefixIcon: Icon(Icons.search, size: 24),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final e = list[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.primaryLight,
                      child: Text(
                        e.node.name.isNotEmpty ? e.node.name[0] : '?',
                        style: const TextStyle(color: AppTheme.primaryDark),
                      ),
                    ),
                    title: Text(
                      e.node.name,
                      style: const TextStyle(
                        fontSize: AppTheme.fontMd,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      e.node.placementSide == null
                          ? '第 ${e.depth} 层 · 我 (根)'
                          : '第 ${e.depth} 层 · ${e.node.placementSide == 'left' ? 'A线' : 'B线'}',
                      style: const TextStyle(fontSize: AppTheme.fontXs),
                    ),
                    onTap: () => setState(() => _picked = e.node),
                  );
                },
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '加到「${_picked!.name}」的下级',
                    style: const TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'left', label: Text('A线')),
                      ButtonSegment(value: 'right', label: Text('B线')),
                    ],
                    selected: {_side},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _side = v.first),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      PlacementTarget(_picked!.id, _picked!.name, _side),
                    ),
                    icon: const Icon(Icons.send, size: 22),
                    label: const Text('提交 (走三方确认)',
                        style: TextStyle(fontSize: AppTheme.fontMd)),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _picked = null),
                    child: const Text('换个上级',
                        style: TextStyle(fontSize: AppTheme.fontMd)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

  /// 「发展客户为加盟商」: 选上级点位 → 发起三方确认的落位申请 (主人 2026-09-18 拍 Q1)
