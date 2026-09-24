// ============================================
// 互动详情底部弹层 测试 (2026-09-25 第 5 项)
//
// 守护:
//   ① 查看态: 类型 + 时间 + 内容全文渲染
//   ② 编辑保存: 调用 update(参数断言 type/summary); 成功后 invalidate +
//       pop + SnackBar「已更新」; 失败 → SnackBar「保存失败: $e」
//   ③ 删除: 二次确认框; 确认后调 delete; 取消 = 不动
//
// 跑: cd flutter_app && flutter test test/interaction_detail_sheet_test.dart
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/models/follow_up.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart' show AppTheme;
import 'package:nuankebao/core/theme/tokens.g.dart' show AppThemes;
import 'package:nuankebao/modules/follow_up/widgets/interaction_detail_sheet.dart';

// ---------- 假 InteractionService ----------

class _FakeInteractionService extends InteractionService {
  _FakeInteractionService(this._initial) : super(Dio());

  final Interaction _initial;
  final List<({String id, Map<String, dynamic> data})> updateCalls = [];
  final List<String> deleteCalls = [];

  /// 测试可注入: 抛错覆盖默认 success 路径
  Exception? updateToThrow;
  Exception? deleteToThrow;

  @override
  Future<List<Interaction>> list({String? customerId}) async => [_initial];

  @override
  Future<Interaction> update(String id, Map<String, dynamic> data) async {
    updateCalls.add((id: id, data: Map<String, dynamic>.from(data)));
    if (updateToThrow != null) throw updateToThrow!;
    return _initial;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls.add(id);
    if (deleteToThrow != null) throw deleteToThrow!;
  }
}

final _seedInteraction = Interaction(
  id: 'i-42',
  customerId: 'c1',
  type: 'phone',
  summary: '约下周三到店',
  createdBy: 'me',
  createdAt: DateTime(2026, 9, 22, 14, 30),
);

Future<({_FakeInteractionService svc, ProviderContainer container})>
    _pumpAndOpen(WidgetTester tester) async {
  final svc = _FakeInteractionService(_seedInteraction);
  final container = ProviderContainer(
    overrides: <Override>[
      interactionServiceProvider.overrideWithValue(svc),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light(AppThemes.sage),
        home: Consumer(
          builder: (innerCtx, ref, _) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showInteractionDetailSheet(
                  innerCtx,
                  ref,
                  interaction: _seedInteraction,
                  customerId: 'c1',
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
  return (svc: svc, container: container);
}

void main() {
  testWidgets('① 查看态渲染: 类型 + 时间 + 内容全文', (tester) async {
    await _pumpAndOpen(tester);

    // 弹层头部 + 类型 label
    expect(find.text('联系记录'), findsOneWidget);
    expect(find.text('电话'), findsOneWidget);

    // 时间 (本地时区; 测试期是 CST, 09-22 14:30 → 2026-09-22 14:30)
    expect(find.text('2026-09-22 14:30'), findsOneWidget);

    // 内容全文
    expect(find.text('约下周三到店'), findsOneWidget);

    // 「编辑」+「删除」两个操作入口 (查看态)
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('② 编辑保存: 调 update(type, summary) + invalidate + pop + SnackBar「已更新」',
      (tester) async {
    final fake = await _pumpAndOpen(tester);

    // 进入编辑态
    await tester.tap(find.byKey(const ValueKey('interactionSheetEdit')));
    await tester.pumpAndSettle();

    // 编辑态头部变了
    expect(find.text('编辑联系记录'), findsOneWidget);

    // 默认 type=phone 已选; 切到「微信」
    await tester.tap(find.widgetWithText(ChoiceChip, '微信'));
    await tester.pumpAndSettle();

    // 修改 summary
    await tester.enterText(
      find.byKey(const ValueKey('editSummaryField')),
      '新内容',
    );
    await tester.pumpAndSettle();

    // 保存
    await tester.tap(find.byKey(const ValueKey('editSaveBtn')));
    await tester.pumpAndSettle();

    // update 被调用一次, id 正确
    expect(fake.svc.updateCalls, hasLength(1));
    expect(fake.svc.updateCalls.single.id, 'i-42');
    expect(fake.svc.updateCalls.single.data['type'], 'wechat');
    expect(fake.svc.updateCalls.single.data['summary'], '新内容');

    // 弹层已关 + SnackBar「已更新」
    expect(find.text('联系记录'), findsNothing);
    expect(find.text('已更新'), findsOneWidget);
  });

  testWidgets('③ 编辑保存失败 → SnackBar 包含「保存失败」+ 弹层仍在',
      (tester) async {
    final fake = await _pumpAndOpen(tester);
    final svc = fake.svc;
    svc.updateToThrow = Exception('boom');

    await tester.tap(find.byKey(const ValueKey('interactionSheetEdit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('editSaveBtn')));
    await tester.pumpAndSettle();

    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    // 弹层仍在 (没 pop)
    expect(find.text('编辑联系记录'), findsOneWidget);
  });

  testWidgets('④ 删除: 二次确认框 → 确认后调 delete + SnackBar「已删除」',
      (tester) async {
    final fake = await _pumpAndOpen(tester);

    // 点「删除」
    await tester.tap(find.byKey(const ValueKey('interactionSheetDelete')));
    await tester.pumpAndSettle();

    // 二次确认对话框
    expect(find.text('删除这条联系记录?'), findsOneWidget);
    expect(find.byKey(const ValueKey('deleteDialogCancel')), findsOneWidget);
    expect(find.byKey(const ValueKey('deleteDialogConfirm')), findsOneWidget);

    // 确认
    await tester.tap(find.byKey(const ValueKey('deleteDialogConfirm')));
    await tester.pumpAndSettle();

    // delete 被调用 + 弹层关 + SnackBar
    expect(fake.svc.deleteCalls, ['i-42']);
    expect(find.text('联系记录'), findsNothing);
    expect(find.text('已删除'), findsOneWidget);
  });

  testWidgets('⑤ 删除取消 → delete **未**被调用', (tester) async {
    final fake = await _pumpAndOpen(tester);

    await tester.tap(find.byKey(const ValueKey('interactionSheetDelete')));
    await tester.pumpAndSettle();

    // 取消
    await tester.tap(find.byKey(const ValueKey('deleteDialogCancel')));
    await tester.pumpAndSettle();

    expect(fake.svc.deleteCalls, isEmpty);
    // 弹层还在
    expect(find.text('联系记录'), findsOneWidget);
  });
}