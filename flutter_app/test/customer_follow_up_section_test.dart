// ============================================
// CustomerFollowUpSection —— 跟进任务 tile 渲染测试 (2026-09-24)
//
// 主人反馈: 「点击跟进后, 直接创建了当天的跟进任务, 并且创建时就是已过期状态。
//   当前日期的待办状态应该还没过期。」
//
// 验证:
//   · dueAt=昨天 → 文案「MM-dd · 已过期」
//   · dueAt=今天 → 文案「今天到期」, 且**不**含「已过期」字样
//   · dueAt=明天 → 文案「明天到期」
//
// 跑: cd flutter_app && flutter test test/customer_follow_up_section_test.dart
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/follow_up.dart';
import 'package:nuankebao/core/widgets/b2_no_chrome.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart' show AppTheme;
import 'package:nuankebao/core/theme/tokens.g.dart' show AppThemes;
import 'package:nuankebao/modules/customer/widgets/customer_activity_cards.dart';

/// Fake FollowUpService —— list 返回注入的 tasks, 其它 throw。
class _FakeFollowUpService extends FollowUpService {
  _FakeFollowUpService(this._fakeList) : super(Dio());

  final List<FollowUpTask> _fakeList;
  int listCalls = 0;

  @override
  Future<List<FollowUpTask>> list({
    String? customerId,
    String status = 'pending',
  }) async {
    listCalls++;
    return _fakeList;
  }
}

Widget _wrap({required Widget child, required FollowUpService fake}) {
  // 不挂全 page (避免副作用), 只挂 section widget + 假 service + 真主题。
  return ProviderScope(
    overrides: [
      followUpServiceProvider.overrideWithValue(fake),
    ],
    child: MaterialApp(
      theme: AppTheme.light(AppThemes.sage),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(children: [child]),
        ),
      ),
    ),
  );
}

/// 构造一个本地时区的 DateTime (年/月/日/时/分) —— 不带 Z, 默认 toLocal 视角。
DateTime _local(int y, int m, int d, [int h = 9, int min = 0]) =>
    DateTime(y, m, d, h, min);

/// 相对「今天」的日期 (2026-09-26 修): 旧 fixture 把「今天」写死成 2026-09-24,
/// 而组件 (`customer_activity_cards.dart`) 判「今天到期 / 已过期」用的是**真实 now** →
/// 日期一漂移，标签全变「已过期」→ 用例假失败。
DateTime _day(int dayOffset, [int h = 9, int min = 0]) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + dayOffset, h, min);
}

/// 泵 + 等到 ConsumerStatefulWidget 走完首帧。
Future<void> _pumpUntilSettled(WidgetTester tester) async {
  await tester.pump();
  // runAsync 让 FakeTime 推真实时间, 等 FutureProvider resolve + frame rebuild。
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  });
}

void main() {
  testWidgets(
    'dueAt=昨天 (本地 23:59, now=今天 10:00) → 显示「MM-dd · 已过期」',
    (tester) async {
      // 锚 now = 今天 10:00; dueAt = 昨天 23:59 → 应该判「已过期」
      final now = _local(2026, 9, 24, 10, 0);
      // 用相对 now 的「昨天」+「今天」, 避免测试在不同年份漂移 (用 2026 锚)。
      final yesterday = now.subtract(const Duration(days: 1));
      final dueAt = DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59);
      final fake = _FakeFollowUpService([
        FollowUpTask(
          id: 't-overdue',
          customerId: 'c1',
          dueAt: dueAt,
          reason: '回访昨日到店',
          status: 'pending',
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(_wrap(
        child: const CustomerFollowUpSection(customerId: 'c1'),
        fake: fake,
      ));
      await _pumpUntilSettled(tester);

      expect(find.textContaining('已过期'), findsOneWidget,
          reason: '昨天任务应显示「已过期」');
      expect(find.textContaining('回访昨日到店'), findsOneWidget);
    },
  );

  testWidgets(
    'dueAt=今天 (now=同一天晚些时候) → 显示「今天到期」, 且**不**含「已过期」',
    (tester) async {
      // dueAt = 今天 08:00 (相对今天) → 今天到期
      final now = DateTime.now();
      final dueAt = _day(0, 8);
      final fake = _FakeFollowUpService([
        FollowUpTask(
          id: 't-today',
          customerId: 'c1',
          dueAt: dueAt,
          reason: '问她腰好点没',
          status: 'pending',
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(_wrap(
        child: const CustomerFollowUpSection(customerId: 'c1'),
        fake: fake,
      ));
      await _pumpUntilSettled(tester);

      expect(find.text('今天到期'), findsOneWidget,
          reason: '今天到期 ≠ 已过期 (核心诉求)');
      expect(find.textContaining('已过期'), findsNothing,
          reason: '「今天到期」绝对不能同时显示「已过期」');
      expect(find.textContaining('问她腰好点没'), findsOneWidget);
    },
  );

  testWidgets(
    'dueAt=明天 → 显示「明天到期」',
    (tester) async {
      final now = DateTime.now();
      final dueAt = _day(1, 9);
      final fake = _FakeFollowUpService([
        FollowUpTask(
          id: 't-tmr',
          customerId: 'c1',
          dueAt: dueAt,
          reason: '约下次到店',
          status: 'pending',
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(_wrap(
        child: const CustomerFollowUpSection(customerId: 'c1'),
        fake: fake,
      ));
      await _pumpUntilSettled(tester);

      expect(find.text('明天到期'), findsOneWidget);
      expect(find.textContaining('已过期'), findsNothing);
      expect(find.textContaining('约下次到店'), findsOneWidget);
    },
  );

  testWidgets(
    'dueAt=更远 (8 天后) → 显示「MM-dd 到期」 (无「已过期」无「今天到期」)',
    (tester) async {
      final now = _local(2026, 9, 24, 9, 0);
      final dueAt = now.add(const Duration(days: 8));
      final fake = _FakeFollowUpService([
        FollowUpTask(
          id: 't-far',
          customerId: 'c1',
          dueAt: dueAt,
          reason: '下月再联系',
          status: 'pending',
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(_wrap(
        child: const CustomerFollowUpSection(customerId: 'c1'),
        fake: fake,
      ));
      await _pumpUntilSettled(tester);

      expect(find.textContaining('到期'), findsOneWidget);
      expect(find.textContaining('已过期'), findsNothing);
      expect(find.text('今天到期'), findsNothing);
      expect(find.text('明天到期'), findsNothing);
    },
  );

  testWidgets(
    '列表同时含「逾期」和「今天」 → 各自走不同分支 (回归: 不会再都被标「已过期」)',
    (tester) async {
      final now = DateTime.now();
      final dueOverdue = _day(-1, 23, 59);
      final dueToday = _day(0, 8);
      final fake = _FakeFollowUpService([
        FollowUpTask(
          id: 't1',
          customerId: 'c1',
          dueAt: dueOverdue,
          reason: '逾期一条',
          status: 'pending',
          createdAt: now,
        ),
        FollowUpTask(
          id: 't2',
          customerId: 'c1',
          dueAt: dueToday,
          reason: '今天一条',
          status: 'pending',
          createdAt: now,
        ),
      ]);

      await tester.pumpWidget(_wrap(
        child: const CustomerFollowUpSection(customerId: 'c1'),
        fake: fake,
      ));
      await _pumpUntilSettled(tester);

      expect(find.textContaining('已过期'), findsOneWidget,
          reason: '逾期那条必须显示「已过期」');
      expect(find.text('今天到期'), findsOneWidget,
          reason: '今天那条必须显示「今天到期」');
      // 找两个 reason 都出现 (整体渲染没崩)
      expect(find.textContaining('逾期一条'), findsOneWidget);
      expect(find.textContaining('今天一条'), findsOneWidget);
    },
  );

  // ============================================
  // ⑨ 折叠态 (2026-09-24 主人诉求: 「跟进任务」卡随上滑收起, 但不上高亮色)
  //
  // 主人原话: 「『跟进任务』卡片也像『现在该做』卡片一样随上滑收起,
  //   但不需要高亮显示。」
  //
  // 守什么 (widget 级):
  //   · collapsed=true + 有任务 → 只渲染一行 header + 右侧 expand_more
  //     (理由 / 完成按钮 全部不渲染); 「+ 新建」按钮**仍**可见 (折叠态
  //     也能快速建任务, 不必先展开)
  //   · 卡片底色 == tokens.surfaceCard (白) —— **明确不上**任何警示色
  //     (跟 L0「现在该做」的 warning 琥珀**刻意**区分; 主人原话
  //     「不需要高亮显示」)。反向断言 isNot(warningSurface) +
  //     isNot(primaryLight) 防有人手滑照抄 L0 警示色
  //   · 点 expand_more → 回调被调 (详情页收到后切回展开)
  //   · collapsed=true + 无任务 → 「没有待办跟进」可见, **不**出图标
  //     (没东西可展开, 出图标 = 误导, 同根 §5「贴告示 ≠ 修复」)
  //
  // 页面级「上滑后跟进卡仍在树上 + 任务行收起 + 滚回顶部恢复」是
  // customer_detail_tabs_test.dart 的事, 本文件只守 widget 级渲染。
  // ============================================
  group("⑨ 折叠态 (2026-09-24 主人诉求, 跟 L0 共用折叠机)", () {
    testWidgets(
      'collapsed=true + 有任务 → 只渲染一行 header (含「+ 新建」 + expand_more), 任务 reason 不可见',
      (tester) async {
        final fake = _FakeFollowUpService([
          FollowUpTask(
            id: 't1',
            customerId: 'c1',
            dueAt: _local(2026, 9, 25, 9, 0),
            reason: '折叠后这条 reason 不可见',
            status: 'pending',
            createdAt: _local(2026, 9, 24, 10, 0),
          ),
        ]);
        await tester.pumpWidget(_wrap(
          child: CustomerFollowUpSection(
            customerId: 'c1',
            collapsed: true,
            onToggleCollapsed: () {},
          ),
          fake: fake,
        ));
        await _pumpUntilSettled(tester);

        // header 一行保留
        expect(find.text('跟进任务'), findsOneWidget);
        // 折叠态下「+ 新建」按钮**仍**可见 (避免用户必须先展开→建→折叠)
        expect(find.text('新建'), findsOneWidget,
            reason: '折叠态也要让销售能快速建任务, 「+ 新建」按钮保留');
        // 右上角展开图标出现
        expect(find.byIcon(Icons.expand_more), findsOneWidget,
            reason: 'collapsed=true + 有任务 → 右侧出 expand_more');

        // 任务 tile 全部收起: reason / 完成按钮 不可见
        expect(find.textContaining('折叠后这条 reason 不可见'), findsNothing,
            reason: '折叠态不该渲染任务 reason');
        expect(find.byIcon(Icons.check_circle_outline), findsNothing,
            reason: '折叠态不该渲染「标记完成」按钮');
        // 「今天/明天/已过期」/「到期」这些 task 副文也不该出现
        expect(find.textContaining('到期'), findsNothing);
      },
    );

    testWidgets(
      'collapsed=true + 有任务 → 卡片底色是 surfaceCard (白); 反向断言不是警示色',
      (tester) async {
        final fake = _FakeFollowUpService([
          FollowUpTask(
            id: 't1',
            customerId: 'c1',
            dueAt: _local(2026, 9, 25, 9, 0),
            reason: '回归测试',
            status: 'pending',
            createdAt: _local(2026, 9, 24, 10, 0),
          ),
        ]);
        await tester.pumpWidget(_wrap(
          child: CustomerFollowUpSection(
            customerId: 'c1',
            collapsed: true,
            onToggleCollapsed: () {},
          ),
          fake: fake,
        ));
        await _pumpUntilSettled(tester);

        final tokens = AppThemes.resolve(null);

        // ⚠ 锁卡片 = CustomerFollowUpSection.cardKey (跟详情页页面级测试共用,
        //   「不能随上滑全部不见了」验收就靠它)
        final cardFinder =
            find.byKey(CustomerFollowUpSection.cardKey);
        expect(cardFinder, findsOneWidget,
            reason: '卡片必须挂 followUpCard key (详情页验收契约)');

        // B2NoChrome 的 BoxDecoration: 折叠态仍是 surfaceCard (白)
        final b2 = tester.widget<B2NoChrome>(cardFinder);
        final b2Deco = b2.color ?? tokens.surfaceCard;
        // B2NoChrome 默认 color 是 context.tokens.surfaceCard, 不挂
        // BoxDecoration; 折叠态**不上**警示/高亮色。
        // 反向断言: 折叠态底色**不能**是警示色 (主人明确否过),
        // 也不能是品牌绿 (语义错位, 同 L0 「现在该做」折叠态的警示语义反向)。
        expect(b2Deco, isNot(tokens.warningSurface),
            reason: '折叠态不能用 warningSurface (主人原话「不需要高亮显示」)');
        expect(b2Deco, isNot(tokens.warning),
            reason: '折叠态不能用 warning (深琥珀)');
        expect(b2Deco, isNot(tokens.primaryLight),
            reason: '折叠态不能用品牌绿 (语义错位: 不是正向完成态)');

        // 顺带兜底正向断言: 折叠态底色**应该**就是 surfaceCard (白)
        expect(b2Deco, tokens.surfaceCard,
            reason: '折叠态卡片底色 = surfaceCard (白), 跟展开态视觉一致');
      },
    );

    testWidgets(
      '点 expand_more → onToggleCollapsed 回调被调',
      (tester) async {
        var toggled = 0;
        final fake = _FakeFollowUpService([
          FollowUpTask(
            id: 't1',
            customerId: 'c1',
            dueAt: _local(2026, 9, 25, 9, 0),
            reason: '点击展开',
            status: 'pending',
            createdAt: _local(2026, 9, 24, 10, 0),
          ),
        ]);
        await tester.pumpWidget(_wrap(
          child: CustomerFollowUpSection(
            customerId: 'c1',
            collapsed: true,
            onToggleCollapsed: () => toggled++,
          ),
          fake: fake,
        ));
        await _pumpUntilSettled(tester);

        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.pumpAndSettle();

        expect(toggled, 1,
            reason: '点 expand_more → onToggleCollapsed 应被详情页拿到 (本测试用计数器验证)');
      },
    );

    testWidgets(
      'collapsed=true + 无任务 → 「没有待办跟进」可见, 无 expand_more 图标',
      (tester) async {
        final fake = _FakeFollowUpService([]);
        await tester.pumpWidget(_wrap(
          child: CustomerFollowUpSection(
            customerId: 'c1',
            collapsed: true,
            onToggleCollapsed: () {},
          ),
          fake: fake,
        ));
        await _pumpUntilSettled(tester);

        // 「没有待办跟进」仍可见 (跟展开态空态一致)
        expect(find.text('没有待办跟进'), findsOneWidget);

        // ⚠ 没东西可展开 → **不**出图标 (同根 §5「贴告示 ≠ 修复」:
        //   出图标让人以为能点开看什么, 结果啥也没有)
        expect(find.byIcon(Icons.expand_more), findsNothing,
            reason: '无任务时折叠态不该出现展开图标 (没东西可展开)');
        // 顺带兜底: 「+ 新建」按钮仍可见 (折叠态空态也能建任务)
        expect(find.text('新建'), findsOneWidget);
      },
    );

    testWidgets(
      'collapsed=false → 现有展开态渲染不受影响 (回归保护)',
      (tester) async {
        final fake = _FakeFollowUpService([
          FollowUpTask(
            id: 't1',
            customerId: 'c1',
            dueAt: _local(2026, 9, 25, 9, 0),
            reason: '展开态 reason 必须可见',
            status: 'pending',
            createdAt: _local(2026, 9, 24, 10, 0),
          ),
        ]);
        await tester.pumpWidget(_wrap(
          child: const CustomerFollowUpSection(customerId: 'c1'),
          fake: fake,
        ));
        await _pumpUntilSettled(tester);

        // 展开态: 任务 reason 可见, **不**出 expand_more (没人传 collapsed)
        expect(find.textContaining('展开态 reason 必须可见'), findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsNothing,
            reason: '展开态**不**该出现展开图标');
      },
    );

    testWidgets(
      '「+ 新建」固定在卡片右上角 (最右控件 + 贴右边) —— 折叠/展开两态都成立',
      (tester) async {
        // 主人 2026-09-24: 「'+新建'按键整体靠右，固定到卡片的右上角」
        //   锁两件事:
        //     ① 它必须是**最右侧控件** —— 展开箭头 (⌄) 不许抢最右位
        //        (2026-09-24 调序: 箭头已移到按钮**左侧**)
        //     ② 它要**贴右边缘** —— 距卡片右缘 ≤ 24px (不是飘在 header 中间)
        final tasks = [
          FollowUpTask(
            id: 't1',
            customerId: 'c1',
            dueAt: _local(2026, 9, 25, 9, 0),
            reason: '贴角验证',
            status: 'pending',
            createdAt: _local(2026, 9, 24, 10, 0),
          ),
        ];

        Future<void> checkAtCorner({required bool collapsed}) async {
          final fake = _FakeFollowUpService(tasks);
          await tester.pumpWidget(_wrap(
            child: CustomerFollowUpSection(
              customerId: 'c1',
              collapsed: collapsed,
              onToggleCollapsed: () {},
            ),
            fake: fake,
          ));
          await _pumpUntilSettled(tester);

          // 按 widget 里的测试契约 key 抓 (TextButton.icon 是私有子类,
          //   find.byType(TextButton) 抓不到)
          final btn = find.byKey(const ValueKey('followUpNewButton'));
          expect(btn, findsOneWidget,
              reason: 'collapsed=$collapsed 时「+ 新建」必须可见');
          final btnRect = tester.getRect(btn);
          final cardRect =
              tester.getRect(find.byKey(CustomerFollowUpSection.cardKey));

          // ② 贴角 (折叠态实际 ~4px 内边距, 展开态 ~16px)
          expect(cardRect.right - btnRect.right, lessThanOrEqualTo(24.0),
              reason:
                  'collapsed=$collapsed: 「+ 新建」要贴卡片右上角 (距右缘 ≤ 24px)');

          // ① 最右控件: 若折叠态有展开箭头, 它必须在按钮**左侧**
          final chev = find.byIcon(Icons.expand_more);
          if (chev.evaluate().isNotEmpty) {
            expect(tester.getRect(chev).right,
                lessThanOrEqualTo(btnRect.left + 0.5),
                reason: '展开箭头不能占最右位 (主人要求「+ 新建」在卡片右上角)');
          }
        }

        await checkAtCorner(collapsed: false);
        await checkAtCorner(collapsed: true);
      },
    );

    testWidgets(
      '「+ 新建」是实心按钮 (背景显式, 主人 2026-09-24 「按键化, 按键背景显式」)',
      (tester) async {
        final fake = _FakeFollowUpService([
          FollowUpTask(
            id: 't1',
            customerId: 'c1',
            dueAt: _local(2026, 9, 25, 9, 0),
            reason: '按键化验证',
            status: 'pending',
            createdAt: _local(2026, 9, 24, 10, 0),
          ),
        ]);
        await tester.pumpWidget(_wrap(
          child: const CustomerFollowUpSection(customerId: 'c1'),
          fake: fake,
        ));
        await _pumpUntilSettled(tester);

        final btn = tester.widget<FilledButton>(
            find.byKey(const ValueKey('followUpNewButton')));
        // 显式背景: style 里必须给 backgroundColor (浅主色), 不是靠主题默认或透明
        final bg = btn.style?.backgroundColor?.resolve(<WidgetState>{});
        expect(bg, AppTheme.primaryLight,
            reason: '「+ 新建」要有显式按键背景 (浅主色底), 不能再是无背景文字链');
        // 前景色也要显式 (深主色), 保证浅底上可读
        final fg = btn.style?.foregroundColor?.resolve(<WidgetState>{});
        expect(fg, AppTheme.primaryDark,
            reason: '浅主色底上必须配深主色字 (对比度)');
      },
    );
  });
}
