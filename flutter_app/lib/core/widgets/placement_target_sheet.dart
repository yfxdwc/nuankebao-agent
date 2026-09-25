// ============================================
// 选上级点位弹层 (通用) — 主人 2026-09-18 拍
//   「发展为加盟商」(普通/种子 → 加盟) 和「移动点位」都用它
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/franchisee.dart';
import '../models/placement_request.dart';
import '../services/api.dart';
import '../providers/service_providers.dart';
import '../theme/app_theme.dart';

import '../theme/tokens.g.dart';
// ============================================
// 「发展为加盟商」选点位弹层 (主人 2026-09-18 拍 Q1)
// 先选上级节点 → 再选 A线/B线 → 可选「直推者」 → 返回 PlacementTarget 供上层发起三方确认
// ============================================
// ★ Phase B §6 E1 (客户标识体系): 「直推者」在落位发起时显式选 (默认 = 发起人)
//   - 选完点位父后, 拉 /api/franchisees/placement-requests/candidates
//   - 候选链 = targetParent + 上层直系 3 层
//   - 默认选项 = 服务端返回的 defaultReferrerFid (= 发起人 若在链内, 否则 = targetParent)

class PlacementTarget {
  final String parentId;
  final String parentName;
  final String side; // left | right
  /// ★ Phase B §6 E1: 显式选的直推者 (可选, null = 服务端默认 = 发起人)
  final String? referrerFid;
  const PlacementTarget(
    this.parentId,
    this.parentName,
    this.side, {
    this.referrerFid,
  });
}

/// 选上级点位 (+ A线/B线) 的通用弹层
///   - 客户详情「发展为加盟商」: title = 发展「张三」为加盟商
///   - 加盟商详情「移动点位」: title = 把「李四」挪到新的点位
class PlacementTargetSheet extends ConsumerStatefulWidget {
  final FranchiseeTreeNode tree;
  final String title;
  final String hint;
  const PlacementTargetSheet({
    required this.tree,
    required this.title,
    this.hint = '选一个上级点位 (你的图谱里任意节点) → 需要三方确认才生效',
  });

  @override
  ConsumerState<PlacementTargetSheet> createState() => PlacementTargetSheetState();
}

class PlacementTargetSheetState extends ConsumerState<PlacementTargetSheet> {
  String _search = '';
  FranchiseeTreeNode? _picked;
  String _side = 'left';

  /// ★ Phase B §6 E1: 直推者候选 (异步拉, 选中点位父后加载)
  ReferrerCandidatesResponse? _referrerCandidates;
  String? _referrerFid; // 选中的 referrerFid
  bool _loadingCandidates = false;
  String? _candidatesError;

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

  /// ★ Phase B §6 E1: 选了点位父后, 异步加载「直推者」候选链
  ///
  /// ★ 失败不影响主流程: 选不到就退回「默认 = 不传 (服务端给)」
  Future<void> _loadReferrerCandidates(String parentId) async {
    setState(() {
      _loadingCandidates = true;
      _candidatesError = null;
      _referrerCandidates = null;
      _referrerFid = null;
    });
    try {
      // 直接用 FranchiseeService (跟其他调用一致)
      final dio = ref.read(dioProvider);
      final api = FranchiseeService(dio);
      final resp = await api.getReferrerCandidates(targetParentId: parentId);
      if (!mounted) return;
      setState(() {
        _referrerCandidates = resp;
        _referrerFid = resp.defaultReferrerFid;
        _loadingCandidates = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _candidatesError = e.toString();
        _loadingCandidates = false;
      });
    }
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
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s16, AppSpace.s16, AppSpace.s8),
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
                const SizedBox(height: AppSpace.s4),
                Text(
                  widget.hint,
                  style: const TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: AppTheme.textSecondary,
                  ),
                ),
                if (hiddenCount > 0) ...[
                  const SizedBox(height: AppSpace.s2),
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
              child: TextField(
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                  hintText: '搜上级姓名',
                  prefixIcon: Icon(Icons.search, size: AppSize.iconLg),
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
                    onTap: () {
                      setState(() => _picked = e.node);
                      // ★ Phase B §6 E1: 选了点位父 → 拉直推者候选
                      _loadReferrerCandidates(e.node.id);
                    },
                  );
                },
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s0),
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
                  const SizedBox(height: AppSpace.s8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'left', label: Text('A线')),
                      ButtonSegment(value: 'right', label: Text('B线')),
                    ],
                    selected: {_side},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _side = v.first),
                  ),
                  // ★ Phase B §6 E1: 直推者选择区
                  const SizedBox(height: AppSpace.s16),
                  _buildReferrerPicker(context),
                  const SizedBox(height: AppSpace.s16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      PlacementTarget(
                        _picked!.id,
                        _picked!.name,
                        _side,
                        referrerFid: _referrerFid,
                      ),
                    ),
                    icon: const Icon(Icons.send, size: AppSize.iconMd),
                    label: const Text('提交 (走三方确认)',
                        style: TextStyle(fontSize: AppTheme.fontMd)),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, AppSpace.s56),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _picked = null;
                        _referrerCandidates = null;
                        _referrerFid = null;
                      });
                    },
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

  /// ★ Phase B §6 E1: 直推者选择 picker UI
  ///
  /// - 加载中: 转圈
  /// - 加载失败: 不显示 (默认 = 不传 referrerFid, 服务端给)
  /// - 加载成功: 弹出底部选择器 (Bottomsheet) 让用户从「祖先链」里挑一个
  ///   - 默认选项 = 发起人 (若有) 否则 = targetParent 本身 (服务端给)
  Widget _buildReferrerPicker(BuildContext context) {
    if (_loadingCandidates) {
      return Row(
        children: [
          const SizedBox(
            width: AppSpace.s16,
            height: AppSpace.s16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpace.s8),
          Text(
            '加载直推者选项…',
            style: TextStyle(
              fontSize: AppTheme.fontXs,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      );
    }
    if (_candidatesError != null) {
      // 静默退化: 不显示选择器 (默认 = 不传, 服务端 fallback)
      return const SizedBox.shrink();
    }
    final resp = _referrerCandidates;
    if (resp == null || resp.candidates.isEmpty) {
      return const SizedBox.shrink();
    }
    final pickedName = resp.candidates
        .firstWhere(
          (c) => c.id == _referrerFid,
          orElse: () => resp.candidates.first,
        )
        .name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.person_add_alt_1,
                size: AppSize.iconMd, color: AppTheme.textSecondary),
            const SizedBox(width: AppSpace.s8),
            Text(
              '直推者 (默认 = 发起人)',
              style: TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.s4),
        OutlinedButton.icon(
          icon: const Icon(Icons.person, size: AppSize.iconMd),
          label: Text(
            pickedName,
            style: const TextStyle(fontSize: AppTheme.fontMd),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, AppSpace.s48),
            alignment: Alignment.centerLeft,
          ),
          onPressed: () async {
            final pickedId = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              builder: (ctx) => _ReferrerPickerSheet(
                candidates: resp.candidates,
                currentId: _referrerFid,
              ),
            );
            if (pickedId != null) {
              setState(() => _referrerFid = pickedId);
            }
          },
        ),
      ],
    );
  }
}

/// ★ Phase B §6 E1: 「直推者」选择底部弹层
///   - 列表 = 候选链 (由近到远)
///   - 每行: 姓名 + level label + 「我」徽章 (若是自己)
///   - 当前选中高亮
class _ReferrerPickerSheet extends StatelessWidget {
  final List<ReferrerCandidate> candidates;
  final String? currentId;
  const _ReferrerPickerSheet({
    required this.candidates,
    required this.currentId,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      builder: (ctx, scrollController) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.s16, AppSpace.s16, AppSpace.s16, AppSpace.s8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选直推者',
                  style: const TextStyle(
                    fontSize: AppTheme.fontLg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpace.s4),
                Text(
                  '候选 = 落位后她的祖先链 (目标点位父 + 其上层直系 3 层)',
                  style: TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: candidates.length,
              itemBuilder: (_, i) {
                final c = candidates[i];
                final isSelected = c.id == currentId;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        isSelected ? AppTheme.primaryLight : AppTheme.bgCard,
                    child: Text(
                      c.name.isNotEmpty ? c.name[0] : '?',
                      style: const TextStyle(color: AppTheme.primaryDark),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.name,
                          style: const TextStyle(
                            fontSize: AppTheme.fontMd,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (c.isSelf) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.s6, vertical: AppSpace.s2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(AppRadius.r8),
                          ),
                          child: const Text(
                            '我',
                            style: TextStyle(
                              fontSize: AppTheme.fontXs,
                              color: AppTheme.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${c.levelLabel} · 第 ${c.depth} 层',
                    style: const TextStyle(fontSize: AppTheme.fontXs),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: AppTheme.primary)
                      : null,
                  onTap: () => Navigator.of(ctx).pop(c.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

  /// 「发展客户为加盟商」: 选上级点位 → 发起三方确认的落位申请 (主人 2026-09-18 拍 Q1)
