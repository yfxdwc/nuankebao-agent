// ============================================
// 加盟网络图谱 (Plan F3)
// CustomPainter 渲染二叉树 + Stack + Positioned 处理点击
// 中老年大字 + 大节点 (88pt)
//
// ⚠ DEPRECATED (v0.1.4, 拍板 2026-09-16): 路由 /franchise-tree 已重定向到
//   /customers?view=graph (客户页图谱 tab), 本文件 1 周观察期后主人 review 删除.
//   决策来源: ask_user domain_split=reuse_franchisee
//                          franchise_tree_page=redirect_to_customer
//   调用方: 0 (route redirect 后), import 已从 app_router.dart 删除
//   保留理由: 1 周观察期内主人手动 review, 确认无回退需求再 git rm
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/franchisee.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_empty.dart';
import '../../../core/widgets/franchise_chip.dart';
import '../../presentation/graph/widgets/franchise_node_sheet.dart';
import '../../presentation/graph/widgets/franchise_tree_painter.dart';
// fix-graph-zoom-pan v2 (2026-09-16): auto-fit initial scale
import 'dart:math' as math;

import '../../../core/theme/tokens.g.dart';
// W5 RBAC: ≤3 层硬限 (ADR-0006 / 《禁止传销条例》红线)
const int _maxAllowedDepth = 3;

class FranchiseTreePage extends ConsumerStatefulWidget {
  const FranchiseTreePage({super.key});

  @override
  ConsumerState<FranchiseTreePage> createState() => _FranchiseTreePageState();
}

class _FranchiseTreePageState extends ConsumerState<FranchiseTreePage> {
  int _depth = 3;
  FranchiseeTreeNode? _highlightedNode;

  /// 搜索框控制器 (加盟商名字模糊匹配)
  final _searchController = TextEditingController();
  String _search = '';

  /// fix-graph-zoom-pan v2: auto-fit initial scale (进页面看全树)
  final TransformationController _treeTransformController = TransformationController();
  bool _treeAutoFitApplied = false;

  @override
  void dispose() {
    _searchController.dispose();
    _treeTransformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncTree = ref.watch(myFranchiseeTreeProvider(_depth));

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的加盟网络'),
        toolbarHeight: AppSize.appBarHeight,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: AppSize.iconXl),
            tooltip: '刷新',
            onPressed: () => ref.invalidate(myFranchiseeTreeProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // 上级信息条 (如果有)
          asyncTree.maybeWhen(
            data: (tree) => _buildReferrerBar(tree),
            orElse: () => const SizedBox.shrink(),
          ),

          // 深度切换 chip
          _buildDepthSelector(),
          const Divider(height: 1),

          // 搜索框 (名字模糊匹配; 匹配节点 + 上下级链高亮, 其余淡化)
          asyncTree.maybeWhen(
            data: (tree) => _buildSearchBar(tree),
            orElse: () => const SizedBox.shrink(),
          ),

          // 搜索结果提示 (0 匹配时明示, 其余不占位)
          asyncTree.maybeWhen(
            data: (tree) => _buildSearchHint(tree),
            orElse: () => const SizedBox.shrink(),
          ),

          // 树渲染
          Expanded(
            child: asyncTree.when(
              loading: () => const LoadingState(),
              error: (e, _) => ErrorState(
                error: e,
                onRetry: () => ref.invalidate(myFranchiseeTreeProvider),
              ),
              data: (tree) => _buildTreeView(tree),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferrerBar(FranchiseeTreeNode tree) {
    if (tree.placementSide == null) return const SizedBox.shrink();
    return FutureBuilder(
      future: ref.read(franchiseeServiceProvider).getById(tree.id),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final me = snap.data!;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s10),
          color: AppTheme.franchisee.withOpacity(0.08),
          child: Row(
            children: [
              const Icon(Icons.arrow_upward, size: AppSize.iconMd, color: AppTheme.franchisee),
              const SizedBox(width: AppSpace.s8),
              const Text(
                '我的上级',
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpace.s8),
              Text(
                me.name,
                style: const TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.franchisee,
                ),
              ),
              const Spacer(),
              const FranchiseChip(type: 'franchisee', fontSize: AppType.micro),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDepthSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s12),
      color: AppTheme.bgWarm,
      child: Row(
        children: [
          const Text(
            '深度',
            style: TextStyle(
              fontSize: AppTheme.fontMd,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpace.s12),
          for (final d in [1, 2, _maxAllowedDepth]) ...[
            _depthChip(d),
            const SizedBox(width: AppSpace.s8),
          ],
          const SizedBox(width: AppSpace.s8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s8),
            decoration: BoxDecoration(
              color: AppTheme.franchisee.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadius.r20),
            ),
            child: const Text(
              '≤3 层',
              style: TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.franchisee,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${_depth}层',
            style: const TextStyle(
              fontSize: AppTheme.fontSm,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _depthChip(int d) {
    final selected = _depth == d;
    return GestureDetector(
      onTap: () => setState(() => _depth = d),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.white,
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.primary.withOpacity(0.4),
            width: AppSpace.s2,
          ),
          borderRadius: BorderRadius.circular(AppRadius.r20),
        ),
        child: Text(
          '$d层',
          style: TextStyle(
            fontSize: AppTheme.fontSm,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? Colors.white : AppTheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(FranchiseeTreeNode tree) {
    final q = _search.trim();
    // 预算匹配数 (用于后缀徽标, 全树 O(n) 走一遍)
    final matchCount =
        q.isEmpty ? 0 : _countMatches(tree, q.toLowerCase());
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 8, 16, 8),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(fontSize: AppTheme.fontMd),
        decoration: InputDecoration(
          hintText: '搜索加盟商名字',
          prefixIcon: const Icon(Icons.search, size: AppSize.iconLg),
          suffixIcon: q.isEmpty
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (matchCount > 0)
                      Container(
                        margin: const EdgeInsets.only(right: AppSpace.s4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.s8, vertical: AppSpace.s2),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(AppRadius.r10),
                        ),
                        child: Text(
                          '$matchCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: AppTheme.fontXs,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, size: AppSize.iconMd),
                      tooltip: '清除',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _search = '';
                          _highlightedNode = null;
                        });
                      },
                    ),
                  ],
                ),
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
    );
  }

  /// 递归遍历全树, 统计名字 contains(query) 的节点数
  int _countMatches(FranchiseeTreeNode node, String lowerQuery) {
    var c = node.name.toLowerCase().contains(lowerQuery) ? 1 : 0;
    for (final child in node.children) {
      c += _countMatches(child, lowerQuery);
    }
    return c;
  }

  /// 搜索结果提示条 (有查询且 0 匹配时显示红字提醒)
  Widget _buildSearchHint(FranchiseeTreeNode tree) {
    final q = _search.trim();
    if (q.isEmpty) return const SizedBox.shrink();
    final count = _countMatches(tree, q.toLowerCase());
    if (count > 0) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16, vertical: AppSpace.s6),
      color: AppTheme.danger.withOpacity(0.08),
      child: Text(
        '没有匹配「$q」的加盟商',
        style: const TextStyle(
          fontSize: AppTheme.fontXs,
          color: AppTheme.danger,
        ),
      ),
    );
  }

  /// 递归遍历全树, 返回名字 contains(query) 的节点 id 集合
  /// 拍平树 (给 painter 的 relations map 用)
  List<FranchiseeTreeNode> _flatten(FranchiseeTreeNode node) {
    final out = <FranchiseeTreeNode>[node];
    for (final c in node.children) {
      out.addAll(_flatten(c));
    }
    return out;
  }

  Set<String> _collectMatches(FranchiseeTreeNode node, String lowerQuery) {
    final result = <String>{};
    if (node.name.toLowerCase().contains(lowerQuery)) result.add(node.id);
    for (final child in node.children) {
      result.addAll(_collectMatches(child, lowerQuery));
    }
    return result;
  }

  Widget _buildTreeView(FranchiseeTreeNode tree) {
    // ★ 业务空状态 (非错误, 不走 ErrorState):
    //   - id == "0" / name == "未加盟": user 没加盟关系 (dev mode / 普通用户)
    //     → 旧版这情况是后端 404, Flutter ErrorState 误为「网络不太好」,
    //       误导用户. 业务上「未加盟」是合法状态, 应走 empty state.
    if (tree.id == '0' || tree.name == '未加盟') {
      return AppEmptyState(
        icon: Icons.account_tree_outlined,
        title: '还不是加盟商, 没有加盟网络',
        hint: '当前账号未关联加盟关系, 无法查看加盟图谱',
        action: FilledButton(
          onPressed: () => context.push('/customers/new'),
          child: const Text('+ 添加客户'),
        ),
      );
    }
    if (tree.children.isEmpty) {
      return AppEmptyState(
        icon: Icons.account_tree_outlined,
        title: '还没有下线',
        hint: '点击下方"添加下线"按钮, 发展第一位加盟商',
        action: FilledButton(
          onPressed: () => _showAddDownlineHint(tree),
          child: const Text('+ 添加下线'),
        ),
      );
    }

    // 计算画布大小 (v2 双主线布局: 两条主线平行直下 + 侧枝外侧展开)
    final layout = TreeLayout.compute(tree, maxDepth: _depth);
    final canvasSize = layout.canvasSize;
    final positions = layout.positions;

    // 搜索匹配集合 (空查询 → null, painter 不参与高亮)
    final q = _search.trim();
    final Set<String>? searchMatchedIds = q.isEmpty
        ? null
        : _collectMatches(tree, q.toLowerCase());

    // AGENTS §3 fix-graph-zoom-pan (2026-09-16): InteractiveViewer 替代嵌套 SingleChildScrollView
    //   v2 加 auto-fit initial scale: user 一进页面看全树, 然后手动 zoom/pan
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!_treeAutoFitApplied) {
          final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          final scaleX = viewportSize.width / canvasSize.width;
          final scaleY = viewportSize.height / canvasSize.height;
          final fitScale = math.max(0.1, math.min(scaleX, scaleY) * 0.95);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _treeTransformController.value = Matrix4.identity()..scale(fitScale);
            setState(() => _treeAutoFitApplied = true);
          });
        }
        return InteractiveViewer(
          transformationController: _treeTransformController,
          panEnabled: true,
          scaleEnabled: true,
          minScale: 0.1,
          maxScale: 3.0,
          boundaryMargin: const EdgeInsets.all(AppSpace.s80),
          child: SizedBox(
            width: canvasSize.width,
            height: canvasSize.height,
            child: Stack(
              children: [
                // 1. Painter (连线 + 节点圆形)
                CustomPaint(
                  size: canvasSize,
                  painter: FranchiseTreePainter(
                    root: tree,
                    positions: positions,
                    selectedNodeId: _highlightedNode?.id,
                    spineIds: layout.spineIds,
                    aLineIds: layout.aLineIds,
                    bLineIds: layout.bLineIds,
                    relations: {
                      for (final n in _flatten(tree)) n.id: n.relation,
                    },
                    searchMatchedIds: searchMatchedIds,
                    currentUserId: tree.id,
                  ),
                ),

                // 2. Positioned 透明 hitTest 区 (点击节点)
                ..._buildHitAreas(tree, positions),

                // 3. 空位提示 (虚线圆 + +号)
                ..._buildEmptySlots(tree, positions),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildHitAreas(
    FranchiseeTreeNode node,
    Map<String, Offset> positions,
  ) {
    final widgets = <Widget>[];
    final pos = positions[node.id];
    if (pos == null) return widgets;

    // 节点点击区 (方形, 88x88 中心)
    widgets.add(
      Positioned(
        left: pos.dx - TreeLayout.nodeRadius,
        top: pos.dy - TreeLayout.nodeRadius,
        width: TreeLayout.nodeSize,
        height: TreeLayout.nodeSize,
        child: GestureDetector(
          onTap: () => _onNodeTap(node),
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
      ),
    );

    for (final child in node.children) {
      widgets.addAll(_buildHitAreas(child, positions));
    }
    return widgets;
  }

  List<Widget> _buildEmptySlots(
    FranchiseeTreeNode node,
    Map<String, Offset> positions,
  ) {
    final widgets = <Widget>[];
    final pos = positions[node.id];
    if (pos == null) return widgets;

    // 当前节点下: 看左右是否有人, 没有就显示空位
    final hasLeft = node.children.any((c) => c.placementSide == 'left');
    final hasRight = node.children.any((c) => c.placementSide == 'right');

    if (!hasLeft) {
      widgets.add(_emptySlot(pos.translate(-40, 50), '左', () => _onEmptySlotTap(node, 'left')));
    }
    if (!hasRight) {
      widgets.add(_emptySlot(pos.translate(40, 50), '右', () => _onEmptySlotTap(node, 'right')));
    }

    for (final child in node.children) {
      widgets.addAll(_buildEmptySlots(child, positions));
    }
    return widgets;
  }

  Widget _emptySlot(Offset position, String label, VoidCallback onTap) {
    return Positioned(
      left: position.dx - 32,
      top: position.dy - 32,
      width: AppSpace.s64,
      height: AppSpace.s64,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.primary.withOpacity(0.4),
              width: AppSpace.s2,
              style: BorderStyle.solid,
            ),
            color: Colors.white.withOpacity(0.5),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add,
                size: AppSize.iconMd,
                color: AppTheme.primary,
              ),
              Text(
                '空$label',
                style: const TextStyle(
                  fontSize: AppType.micro,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onNodeTap(FranchiseeTreeNode node) {
    setState(() => _highlightedNode = node);
    showFranchiseNodeSheet(context, node: node);
  }

  void _onEmptySlotTap(FranchiseeTreeNode parent, String side) {
    // 跳转到添加下线页面, 预填 parent + side
    context.push('/franchisees/new?parentId=${parent.id}&sideHint=$side');
  }

  void _showAddDownlineHint(FranchiseeTreeNode tree) {
    // 根节点空树 → 跳转到添加页 (独立模式)
    context.push('/franchisees/new');
  }
}