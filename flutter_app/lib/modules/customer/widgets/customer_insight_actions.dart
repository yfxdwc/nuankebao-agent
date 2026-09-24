// ============================================
// 客户洞察 L0 —— 「现在该做」行动卡 (详情页顶部, 切 Tab 可见)
//
// 主人 2026-09-23 拍板 P1 前端。设计依据:
//   · CHARTER §1.4 四要素最后一条「行动输出 = **明确的**跟进指引」
//     → 必须在**永远可见**的位置 (L0), 不是滚到第 8 屏
//   · CHARTER §1.4 强调"行动" ≠ "评分": 评分是参考, 行动是产出
//     → 评分卡本次 (2026-09-24) 搬到「分析」Tab, 但**行动卡留在 L0**
//     (贴告示 ≠ 修复: 不要因为诉求是"评分卡只在分析"就顺手把行动也搬走,
//      那等于"看起来优化了", 实则把"切 Tab 也可见"的核心拍板也撤了)
//
// 为什么评分是"确定性规则"而不是 AI:
//   销售一定会问「为什么是 78 分」→ 评分卡那侧可解释 (本文件已迁出);
//   AI 只补 action.script (会员)。本文件只关心"现在该做哪些事 + 一键闭环"。
//
// ⚠ 健壮性: 详情页的其他 section 不能因为本组件出错而消失 ——
//   所以加载失败 / 无数据时**静默降级** (SizedBox.shrink), 不抛异常。
//
// 2026-09-24 折叠态: 主人诉求「随页面上滑折叠到最少一行, 补折叠状态时卡片右上角
//   出现图标 (向下展开)」。
//   · collapsed == true + todos.isNotEmpty → 只渲染一行 header + 右侧 expand_more 图标
//   · collapsed == true + todos.isEmpty   → 「节奏正常」单行, **不**出图标
//     (没东西可展开, 出图标反而误导销售以为能点开看什么 —— 同根 §5
//      「贴告示 ≠ 修复」)
//   · collapsed == false                  → 完整展开 (原有渲染)
//   · 整块用 AnimatedSize 包, ~180ms easeOut, alignment 顶部 ——
//     不要生硬跳变 (Android 上突然出现一整块行动行 = 视觉跳)
//   · collapsed 由**详情页**管 (三个 Tab 各自滚动, 一处收口避免在每个
//     ScrollController 上挂监听; 详见 customer_detail_page.dart 的注释)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/customer_insight.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';

/// L0 行动卡 —— 评分卡不在这里 (评分卡移到分析 Tab, 见 customer_score_card.dart)
///
/// 切 Tab 也可见的"现在该做"指引 (CHARTER §1.4): 有行动 → 列表; 无行动 → 「节奏正常」。
///
/// 折叠态 (2026-09-24 主人诉求):
///   · `collapsed == true` + 有行动 → 只显示一行 header + 右上角 expand_more 图标
///   · `collapsed == true` + 无行动 → 「节奏正常」单行, **不**出图标 (没东西可展开)
///   · `collapsed == false` → 完整展开 (原有渲染)
class CustomerInsightActions extends ConsumerWidget {
  const CustomerInsightActions({
    super.key,
    required this.customerId,
    required this.onBuildTask,
    required this.onClaim,
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  final String customerId;

  /// 点「建任务」→ 由详情页写 follow_up_task (回写闭环, CHARTER §1.4)
  final Future<void> Function(ActionItem action) onBuildTask;
  /// 认领归属 (cta == 'claim_ownership' 时用) —— 建任务对这类行动是死路
  final Future<void> Function(ActionItem action) onClaim;

  /// 是否折叠到一行 header (详情页根据页面上滑状态传入, 本组件不感知 scroll)
  final bool collapsed;

  /// 折叠态下, 点 header 上的 expand_more 图标 → 详情页收到回调后切回展开
  /// (图标只在「确实有内容可展开」时才出, 不需要每种状态都收到回调)
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerInsightProvider(customerId));

    // 静默降级: 洞察拿不到不影响详情页其他部分
    return async.when(
      // 骨架 / 错误态不受 collapsed 影响 —— 折叠是**有内容**时的优化,
      // 加载中本来就不占空间, 折叠它没意义
      loading: () => const _ActionsSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (insight) => _ActionsBody(
        todos: insight.topActions,
        totalActions: insight.actions.length,
        onBuildTask: onBuildTask,
        onClaim: onClaim,
        collapsed: collapsed,
        onToggleCollapsed: onToggleCollapsed,
      ),
    );
  }
}

// ============================================
// 主体 (待办列表 / 节奏正常 / 折叠态)
// ============================================

class _ActionsBody extends StatelessWidget {
  const _ActionsBody({
    required this.todos,
    required this.totalActions,
    required this.onBuildTask,
    required this.onClaim,
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  final List<ActionItem> todos;
  final int totalActions;
  final Future<void> Function(ActionItem) onBuildTask;
  final Future<void> Function(ActionItem) onClaim;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  /// 折叠态只在「有行动可展开」时生效; 无行动时折叠 + 没图标, 跟「节奏正常」一致
  bool get _isCollapsed => collapsed && todos.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Container(
      decoration: BoxDecoration(
        color: t.surfaceCard,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: t.divider),
      ),
      // AnimatedSize: 折叠 / 展开切换平滑过渡 (~180ms easeOut),
      // alignment 顶部 → 折叠时行动区从顶部收起来 (而非从底部 / 中央)
      child: AnimatedSize(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: _isCollapsed
            // ── 折叠态: 只有一行 header ──
            ? _CollapsedHeader(
                todos: todos,
                totalActions: totalActions,
                onToggleCollapsed: onToggleCollapsed,
              )
            // ── 展开态: 现有完整渲染 ──
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── 有待办: 列表 (§1.4 行动输出; 永远可见) ──
                  if (todos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.cardPadding,
                        AppSpace.s10,
                        AppSpace.cardPadding,
                        AppSpace.s12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.checklist_rtl,
                                  size: AppSize.iconSm, color: t.textSecondary),
                              const SizedBox(width: AppSpace.s6),
                              Text(
                                '现在该做 (${todos.length})',
                                style: TextStyle(
                                  fontSize: AppType.sm,
                                  fontWeight: AppWeight.semibold,
                                  color: t.textPrimary,
                                ),
                              ),
                              const Spacer(),
                              if (totalActions > todos.length)
                                Text(
                                  '共 $totalActions 条',
                                  style: TextStyle(
                                      fontSize: AppType.xs, color: t.textTertiary),
                                ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.s8),
                          for (var i = 0; i < todos.length; i++) ...[
                            if (i > 0) const SizedBox(height: AppSpace.s8),
                            _ActionRow(
                              action: todos[i],
                              onBuildTask: () => onBuildTask(todos[i]),
                              onClaim: () => onClaim(todos[i]),
                            ),
                          ],
                        ],
                      ),
                    ),

                  // ── 无待办: 明确告诉销售"没事做" (而不是一片空白) ──
                  if (todos.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.cardPadding,
                        AppSpace.s10,
                        AppSpace.cardPadding,
                        AppSpace.s12,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: AppSize.iconSm, color: t.success),
                          const SizedBox(width: AppSpace.s6),
                          Text(
                            '节奏正常, 暂无该做的事',
                            style: TextStyle(fontSize: AppType.sm, color: t.textSecondary),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

// ============================================
// 折叠态 header (单行 + 右上角展开图标)
//
// 单独抽 widget 而不是塞回 _ActionsBody 里, 是为了:
//   1. AnimatedSize 切换时, 折叠态是**单一子节点**, 类型稳定 → Flutter 复用 Element,
//      切换动画更顺滑 (不用重建整棵 Column)
//   2. widget test 锁定图标更直接 (`find.byIcon(Icons.expand_more)` 就行,
//      不用 descendant 兜底)
//
// 触摸区 ≥ AppSize.tapMin (48pt): IconButton 默认 MaterialTapTargetSize.padded
// 是 48×48, 中老年手指友好 —— 同 AGENTS §1「移动优先, 移动端重度使用」。
// ============================================

class _CollapsedHeader extends StatelessWidget {
  const _CollapsedHeader({
    required this.todos,
    required this.totalActions,
    required this.onToggleCollapsed,
  });

  final List<ActionItem> todos;
  final int totalActions;
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.cardPadding,
        AppSpace.s10,
        AppSpace.s4, // 右侧少留点 padding, 让 IconButton 视觉上贴边
        AppSpace.s12,
      ),
      child: Row(
        children: [
          Icon(Icons.checklist_rtl, size: AppSize.iconSm, color: t.textSecondary),
          const SizedBox(width: AppSpace.s6),
          Expanded(
            child: Text(
              '现在该做 (${todos.length})',
              style: TextStyle(
                fontSize: AppType.sm,
                fontWeight: AppWeight.semibold,
                color: t.textPrimary,
              ),
            ),
          ),
          // 「共 N 条」小字 —— 折叠态也保留, 单行信息没成本, 让销售一眼看到总量
          if (totalActions > todos.length)
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.s4),
              child: Text(
                '共 $totalActions 条',
                style:
                    TextStyle(fontSize: AppType.xs, color: t.textTertiary),
              ),
            ),
          // 展开图标 —— IconButton 自带 tooltip「展开」 + 48×48 触摸区
          IconButton(
            icon: const Icon(Icons.expand_more, size: AppSize.iconMd),
            tooltip: '展开',
            // 详情页在「确实有内容可展开」时才会传回调 (collapsed && todos.isNotEmpty),
            // 这里给个空保护: 即便外部传了 null, 按钮也不该可点 (避免点了没反应)
            onPressed: onToggleCollapsed,
          ),
        ],
      ),
    );
  }
}

// ============================================
// 一条行动 (带"建任务"闭环)
// ============================================

class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.action,
    required this.onBuildTask,
    required this.onClaim,
  });

  final ActionItem action;
  final Future<void> Function() onBuildTask;
  final Future<void> Function() onClaim;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _busy = false;
  bool _done = false;

  /// 这条行动的闭环动作 —— 由**后端**声明 (action.cta), 不在前端按规则 id 硬编码
  Future<void> Function() get _run =>
      widget.action.isClaimOwnership ? widget.onClaim : widget.onBuildTask;

  Future<void> _build() async {
    if (_busy || _done) return;
    setState(() => _busy = true);
    try {
      await _run();
      if (mounted) setState(() => _done = true);
    } catch (_) {
      // ⚠ 错误提示由**回调自己**负责 (它知道业务上下文, 能说清"网络"还是"重复建")。
      //   这里吞掉只是**不让异常冒泡崩掉整个详情页** —— 行动区坏了不该拖垮其他 section。
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final a = widget.action;
    final dot = a.isHigh
        ? t.danger
        : a.priority == 'medium'
            ? t.accent
            : t.textTertiary;

    return Container(
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: a.isHigh ? t.dangerSurface : t.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 5),
                width: AppSpace.s6,
                height: AppSpace.s6,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
              ),
              const SizedBox(width: AppSpace.s8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            a.title,
                            style: TextStyle(
                              fontSize: AppType.md,
                              fontWeight: AppWeight.semibold,
                              color: t.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.s6),
                        Text(
                          '${a.when} · ${a.channelLabel}',
                          style:
                              TextStyle(fontSize: AppType.xs, color: t.textTertiary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.s2),
                    // why 是可核对的数字, 不是"AI 觉得"
                    Text(
                      a.why,
                      style: TextStyle(fontSize: AppType.xs, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.s8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '做完预期: ${a.expected}',
                  style: TextStyle(fontSize: AppType.micro, color: t.textTertiary),
                ),
              ),
              if (_done)
                Row(
                  children: [
                    Icon(Icons.check, size: AppSize.iconSm, color: t.success),
                    const SizedBox(width: AppSpace.s2),
                    Text(
                        // 「已建任务」对认领类行动是错的 —— 它压根没建任务
                        a.isClaimOwnership ? '已认领' : '已建任务',
                        style:
                            TextStyle(fontSize: AppType.xs, color: t.success)),
                  ],
                )
              else
                TextButton(
                  onPressed: _busy ? null : _build,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, AppSize.controlSm),
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: _busy
                      ? SizedBox(
                          width: AppSize.iconSm,
                          height: AppSize.iconSm,
                          child: const CircularProgressIndicator(strokeWidth: 2),
                        )
                      // ⚠ 认领类行动的按钮**不能**也用「认领为我的客户」——
                      //   那是它的标题文案, 同一行出现两遍既冗余又让人以为点错了
                      //   (其它规则天然不同: 标题「约下次到店」+ 按钮「建任务」)。
                      : Text(a.isClaimOwnership ? '认领' : '建任务'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================
// 骨架 (加载中, 矮骨架 —— L0 只占一行, 避免大跳)
// ============================================

class _ActionsSkeleton extends StatelessWidget {
  const _ActionsSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      // 矮骨架: L0 行动卡至少含一行"现在该做 (N)" + 一条行动 = 视觉上 ~80pt 起,
      //   用 48 太矮会跳; 用 56 给一行的最小呼吸感, 跟"行动区"的视觉重量匹配。
      height: AppSpace.s56,
      decoration: BoxDecoration(
        color: t.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: AppSize.iconLg,
        height: AppSize.iconLg,
        child: const CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}