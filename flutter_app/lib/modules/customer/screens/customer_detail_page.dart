// ============================================
// 暖客宝 客户详情页 (B1 客户域换装, 2026-09-24)
//
// 本文件从 customers_page.dart 拆出 (2026-09-24).
// 设计依据 (docs/ui-principles.md):
//   - 原则 1: 密度 = 尊重用户时间 (行高 60, 关键信息紧凑)
//   - 原则 4: 容器越少内容越强 (原则: 一屏有边框/阴影的元素 ≤ 2)
//   - 原则 5: 颜色是信号, 不是装饰 (状态色只在有状态时出现)
//
// 详情页结构 (P2 主人 2026-09-23 拍):
//   L0: CustomerInsightHeader (评分环 + 今日待办) — 切 Tab 也可见
//   TabBar: 记录 / 分析 / 管理
//   L0 在 TabBarView **外面** —— "切 Tab 才看见" = "要滚才看见" 的老毛病
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/customer.dart';
import '../../../core/models/customer_insight.dart';
import '../../../core/models/customer_ownership.dart';
import '../../../core/models/franchisee.dart';
import '../../../core/models/placement_request.dart';
import '../../../core/models/wellness_record.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/utils/birthday.dart';
import '../../../core/widgets/app_empty.dart';
import '../../../core/widgets/franchise_chip.dart';
import '../../../core/widgets/placement_target_sheet.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../screens/profile_sheets.dart' show showAvatarPickerSheet;
import '../../follow_up/widgets/follow_up_analysis_card.dart';
import '../widgets/ai_insight_cards.dart';
import '../widgets/customer_activity_cards.dart';
import '../widgets/customer_analysis_charts.dart';
import '../widgets/customer_insight_header.dart';
import '../widgets/danger_zone_card.dart';
import 'add_record_sheet.dart';
import '../widgets/ownership_card.dart';
import '../widgets/record_tile.dart';
import '../../../core/widgets/b2_no_chrome.dart';

// ============================================
// CustomerDetailPage (详情 + 3 Tab)
// ============================================

class CustomerDetailPage extends ConsumerWidget {
  final String customerId;
  const CustomerDetailPage({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCustomer = ref.watch(customerDetailProvider(customerId));

    // P2 (主人 2026-09-23 拍): 单页 11 section 堆叠 → L0 + 3 Tab
    //
    // 为什么用 DefaultTabController 而不是自己管 TabController:
    //   不需要 StatefulWidget / TickerProvider / dispose —— 本页没有
    //   "记住用户选了哪个 Tab" 的需求, 少一份生命周期就少一类 bug。
    //
    // 为什么 L0 在 TabBarView **外面**:
    //   CHARTER §1.4 的「行动输出 = 明确的跟进指引」必须**切 Tab 也可见** ——
    //   放进任一 Tab 里就等于"只有切到那个 Tab 才看得到", 又退回"要滚才看见"的老毛病。
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('客户详情'),
          toolbarHeight: AppSize.appBarHeight,
          actions: [
            IconButton(
              icon: const Icon(Icons.edit, size: AppSize.iconXl),
              tooltip: '编辑',
              onPressed: () => context.push('/customers/$customerId/edit'),
            ),
          ],
          // Tab 只在数据就绪后出现 (加载中/出错时没有东西可切, 显示 Tab 反而误导)
          bottom: asyncCustomer.maybeWhen(
            data: (_) => const TabBar(
              tabs: [
                Tab(text: '记录'),
                Tab(text: '分析'),
                Tab(text: '管理'),
              ],
            ),
            orElse: () => null,
          ),
        ),
        body: asyncCustomer.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState(error: e),
          data: (customer) => Column(
            children: [
              // L0: 评分环 + 今日待办 (免费层, 不烧 AI 额度; 拿不到数据时自己静默隐藏)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.pagePadding, AppSpace.s8, AppSpace.pagePadding, 0),
                child: CustomerInsightHeader(
                  customerId: customerId,
                  onBuildTask: (action) =>
                      _buildTaskFromAction(context, ref, action),
                  onClaim: (action) =>
                      _claimFromAction(context, ref, action),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildRecordTab(context, ref, customer),
                    _buildAnalysisTab(context, ref, customer),
                    _buildManagementTab(context, ref, customer),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 各 Tab 统一的滚动容器 (防止三个各写一遍 padding 漂移)
  ///
  /// ⚠ `primary: false` 是**必须的**, 不是可选优化 ——
  ///   三个 Tab 各有一个纵向 ListView, 默认 `primary: true` 时它们会**共用**
  ///   外层继承到的 `PrimaryScrollController` → 滚动位置互相串:
  ///   切到「分析」时继承了「记录」的偏移 → 顶部图表被顶出视口 →
  ///   语义树/截图里都看不到, 而 `find.text` 却仍能找到 **(极难排查)**。
  ///   每个 Tab 独立滚动位置本来就是正确的交互 (切 Tab 不该共享滚动)。
  Widget _tabScroll({required List<Widget> children}) =>
      SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.fromLTRB(AppSpace.pagePadding, AppSpace.s12,
            AppSpace.pagePadding, AppSpace.s48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );

  /// **记录 Tab** —— 三大动作之「记录」: 养生记录 + 跟进任务 + 互动流水
  Widget _buildRecordTab(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) {
    final asyncRecords = ref.watch(customerWellnessRecordsProvider(customerId));
    return _tabScroll(children: [
      // 养生记录 (含汇总: 共 N 次 / 最近到店)
      _buildWellnessSection(context, ref, asyncRecords),
      const SizedBox(height: AppSpace.cardGap),
      // 跟进任务 (该客户待办, 可直接勾完成)
      CustomerFollowUpSection(customerId: customerId),
      const SizedBox(height: AppSpace.cardGap),
      // 互动记录 (电话/微信/到店流水)
      CustomerInteractionSection(customerId: customerId),
    ]);
  }

  /// **分析 Tab** —— 三大动作之「分析」: 图谱 → 客观指标 → AI 解读
  Widget _buildAnalysisTab(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) {
    // 雷达图要吃 L0 的评分 (避免重复请求 /insight)
    final insight = ref.watch(customerInsightProvider(customerId)).valueOrNull;
    return _tabScroll(children: [
      // ★ P4 图谱 (主人 2026-09-23 拍): 雷达 / 效果趋势 / 部位热力
      //   放最上面: 图比文字快 —— "她整体怎样" 一眼就能看出
      //
      // ⚠ 不要写成 `if (insight != null) CustomerAnalysisCharts(...)` ——
      //   那会让"洞察还没就绪"时整块图表消失 (趋势/部位只依赖 /charts, 被无关依赖拖累)。
      //   传可空 score, 组件内部显示加载/空态。
      CustomerAnalysisCharts(
        customerId: customerId,
        score: insight?.score,
      ),
      const SizedBox(height: AppSpace.cardGap),
      // 客观指标 (免费)
      FollowUpAnalysisCard(customerId: customerId),
      const SizedBox(height: AppSpace.cardGap),
      // AI 智能区 (会员): 顺序按「销售员每天最用得上」排
      //   复购预测 (自动算, 不烧额度) → 跟进建议 (开口话术) → 轮廓画像 (这人是谁) → 效果分析 (疗程有没有用)
      _buildSectionTitle('AI 助手'),
      RepurchaseCard(customerId: customerId),
      AiFollowUpCard(customerId: customerId),
      AiProfileCard(customerId: customerId),
      EffectAnalysisCard(customerId: customerId),
    ]);
  }

  /// **管理 Tab** —— 三大动作之「管理」: 档案字段 + 类型 + 身份
  ///
  /// 为什么把这三个从首屏挪进 Tab:
  ///   它们是"设置频次"的内容 (改一次就不动), 却占着详情页最宝贵的前两屏。
  ///   L0 要留给"每天看"的东西 (§1.4 行动输出)。
  Widget _buildManagementTab(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
  ) {
    return _tabScroll(children: [
      // 大头像 + 基本信息 (类型徽章 / 年龄 / 拨号)
      _buildHeader(context, ref, customer),
      const SizedBox(height: AppSpace.cardGap),
      // ★ 归属 (P7 管理维度补的缺口): 谁把她当客户在管 + 认领
      //   放在类型卡**之前**: 归属是"她算不算我的客户"的前提,
      //   比"她是普通还是种子客户"更前置 (ADR-0015 Q11/Q12)。
      CustomerOwnershipCard(customerId: customerId),
      const SizedBox(height: AppSpace.cardGap),
      // 客户类型切换 (主人 2026-09-18: 「没找到修改客户类型的入口」)
      _buildTypeCard(context, ref, customer),
      const SizedBox(height: AppSpace.cardGap),
      // app 身份 (ADR-0016): 已注册 / 未注册 + 填邀请码绑定
      _buildIdentityCard(context, ref, customer),
      const SizedBox(height: AppSpace.cardGap),
      // ★ 危险操作 (P8): 归档 / (后续: 合并) —— 放最底部, 需要时才滑下来看
      CustomerDangerZoneCard(
        customerId: customerId,
        customerName: customer.name,
      ),
    ]);
  }

  /// 「认领归属」—— 把 `profile_incomplete` 那条行动的闭环做完
  ///
  /// 2026-09-23 修 (主人拍「先挂起…修」后落的): 这条行动原本只有一个「建任务」按钮,
  ///   而建任务**完全不碰 `customer.owner_id`** → `hasOwner` 恒为 false →
  ///   行动永远消不掉 (死路, 详见 docs/backlog 挂起项)。
  ///
  /// 本方法的职责就是把「行动」真闭环: 改归属 → 刷新洞察 (hasOwner 变 true → 行动消失)
  ///   + 刷新归属卡 / 客户列表 (三处都受归属影响)。
  Future<void> _claimFromAction(
    BuildContext context,
    WidgetRef ref,
    ActionItem action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(customerServiceProvider).claim(customerId);
      // 归属变了 → 这四处都受影响
      ref.invalidate(customerInsightProvider(customerId)); // 行动据此消失
      ref.invalidate(customerOwnershipProvider(customerId)); // 管理 Tab 的归属卡
      ref.invalidate(customerDetailProvider(customerId));
      ref.invalidate(customersProvider); // “我的客户”列表
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('已认领为我的客户'),
        ),
      );
    } catch (e) {
      // 409/400 都有业务含义 (被别人抢先 / 是自己) —— 把后端的话翻成人话给用户
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text(humanClaimError(e))),
      );
    }
  }

  /// 「建任务」—— 把一条行动指引落成 follow_up_task (闭环的关键一步)
  ///
  /// 为什么这是 P1 的核心: CHARTER §1.4 要求"明确的**可落地**跟进指引"。
  ///   只给一段话术 = 不可勾选/不可追踪; 建了任务才有 dueAt + 状态 + 完成回写,
  ///   完成率还会反哺下一轮评分的「任务健康」因子。
  Future<void> _buildTaskFromAction(
    BuildContext context,
    WidgetRef ref,
    ActionItem action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dueAt = DateTime.tryParse(action.taskDueAt) ?? DateTime.now();
      await ref.read(followUpServiceProvider).create({
        'customerId': customerId,
        'dueAt': dueAt.toUtc().toIso8601String(),
        'reason': action.taskTitle,
      });
      ref.read(usageServiceProvider).track('follow_up_task_created',
          props: {'from': 'insight_action', 'rule': action.id});
      // 任务列表 / 洞察都刷新 (洞察的"任务健康"因子会变)
      ref.invalidate(customerInsightProvider(customerId));
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('已建任务「${action.taskTitle}」',
              style: const TextStyle(fontSize: AppType.md)),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('建任务失败: $e',
              style: const TextStyle(fontSize: AppType.md)),
        ),
      );
    }
  }

  /// 养生记录区: 汇总 + 最近 5 条 + 入口
  Widget _buildWellnessSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<WellnessRecord>> asyncRecords,
  ) {
    return B2NoChrome(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.favorite, size: AppSize.iconLg, color: AppTheme.accent),
                const SizedBox(width: AppSpace.s8),
                const Expanded(
                  child: Text('养生记录',
                      style: TextStyle(
                          fontSize: AppTheme.fontMd,
                          fontWeight: FontWeight.w700)),
                ),
                asyncRecords.maybeWhen(
                  data: (records) {
                    if (records.isEmpty) return const SizedBox.shrink();
                    // Flexible: 窄屏/大字体下让文案省略, 不撑破 Row (中老年常放大系统字号)
                    return Flexible(
                      child: Text(
                        _recordSummary(records),
                        style: const TextStyle(
                            fontSize: AppTheme.fontXs,
                            color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    );
                  },
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            asyncRecords.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpace.s8),
                child: LoadingState(),
              ),
              error: (e, _) => Text('加载失败: $e',
                  style: const TextStyle(color: AppTheme.danger)),
              data: (records) {
                if (records.isEmpty) {
                  return _buildEmptyHint('还没有记录', '点下面的「添加记录」开始');
                }
                // 字典可能还没加载完 —— 为 null 时卡片回落显示「养生记录」而不是白屏
                final dict = ref
                    .watch(dictionariesProvider)
                    .maybeWhen(data: (d) => d, orElse: () => null);
                return Column(
                  children: [
                    ...records.take(5).map((r) => RecordTile(
                          record: r,
                          dict: dict,
                          onTap: () => context.push('/wellness-records/${r.id}'),
                        )),
                    if (records.length > 5)
                      TextButton.icon(
                        onPressed: () => _showAllRecords(context, ref, records),
                        icon: const Icon(Icons.expand_more, size: AppSize.iconMd),
                        label: Text('查看全部 ${records.length} 条',
                            style: const TextStyle(fontSize: AppTheme.fontSm)),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpace.s8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        showAddRecordSheet(context, customerId: customerId),
                    icon: const Icon(Icons.add_circle_outline, size: AppSize.iconLg),
                    label: const Text('+ 添加记录'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, AppSize.buttonLgHeight),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 全部记录 (底部弹层; 列表长了不把详情页撑爆)
  void _showAllRecords(
    BuildContext context,
    WidgetRef ref,
    List<WellnessRecord> records,
  ) {
    // ⚠ 2026-09-23 修: 这里原来读的是 `r.bodyParts` / `r.serviceItem` ——
    //   `WellnessRecord` 上**根本没有这两个字段** (只有 bodyPartIds / serviceItemId)。
    //   因为列表声明是 List<dynamic>, 编译期不报错, **运行时必抛 NoSuchMethodError**。
    //   而且 "查看全部" 按钮只在 >5 条时才出现 —— 客户测试数据都是 3 条，
    //   所以一直没人碰到。类型收紧成 List<WellnessRecord> 后立即暴露。
    final dict = ref
        .watch(dictionariesProvider)
        .maybeWhen(data: (d) => d, orElse: () => null);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (_, controller) => ListView.builder(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
              AppSpace.pagePadding, 0, AppSpace.pagePadding, AppSpace.s24),
          itemCount: records.length,
          itemBuilder: (ctx, i) {
            final r = records[i];
            return RecordTile(
              record: r,
              dict: dict,
              onTap: () {
                Navigator.pop(ctx);
                context.push('/wellness-records/${r.id}');
              },
            );
          },
        ),
      ),
    );
  }

  /// 记录汇总行: 「共 N 次 · 最近 X · 平均 Y 天一次」
  ///
  /// 「平均 Y 天一次」与 P1 洞察 / `follow-up-analysis` 的复购周期**同口径**
  /// (相邻两次到店天数的均值) —— 三处显示同一个数, 销售才不会觉得"两个地方说的不一样"。
  /// 不足 2 次算不出间隔 → 只显示前两段 (宁可少一条信息, 不编)。
  String _recordSummary(List<WellnessRecord> records) {
    if (records.isEmpty) return '';
    final last = records.first.serviceDate;
    final parts = <String>['共 ${records.length} 次', '最近 $last'];

    if (records.length >= 2) {
      // records 按 serviceDate 倒序 (后端 orderBy desc) → 排序后算相邻差
      final days = records
          .map((r) => DateTime.tryParse(r.serviceDate))
          .whereType<DateTime>()
          .toList()
        ..sort();
      if (days.length >= 2) {
        var sum = 0;
        var n = 0;
        for (var i = 1; i < days.length; i++) {
          final d = days[i].difference(days[i - 1]).inDays;
          if (d >= 0) {
            sum += d;
            n++;
          }
        }
        if (n > 0) parts.add('平均 ${(sum / n).round()} 天一次');
      }
    }
    return parts.join(' · ');
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, Customer c) {
    final type = c.customerType;
    final age = c.birthYear == null
        ? null
        : DateTime.now().year - c.birthYear!;
    return B2NoChrome(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: Column(
          children: [
            // 头像 + 右下角相机角标 (主人 2026-09-18 拍: 点它设置客户头像)
            GestureDetector(
              onTap: () => _pickCustomerAvatar(context, ref, c),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  UserAvatar(
                    avatarUrl: c.avatar,
                    name: c.name,
                    size: AppTheme.avatarLg,
                  ),
                  // 相机角标 (64pt 头像右下角, 触摸区 32pt 对中老年友好)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: AppSpace.s32,
                      height: AppSpace.s32,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: AppSpace.s2),
                      ),
                      child: const Icon(Icons.photo_camera,
                          size: AppSize.iconSm, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.s6),
            const Text(
              '点头像可以换 (拍照 / 相册 / 现成头像)',
              style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppSpace.s6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    c.name,
                    style: const TextStyle(
                      fontSize: AppTheme.fontXl,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
                // 类型徽章 (加盟紫 / 种子橙 / 普通绿) —— 跟客户列表同口径
                FranchiseChip(type: type),
              ],
            ),
            const SizedBox(height: AppSpace.s6),
            Text(
              _maskPhone(c.phone),
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                color: AppTheme.textSecondary,
              ),
            ),
            if (c.gender != null || age != null) ...[
              const SizedBox(height: AppSpace.s8),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (c.gender != null)
                    Chip(label: Text(c.gender == 'F' ? '女' : c.gender == 'M' ? '男' : '未知')),
                  if (age != null) Chip(label: Text('$age 岁')),
                  Chip(
                    label: Text(
                        '建档 ${DateFormat('yyyy-MM-dd').format(c.createdAt)}'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpace.s12),
            // 快捷操作: 打电话 / 记一次互动 (拨号在 web 不支持时静默失败)
            Row(
              children: [
                Expanded(
                  child: BigActionButton(
                    icon: Icons.phone,
                    label: '打电话',
                    compact: true,
                    onTap: () => _callCustomer(context, ref, c.phone),
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: BigActionButton(
                    icon: Icons.edit_note,
                    label: '记一次互动',
                    compact: true,
                    onTap: () => _showAddInteractionSheet(context, ref, c.id),
                  ),
                ),
              ],
            ),
            // 生日 + 提醒 (主人 2026-09-18)
            if (c.birthMonth != null && c.birthDay != null) ...[
              const SizedBox(height: AppSpace.s10),
              Builder(builder: (_) {
                final info = birthdayInfo(
                  month: c.birthMonth,
                  day: c.birthDay,
                  calendar: c.birthCalendar,
                );
                final due = isInBirthdayRemindWindow(
                  month: c.birthMonth,
                  day: c.birthDay,
                  calendar: c.birthCalendar,
                  remindDays: c.birthdayRemindDays,
                );
                final nextSolar = info?.nextSolarDate;
                final nextSolarText = nextSolar == null
                    ? ''
                    : ' · 下次 ${nextSolar.year}-${nextSolar.month.toString().padLeft(2, '0')}-${nextSolar.day.toString().padLeft(2, '0')}';
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s10),
                  decoration: BoxDecoration(
                    color: due
                        ? AppTheme.accent.withOpacity(0.18)
                        : AppTheme.bgWarm,
                    borderRadius: BorderRadius.circular(AppRadius.r10),
                    border: Border.all(
                      color: due ? AppTheme.accent : AppColors.divider,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cake_outlined,
                              size: AppSize.iconMd,
                              color: due ? AppTheme.accent : AppTheme.primaryDark),
                          const SizedBox(width: AppSpace.s6),
                          Expanded(
                            child: Text(
                              '生日 ${birthdayLabel(month: c.birthMonth, day: c.birthDay, calendar: c.birthCalendar, year: c.birthYear)}'
                              '${info != null ? ' · ${info.countdownLabel}' : ''}',
                              style: TextStyle(
                                fontSize: AppTheme.fontSm,
                                fontWeight: FontWeight.w600,
                                color: due ? AppTheme.accent : AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpace.s4),
                      Text(
                        '提醒: ${remindLabel(c.birthdayRemindDays)}$nextSolarText',
                        style: const TextStyle(
                            fontSize: AppTheme.fontXs,
                            color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                );
              }),
            ] else if (c.birthYear != null) ...[
              const SizedBox(height: AppSpace.s10),
              Text(
                '生日未填 (只知道年份 ${c.birthYear}) · 填上月日可开启生日提醒',
                style: const TextStyle(
                    fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
              ),
            ],
            if (c.diseaseHistory != null && c.diseaseHistory!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s12),
              Container(
                padding: const EdgeInsets.all(AppSpace.s12),
                decoration: BoxDecoration(
                  color: AppColors.dangerSurface,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                ),
                child: Text(
                  '既往病史: ${c.diseaseHistory}',
                  style: const TextStyle(
                    fontSize: AppTheme.fontSm,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
            if (c.allergyHistory != null && c.allergyHistory!.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s8),
              Container(
                padding: const EdgeInsets.all(AppSpace.s12),
                decoration: BoxDecoration(
                  color: AppColors.accentSurfaceWarm,
                  borderRadius: BorderRadius.circular(AppRadius.r8),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: AppSize.iconMd, color: AppTheme.accent),
                    const SizedBox(width: AppSpace.s6),
                    Expanded(
                      child: Text(
                        '过敏史: ${c.allergyHistory}',
                        style: const TextStyle(
                          fontSize: AppTheme.fontSm,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (c.healthTags.isNotEmpty) ...[
              const SizedBox(height: AppSpace.s12),
              _buildHealthTags(c),
            ],
          ],
        ),
      ),
    );
  }

  /// 换客户头像 (主人 2026-09-18 拍)
  ///   复用「我的」页那套 sheet: 候选头像 (8 个养生图标) + 拍照 + 相册 + 恢复默认;
  ///   区别只是保存动作 = PATCH /api/customers/:id 的 avatar 字段
  Future<void> _pickCustomerAvatar(
    BuildContext context,
    WidgetRef ref,
    Customer c,
  ) async {
    final changed = await showAvatarPickerSheet(
      context,
      ref,
      currentAvatarUrl: c.avatar,
      name: c.name,
      title: '给「${c.name}」设头像',
      subtitle: '拍照 / 相册上传, 或挑一个现成的 (不想用真人照片就选花草茶禅)',
      onApply: (value) async {
        await ref
            .read(customerServiceProvider)
            .update(c.id, {'avatar': value});
        ref.invalidate(customerDetailProvider(c.id));
        // 列表里的小头像也跟着刷新
        ref.invalidate(customersProvider);
      },
    );
    if (changed && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('头像已更新')),
      );
    }
  }

  /// 拨号 (tel:) — web 不支持时给提示, 不崩
  Future<void> _callCustomer(
      BuildContext context, WidgetRef ref, String phone) async {
    ref.read(usageServiceProvider).track('customer_call');
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法拨号, 号码: $phone')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法拨号, 号码: $phone')),
        );
      }
    }
  }

  /// 记一次互动 (电话/微信/到店/节日问候/其他 + 备注)
  void _showAddInteractionSheet(
    BuildContext context, WidgetRef ref, String customerId) {
    const types = {
      'phone': '电话',
      'wechat': '微信',
      'visit': '到店',
      'holiday_greeting': '节日问候',
      'other': '其他',
    };
    var selected = 'phone';
    final summaryCtrl = TextEditingController();
    var saving = false;

    showModalBottomSheet(
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
              const Text('记一次互动',
                  style: TextStyle(
                      fontSize: AppTheme.fontLg, fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.s12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: types.entries
                    .map((e) => ChoiceChip(
                          label: Text(e.value,
                              style: const TextStyle(fontSize: AppTheme.fontSm)),
                          selected: selected == e.key,
                          onSelected: (_) =>
                              setSheetState(() => selected = e.key),
                        ))
                    .toList(),
              ),
              const SizedBox(height: AppSpace.s12),
              TextField(
                controller: summaryCtrl,
                maxLines: 3,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                    labelText: '聊了什么 (可选)', hintText: '例: 说腰疼好多了, 约下周三'),
              ),
              const SizedBox(height: AppSpace.s12),
              FilledButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        setSheetState(() => saving = true);
                        try {
                          await ref
                              .read(interactionServiceProvider)
                              .create({
                            'customerId': customerId,
                            'type': selected,
                            if (summaryCtrl.text.isNotEmpty)
                              'summary': summaryCtrl.text,
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('已记录')),
                            );
                          }
                          ref.invalidate(interactionsForCustomerProvider(customerId));
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

  /// 客户类型卡 (普通 ↔ 种子 一键切换; 加盟类型由关系决定不可切)
  /// app 身份卡 (ADR-0016, 主人 2026-09-22 拍):
  ///   「客户列表中的客户有一些也是 app 用户, 有一些没有注册 app 账号」
  ///   → 详情页给出状态; 没绑定的可以**填她的邀请码 (身份识别码)** 绑定 —— 手机号对不上也能绑
  Widget _buildIdentityCard(BuildContext context, WidgetRef ref, Customer c) {
    final bound = c.hasAccount;
    return B2NoChrome(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  bound ? Icons.verified_user : Icons.person_add_alt_1_outlined,
                  size: AppSize.iconMd,
                  color: bound ? AppTheme.primaryDark : AppTheme.textSecondary,
                ),
                const SizedBox(width: AppSpace.s6),
                const Text(
                  'app 身份',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: AppSpace.s4),
                  decoration: BoxDecoration(
                    color: bound ? AppTheme.primaryLight : AppTheme.bgWarm,
                    borderRadius: BorderRadius.circular(AppRadius.r12),
                  ),
                  child: Text(
                    bound ? '已注册' : '未注册',
                    style: TextStyle(
                      // ⚠ 必须显式给 color (AGENTS §5: 不给 = 真机白字)
                      color: bound ? AppTheme.primaryDark : AppTheme.textSecondary,
                      fontSize: AppTheme.fontXs,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            Text(
              bound
                  ? '她已经是 app 用户 —— 可以在 app 内直接邀请她 (沙龙 / 活动)'
                  : '还不是 app 用户。她注册 app 后, 把她的 6 位**邀请码**填进来即可绑定身份'
                      ' (手机号对不上也能绑; 若系统已按她的号自动建了空档案, 会自动并入这条)',
              style: const TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            if (!bound) ...[
              const SizedBox(height: AppSpace.s12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => _showBindAccountDialog(context, ref, c),
                  icon: const Icon(Icons.qr_code_2, size: AppSize.iconMd),
                  label: const Text(
                    '填邀请码绑定身份',
                    style: TextStyle(fontSize: AppTheme.fontSm),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 绑定弹层: 填她的 6 位邀请码 (身份识别码)
  Future<void> _showBindAccountDialog(
    BuildContext context,
    WidgetRef ref,
    Customer c,
  ) async {
    final codeCtrl = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('绑定 app 身份', style: TextStyle(fontSize: AppTheme.fontLg)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '让「${c.name}」打开 app → 我的 → 我的邀请码, 把 6 位码填到这里。',
              style: const TextStyle(
                fontSize: AppTheme.fontXs,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            TextField(
              controller: codeCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: '她的邀请码 *',
                helperText: '6 位字母数字 (不区分大小写)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('绑定', style: TextStyle(fontSize: AppTheme.fontMd)),
          ),
        ],
      ),
    );
    final code = codeCtrl.text.trim().toUpperCase();
    codeCtrl.dispose();
    if (submitted != true || !context.mounted) return;
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填对方的 6 位邀请码')),
      );
      return;
    }
    try {
      final res = await ref.read(customerServiceProvider).bindAccount(c.id, code);
      ref.invalidate(customerDetailProvider(c.id));
      ref.invalidate(customersProvider);
      ref.invalidate(customerTypeCountsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message.isEmpty ? '已绑定' : res.message)),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('绑定失败: ${_apiErrorText(e)}')),
      );
    }
  }

  /// 从 dio 异常里取服务端人话错误 (AGENTS: 不要只显示 DioException)
  String _apiErrorText(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] != null) return data['error'].toString();
    }
    return e.toString();
  }

  Widget _buildTypeCard(BuildContext context, WidgetRef ref, Customer c) {
    final isFranchisee = c.customerType == 'franchisee';
    return B2NoChrome(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_outlined,
                    size: AppSize.iconMd, color: AppTheme.primaryDark),
                const SizedBox(width: AppSpace.s6),
                const Text(
                  '客户类型',
                  style: TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                FranchiseChip(type: c.customerType),
              ],
            ),
            const SizedBox(height: AppSpace.s10),
            if (isFranchisee)
              const Text(
                '加盟客户：类型由加盟关系决定，不能在这里切换；\n要退出加盟请到加盟商详情页走「解除加盟」(需三方确认)',
                style: TextStyle(
                  fontSize: AppTheme.fontXs,
                  color: AppTheme.textSecondary,
                ),
              )
            else ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'normal', label: Text('普通')),
                  ButtonSegment(value: 'seed', label: Text('🌱 种子')),
                ],
                selected: {c.isSeed ? 'seed' : 'normal'},
                showSelectedIcon: false,
                onSelectionChanged: (v) =>
                    _setCustomerSeed(context, ref, c, v.first == 'seed'),
              ),
              const SizedBox(height: AppSpace.s6),
              const Text(
                '种子 = 还没体验过 / 刚加好友的潜在客户；选「种子」后可用列表顶部「🌱 种子」筛出来',
                style: TextStyle(
                  fontSize: AppTheme.fontXs,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Divider(height: AppSpace.s20),
              const Text(
                '要变成加盟商？走加盟落位（需三方确认）',
                style: TextStyle(
                  fontSize: AppTheme.fontXs,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpace.s8),
              // 发展客户为加盟商 (主人 2026-09-19: 入口迁到「客户类型」区块里)
              //   走三方确认的落位流程 (我 + 客户本人 + 目标上级), 通过后自动成为加盟商
              FilledButton.icon(
                onPressed: () =>
                    _promoteCustomerToFranchisee(context, ref, c),
                icon: const Icon(Icons.person_add_alt_1, size: AppSize.iconLg),
                label: const Text(
                  '发展为加盟商',
                  style: TextStyle(fontSize: AppTheme.fontMd),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHealthTags(Customer c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s12),
      decoration: BoxDecoration(
        color: AppTheme.primaryLight.withOpacity(0.25),
        borderRadius: BorderRadius.circular(AppRadius.r10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '健康标签',
            style: TextStyle(
              fontSize: AppTheme.fontSm,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpace.s8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: c.healthTags.map((t) => HealthTagChip(label: t)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: AppTheme.fontMd,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildEmptyHint(String title, String hint) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.s24),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.history, size: AppSize.fabSize, color: AppTheme.textSecondary),
            const SizedBox(height: AppSpace.s8),
            Text(title, style: const TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: AppSpace.s4),
            Text(hint, style: const TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  String _maskPhone(String phone) {
    if (phone.length == 11) {
      return '${phone.substring(0, 3)}****${phone.substring(7)}';
    }
    return phone;
  }
}

// ============================================
// 顶层方法 (被 CustomerDetailPage 用, 放本文件内)
// ============================================

/// 客户类型切换: 普通 ↔ 种子 (主人 2026-09-18: 详情页直接切, 不用进编辑表单)
Future<void> _setCustomerSeed(
  BuildContext context,
  WidgetRef ref,
  Customer c,
  bool seed,
) async {
  if (c.isSeed == seed) return;
  try {
    await ref.read(customerServiceProvider).update(c.id, {'isSeed': seed});
    ref.invalidate(customerDetailProvider(c.id));
    ref.invalidate(customersProvider);
    ref.invalidate(customerTypeCountsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          seed ? '已标记为 🌱 种子客户' : '已改为普通客户',
          style: const TextStyle(fontSize: AppTheme.fontMd),
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('修改失败: $e')),
    );
  }
}

Future<void> _promoteCustomerToFranchisee(
  BuildContext context,
  WidgetRef ref,
  Customer c,
) async {
  if (c.phone.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这位客户没手机号, 先补手机号再发展为加盟商')),
    );
    return;
  }
  FranchiseeTreeNode tree;
  try {
    tree = await ref
        .read(franchiseeServiceProvider)
        .getMyTree(depth: 12, mode: 'placement');
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('读取我的图谱失败: $e')),
    );
    return;
  }
  if (!context.mounted) return;
  final target = await showModalBottomSheet<PlacementTarget>(
    context: context,
    isScrollControlled: true,
    builder: (_) => PlacementTargetSheet(
      tree: tree,
      title: '发展「${c.name}」为加盟商',
    ),
  );
  if (target == null || !context.mounted) return;

  // ★ P6 (ADR-0016 D1, 主人 2026-09-22 拍): 落位按**邀请码**找账号 —— 先问她本人要码
  //   (她必须已注册 app; 没注册就让她先注册, 再回来发展)
  final codeCtrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('发展「${c.name}」为加盟商',
          style: const TextStyle(fontSize: AppTheme.fontLg)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '节点必须对应一个已注册账号 (她的邀请码 = 唯一识别码)。\n'
            '还没注册? 先请她注册, 再回来发展。',
            style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: AppSpace.s12),
          TextField(
            controller: codeCtrl,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: '她的邀请码 *',
              helperText: '6 位字母数字',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
        FilledButton(
          onPressed: () {
            final v = codeCtrl.text.trim().toUpperCase();
            Navigator.of(ctx).pop(RegExp(r'^[A-Z0-9]{6}$').hasMatch(v) ? v : null);
          },
          child: const Text('提交', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      ],
    ),
  );
  codeCtrl.dispose();
  if (code == null || !context.mounted) return;

  try {
    final req = await ref
        .read(franchiseeServiceProvider)
        .createPlacementRequest(
          targetParentId: target.parentId,
          side: target.side,
          newReferralCode: code,
          newName: c.name,
        );
    if (!context.mounted) return;
    ref.invalidate(placementToConfirmCountProvider);
    // 主人 2026-09-19: 系统管理员设置加盟免多方确认 → 直接生效
    final done = req.status == 'executed';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          done
              ? '已落位: 加到「${target.parentName}」的${PlacementRequest.sideLabel(target.side)} · 管理员设置, 立即生效'
              : '已提交: 加到「${target.parentName}」的${PlacementRequest.sideLabel(target.side)} · 等三方确认后生效',
          style: const TextStyle(fontSize: AppTheme.fontSm),
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('提交失败: $e')),
    );
  }
}
