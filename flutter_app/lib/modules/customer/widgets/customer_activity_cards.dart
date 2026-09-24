// ============================================
// 客户详情页 — 跟进任务 区 (2026-09-24 拍「记录 Tab 重构」)
//
// 本文件**只**保留「跟进任务」区: 互动的展示/记录已迁移到 `customer_timeline_section.dart`
// (混合列表 + 胶囊过滤); 旧 `CustomerInteractionSection` 已删除。
//
// 跟进任务区变化 (2026-09-24):
//   · header 右上角加紧凑「+ 新建」按钮 (不换行不溢出), 沿用原 `showAddFollowUpSheet`
//   · 底部「新建跟进任务」BigActionButton 已删 (原独占一行, 反 vibe;
//     同时跟「两个添加按钮在混合列表上方」重复 —— 删其一)
//   · 「N 条待办」计数保留
//
// 「标记完成」 → 弹出新弹层 (主人 2026-09-24 拍: 选跟进方式 + 记内容)。
//   弹层自己管 saving 转圈 → 本 widget 回归 ConsumerWidget,
//   去掉没用的状态和 setState。 (为什么这么改: 2026-09-24 反馈
//   「点击跟进后只看到任务没了」—— 一闪而过的 spinner 不解决"不知道怎么跟进的"问题,
//   弹层才对。)
//
// 2026-09-24 接 P1 / 折叠诉求 (本 commit): 跟进任务卡**不再**放在记录 Tab
//   滚动区里 —— 跟 L0「现在该做」一样, 在详情页 body 外层固定可见;
//   上滑随页面折叠成 header 一行 (有任务时右边出 expand_more 展开图标),
//   任务 tile 收起; 卡片保持白卡 (跟「现在该做」的警示琥珀**刻意**区分,
//   详见类注释)。
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/follow_up.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';
import '../../follow_up/widgets/complete_follow_up_sheet.dart';

// ============================================
// 建跟进任务 弹层 (客户详情页 / AI 跟进卡共用)
//
// 为什么不是独立页面:
//   `modules/follow_up/screens/` 还是空的 (没有 /follow-ups/new 路由),
//   而"从客户详情直接建一条跟进"是最高频入口 → 就地弹层, 不动路由/不动别的模块
// ============================================
Future<void> showAddFollowUpSheet(
  BuildContext context,
  WidgetRef ref, {
  required String customerId,
  String? aiSuggestion,
}) async {
  final reasonCtrl = TextEditingController();
  var dueAt = DateTime.now().add(const Duration(days: 1));
  var saving = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: AppSpace.s16,
          right: AppSpace.s16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('新建跟进任务',
                style: TextStyle(
                    fontSize: AppTheme.fontLg, fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpace.s12),
            TextField(
              controller: reasonCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(
                labelText: '跟进什么 *',
                hintText: '例: 打电话问腰疼好点没',
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            const Text('什么时候跟进',
                style: TextStyle(
                    fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
            const SizedBox(height: AppSpace.s8),
            Wrap(
              spacing: 8,
              children: [1, 2, 3, 7, 14]
                  .map((d) => ChoiceChip(
                        label: Text(
                          d == 1 ? '明天' : '${d} 天后',
                          style: const TextStyle(fontSize: AppTheme.fontSm),
                        ),
                        selected: dueAt
                                .difference(DateTime.now())
                                .inDays ==
                            d,
                        onSelected: (_) => setSheetState(
                            () => dueAt = DateTime.now().add(Duration(days: d))),
                      ))
                  .toList(),
            ),
            const SizedBox(height: AppSpace.s16),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (reasonCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('请填写跟进内容')),
                        );
                        return;
                      }
                      setSheetState(() => saving = true);
                      try {
                        await ref.read(followUpServiceProvider).create({
                          'customerId': customerId,
                          'dueAt': dueAt.toUtc().toIso8601String(),
                          'reason': reasonCtrl.text.trim(),
                          if (aiSuggestion != null && aiSuggestion.isNotEmpty)
                            'aiSuggestion': aiSuggestion,
                        });
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(content: Text('跟进任务已创建')),
                          );
                        }
                        ref.read(usageServiceProvider).track(
                              'follow_up_create',
                              props: {'source': 'customer_detail'},
                            );
                        ref.invalidate(
                            customerFollowUpTasksProvider(customerId));
                      } catch (e) {
                        setSheetState(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('保存失败: $e')),
                          );
                        }
                      }
                    },
              icon: const Icon(Icons.check, size: AppSize.iconLg),
              label: Text(saving ? '保存中...' : '保存'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, AppSize.buttonLgHeight),
              ),
            ),
            const SizedBox(height: AppSpace.s8),
          ],
        ),
      ),
    ),
  );
}

// ============================================
// 跟进任务 (该客户)
//
// 2026-09-24 接 P1 / 折叠诉求: 跟进任务卡**不再**放在记录 Tab 的滚动区里 ——
//   跟 L0「现在该做」一样, 在详情页 body 外层固定可见; 上滑随页面折叠成
//   header 一行 (有任务时右边出 expand_more 展开图标), 任务 tile 收起;
//   卡片保持白卡 (跟「现在该做」的警示琥珀**刻意**区分)。
//
// 折叠态细节 (照搬 L0 模式, 详见 customer_insight_actions.dart 注释):
//   · `collapsed == true` + 有任务 → 只渲染 header 一行 + 右侧 expand_more
//   · `collapsed == true` + 无任务 → 只渲染 header (没东西可展开, 不出图标,
//     跟展开态的「没有待办跟进」一致 —— 同根 §5「贴告示 ≠ 修复」)
//   · `collapsed == false` → 完整展开 (header + tiles / 空态文案)
//   · 切换用 AnimatedSize (~180ms easeOut, alignment 顶部) 平滑过渡
//
// **不上任何警示/高亮色** (主人 2026-09-24 原话: 「不需要高亮显示」):
//   折叠 = 收起任务 tile, 不是「还有待办被收起的告警信号」。L0 行动卡用
//   warning 琥珀是因为它折叠了**还有待办没处理**; 跟进卡折叠 = 收起任务列表
//   的视觉收纳动作, 没有"还有什么没处理"的语义, 用警示色反而把「正常收纳」
//   错位成「还有事要做」, 销售会被吓着每次展开都确认一下。维持 surfaceCard
//   (白) + 细灰顶边, 跟展开态**视觉一致**, 切换时只有"卡片高度变化"的
//   物理感, 没有"色块跳动"的信号冲击。
// ============================================

class CustomerFollowUpSection extends ConsumerWidget {
  final String customerId;

  /// 是否折叠到一行 header (详情页根据页面上滑状态传入, 本组件不感知 scroll)
  ///
  /// 默认 false —— 独立 widget 测试 / AI 跟进卡复用时不传也保持展开态, 不引入
  /// 「没人传 collapsed 却被吞成折叠态」的隐式 bug。
  final bool collapsed;

  /// 折叠态下, 点 header 上的 expand_more 图标 → 详情页收到回调后切回展开
  ///
  /// (图标只在「确实有任务可展开」时才出, 不是每种状态都收回调。)
  final VoidCallback? onToggleCollapsed;

  /// 测试锁定 key —— 详情页「不能随上滑全部不见了」验收断言通过 key 抓卡
  /// (`find.byKey(CustomerFollowUpSection.cardKey)` findsOneWidget)。
  /// 改这个 key 之前必先全仓 grep: 这是页面级测试 + 内部测试共用的契约。
  static const cardKey = ValueKey('followUpCard');

  const CustomerFollowUpSection({
    super.key,
    required this.customerId,
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('MM-dd');
    final async = ref.watch(customerFollowUpTasksProvider(customerId));

    // 折叠态只在「有任务可展开」时生效 —— collapsed 是详情页的滚动状态机
    // (上滑越过 24pt → true; 回顶 → false), 但光它自己不够:
    //   · collapsed=true + tasks=[] → 不折叠 (跟展开态「没有待办跟进」一致;
    //     出图标 = 误导, 同根 §5「贴告示 ≠ 修复」)
    //   · collapsed=false → 不管任务多少都不折叠
    // tasksForCollapse 是只读的快照 (从 async.maybeWhen 解出来), 下方
    // async.when 还会再读一次拿真正的 tasks (tile 渲染用)。
    final tasksForCollapse = async.maybeWhen<List<FollowUpTask>>(
      data: (t) => t,
      orElse: () => const <FollowUpTask>[],
    );
    final isCollapsed = collapsed && tasksForCollapse.isNotEmpty;

    return B2NoChrome(
      key: cardKey,
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      child: Container(
        // 细顶边: 卡片底仍是 surfaceCard (白, B2NoChrome 默认), 这里只加
        // 1px divider 顶边让卡片有"实体"的视觉重量 —— 不画全 border, 因为
        // 滚动时固定卡的四边紧贴 tab / AppBar, 画全 border 会跟屏幕边缘
        // 双线 (AppBar 也有底边)。
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.divider, width: 0.5),
          ),
        ),
        child: AnimatedSize(
          // ~180ms easeOut, alignment 顶部 → 折叠时任务列表从顶部收起来
          // (而不是从底部 / 中央), 跟 L0「现在该做」卡的折叠动画同手感
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: isCollapsed
              ? _FollowUpCollapsedHeader(
                  taskCount: tasksForCollapse.length,
                  onToggleCollapsed: onToggleCollapsed,
                  customerId: customerId,
                )
              : Padding(
                  padding: const EdgeInsets.all(AppSpace.s16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FollowUpHeader(
                        customerId: customerId,
                        taskCount: tasksForCollapse.length,
                      ),
                      const SizedBox(height: AppSpace.s12),
                      async.when(
                        loading: () =>
                            const _SectionLoading('加载跟进任务...'),
                        error: (e, _) => _SectionError(
                          message: '$e',
                          onRetry: () => ref.invalidate(
                              customerFollowUpTasksProvider(customerId)),
                        ),
                        data: (tasks) => tasks.isEmpty
                            ? const Text('没有待办跟进',
                                style: TextStyle(
                                    fontSize: AppTheme.fontSm,
                                    color: AppTheme.textSecondary))
                            : Column(
                                children: tasks
                                    .map((t) => _tile(context, ref, t, fmt))
                                    .toList(),
                              ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    WidgetRef ref,
    FollowUpTask t,
    DateFormat fmt,
  ) {
    // 2026-09-24 用户反馈修: 旧逻辑 `t.dueAt.isBefore(DateTime.now())` 按时间戳比,
    //   建完下一秒就误判"已过期"。改走日期口径 (`isFollowUpOverdue` = 与后端
    //   `urgency.ts::daysBetween > 0` 同口径), 今天 / 明天 / 更远 文案分开。
    final overdue = isFollowUpOverdue(t.dueAt);
    final daysUntil = followUpDaysUntilDue(t.dueAt);
    final dueLabel = overdue
        ? '${fmt.format(t.dueAt.toLocal())} · 已过期'
        : daysUntil == 0
            ? '今天到期'
            : daysUntil == 1
                ? '明天到期'
                : '${fmt.format(t.dueAt.toLocal())} 到期';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.s8),
      padding: const EdgeInsets.all(AppSpace.s12),
      decoration: BoxDecoration(
        color: overdue ? AppTheme.danger.withOpacity(0.06) : AppTheme.bgWarm,
        borderRadius: BorderRadius.circular(AppRadius.r10),
        border: Border.all(
          color: overdue
              ? AppTheme.danger.withOpacity(0.3)
              : AppColors.divider,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.reason,
                  style: const TextStyle(
                      fontSize: AppTheme.fontSm,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpace.s4),
                Text(
                  dueLabel,
                  style: TextStyle(
                    fontSize: AppTheme.fontXs,
                    color: overdue ? AppTheme.danger : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.check_circle_outline, size: AppSize.iconLg),
            tooltip: '标记完成',
            color: AppTheme.primary,
            onPressed: () async {
              // 2026-09-24 弹层接手: complete + 记互动 + track + invalidate +
              // SnackBar 都收进 showCompleteFollowUpSheet。返回值: true=业务完成 (含部分成功),
              // false=用户取消, null=异常。返回 false 时什么也不动 (本来就是用户的本意)。
              await showCompleteFollowUpSheet(context, ref, task: t);
            },
          ),
        ],
      ),
    );
  }
}

// ============================================
// 跟进任务卡 header (展开态复用)
//
// 抽出 header 让折叠态 / 展开态共用同一行, 切换时不重建 Row, 动画更顺滑;
// 也避免"展开态的 header 长这样、折叠态又长那样"的双源真相。
//
// 「+ 新建」按钮在**两种状态**都显示 —— 主人诉求只说"右侧 expand_more",
// 没说要藏「+ 新建」。理由:
//   · 折叠态仍要让销售能"在记录 Tab 顶部快速建任务" —— 把按钮塞进展开态
//     = 用户必须先展开 → 多一次交互, 反 vibe
//   · 视觉重量一行 header 也容得下「+ 新建」 + expand_more 两个按钮
//     (L0「现在该做」一张卡就放下了清单 + 折叠图标, 本卡更轻量)
// ============================================

class _FollowUpHeader extends ConsumerWidget {
  const _FollowUpHeader({
    required this.customerId,
    required this.taskCount,
  });

  final String customerId;
  final int taskCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      // header: 标题 + 「N 条待办」计数 + 右上角紧凑「新建」按钮 (2026-09-24 拍)
      //   原底部 BigActionButton 已删; 此处一行内同时容纳:
      //   · 标题 (固定左)
      //   · 「N 条待办」(Flexible, 窄屏省略, 中老年放大字号不撑破 Row)
      //   · 「+ 新建」按钮 (固定右, TextButton.icon 风格, **不换行不独占行**)
      children: [
        const Icon(Icons.task_alt,
            size: AppSize.iconLg, color: AppTheme.primary),
        const SizedBox(width: AppSpace.s8),
        const Expanded(
          child: Text('跟进任务',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: AppTheme.fontMd, fontWeight: FontWeight.w700)),
        ),
        // ⚠ 计数**不能**用 Flexible (2026-09-24 修): 标题是 Expanded (flex), 若计数
        //   也带 flex, 两者会平分"剩余空间" —— Flexible 用不完的份额留在行尾,
        //   导致「+ 新建」按钮浮在中间 (实测距右缘 283px!), 正是主人说的
        //   「按键整体靠右」没做到。改成**固定宽**子节点 (无 flex) → 让 Expanded
        //   标题吃掉全部剩余空间 → 计数 + 按钮被顶到右缘 (贴卡片右上角)。
        Text('$taskCount 条待办',
            style: const TextStyle(
                fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        const SizedBox(width: AppSpace.s8),
        FilledButton.icon(
          // 测试契约 key: 「+ 新建」要固定卡片右上角 (2026-09-24) —— 测试按 key 抓
          //   它的 rect 断言"最右控件 + 贴右缘"; 改 key 前先 grep 测试引用。
          key: const ValueKey('followUpNewButton'),
          // 「+ 新建」紧凑按钮 (header 行右侧, 不换行不溢出)
          //   visualDensity: compact 缩 padding 让按钮更紧, 避免中老年字号下被挤到下一行
          onPressed: () => showAddFollowUpSheet(context, ref,
              customerId: customerId),
          icon: const Icon(Icons.add, size: AppSize.iconMd),
          label: const Text('新建',
              style: TextStyle(fontSize: AppTheme.fontSm)),
          style: FilledButton.styleFrom(
            // 背景显式 (主人 2026-09-24: 「按键化, 按键背景显式」) ——
            //   浅主色底 + 深主色字 + 圆角, 一眼是「可以点的键」(不再是无背景文字链);
            //   elevation 0: 卡片里的次级动作, 不加浮起阴影抢视线。
            backgroundColor: AppTheme.primaryLight,
            foregroundColor: AppTheme.primaryDark,
            elevation: 0,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.s10, vertical: AppSpace.s4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.r10)),
          ),
        ),
      ],
    );
  }
}

// ============================================
// 折叠态 header (单行 + 右上角展开图标)
//
// 单独抽 widget 而不是塞回 CustomerFollowUpSection 里, 是为了:
//   1. AnimatedSize 切换时, 折叠态是**单一子节点**, 类型稳定 → Flutter 复用
//      Element, 切换动画更顺滑 (不用重建整棵 Column)
//   2. widget test 锁定图标更直接 (`find.byIcon(Icons.expand_more)` 就行,
//      不用 descendant 兜底)
//
// 触摸区 ≥ AppSize.tapMin (48pt): IconButton 默认 MaterialTapTargetSize.padded
// 是 48×48, 中老年手指友好 —— 同 AGENTS §1「移动优先, 移动端重度使用」。
//
// **不上任何警示/高亮色** (主人 2026-09-24 原话「不需要高亮显示」):
//   折叠 = 收起任务列表的视觉动作, 不是「还有事没处理」。前景色用 textPrimary /
//   textSecondary (跟展开态一致), 切换时只有高度变化的物理感, 没有色块跳动。
// ============================================

class _FollowUpCollapsedHeader extends ConsumerWidget {
  const _FollowUpCollapsedHeader({
    required this.taskCount,
    required this.onToggleCollapsed,
    required this.customerId,
  });

  final int taskCount;
  final VoidCallback? onToggleCollapsed;
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.s16,
        AppSpace.s10,
        AppSpace.s4, // 右侧少留 padding, IconButton 视觉贴边
        AppSpace.s10,
      ),
      child: Row(
        children: [
          // 图标 —— 跟展开态 header 保持一致 (task_alt), 卡片"还是那张卡"
          // 视觉提示, 不要换成别的图标 (换了会让用户以为是另外的东西)
          const Icon(Icons.task_alt,
              size: AppSize.iconLg, color: AppTheme.primary),
          const SizedBox(width: AppSpace.s8),
          Expanded(
            child: Text('跟进任务',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary)),
          ),
          // 「N 条待办」计数 —— 折叠态保留, 单行信息没成本, 销售一眼看到量。
          // ⚠ 同展开态: **不用** Flexible (flex 会跟 Expanded 标题抢空间, 留出
          //   行尾空隙 → 「+ 新建」贴不到右缘)。
          Text('$taskCount 条待办',
              style: const TextStyle(
                  fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(width: AppSpace.s4),
          // 展开图标 —— IconButton 自带 tooltip「展开」 + 48×48 触摸区。
          // 跟 L0「现在该做」同模式, 默认灰 (跟展开态 header 一致)。
          // ⚠ 2026-09-24 调序: 主人要求「+新建」贴卡片右上角 → 箭头**不能**再占
          //   最右位; 箭头移到按钮左边 (仍紧邻 header 右区, 可点展开)。
          IconButton(
            icon: const Icon(Icons.expand_more, size: AppSize.iconMd),
            tooltip: '展开',
            // 折叠态唯一可见的"展开"入口 —— 即便外部传了 null 也不该可点
            // (避免点了没反应; 同 L0 防御性处理)
            onPressed: onToggleCollapsed,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(AppSpace.s4),
          ),
          const SizedBox(width: AppSpace.s2),
          // 「+ 新建」按钮 —— **最右位 (卡片右上角)** (主人 2026-09-24 拍):
          //   折叠态也要能建任务 (避免展开→建→折叠 多一跳);
          //   箭头已在它左侧 → 它是 header 里唯一贴右边缘的控件。
          FilledButton.icon(
            // 测试契约 key: 跟展开态同一个 key (同一时刻只渲染一个头) ——
            //   测试用 `find.byKey` 抓 rect 断言"最右控件 + 贴右缘"
            key: const ValueKey('followUpNewButton'),
            onPressed: () => showAddFollowUpSheet(context, ref,
                customerId: customerId),
            icon: const Icon(Icons.add, size: AppSize.iconMd),
            label: const Text('新建',
                style: TextStyle(fontSize: AppTheme.fontSm)),
            style: FilledButton.styleFrom(
              // 背景显式 (主人 2026-09-24: 「按键化, 按键背景显式」) ——
              //   浅主色底 + 深主色字 + 圆角, 一眼是「可以点的键」(不再是无背景文字链);
              //   elevation 0: 卡片里的次级动作, 不加浮起阴影抢视线。
              backgroundColor: AppTheme.primaryLight,
              foregroundColor: AppTheme.primaryDark,
              elevation: 0,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.s10, vertical: AppSpace.s4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.r10)),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// 小块 (加载 / 错误)
//
// 跟进任务还在用, 保留; 旧的互动 section 跟随整体删除后, 这两个 helper 仍被
// CustomerFollowUpSection 引用 —— 不删。
// ============================================

class _SectionLoading extends StatelessWidget {
  final String label;
  const _SectionLoading(this.label);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const SizedBox(
              width: AppSpace.s18, height: AppSpace.s18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: AppSpace.s10),
          Text(label,
              style: const TextStyle(
                  fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
        ],
      );
}

class _SectionError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _SectionError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Column(
        // ⚠ mainAxisSize.min: 卡片被外部 Padding + Column 包裹, 这里只该占
        //   自己内容的空间 —— 不写 min 会让 Column 默认 mainAxisSize.max,
        //   在父级高度不够时 (e.g. 小视口测试 / L0 卡 + 跟进卡 + TabBar 撑满)
        //   触发 "RenderFlex overflowed" 渲染异常 (2026-09-24 详情页验收复现)。
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⚠ maxLines: 2 + ellipsis —— dio 错误信息能塞超长 (HTTP 错误 +
          //   request 详情)。原来不限行 → 在小视口测试里详情页整个 Column
          //   溢出 (错误占了两行 TabBarView 装不下)。限 2 行 + 「点重试」
          //   按钮能复用, 完整错误在该按钮的 onPressed 里发新请求拿新结果。
          Text('加载失败: $message',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: AppTheme.fontSm, color: AppTheme.danger)),
          const SizedBox(height: AppSpace.s8),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh, size: AppSize.iconMd),
            label: const Text('重试', style: TextStyle(fontSize: AppTheme.fontSm)),
            onPressed: onRetry,
          ),
        ],
      );
}
