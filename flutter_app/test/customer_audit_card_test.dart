// ============================================
// 客户档案「最近改动」卡 (管理 Tab, 2026-09-24 建议 #2)
//
// 守什么:
//   ① INSERT / UPDATE / DELETE → 人话 (建档 / 修改了 X、Y / 归档 (删除))
//   ② 列名 → 中文标签 (name→姓名, birthday_remind_days→生日提醒 …)
//   ③ `updated_at` / `created_at` 是噪音列, 不参与"修改了什么"展示
//      (只有它们变 → 显示"保存")
//   ④ 没有操作人 → 显示「系统」; 空数据 → 「还没有改动记录」; 报错 → 重试按钮
//
// 跑: cd flutter_app && flutter test test/customer_audit_card_test.dart
// ============================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/models/audit_entry.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/modules/customer/widgets/audit_trail_card.dart';

class _FakeCustomerService extends CustomerService {
  _FakeCustomerService(this.entries, {this.error}) : super(Dio());
  final List<AuditEntry> entries;
  final Object? error;

  @override
  Future<List<AuditEntry>> audit(String customerId, {int limit = 20}) async {
    if (error != null) throw error!;
    return entries;
  }
}

AuditEntry _entry({
  String id = '1',
  String operation = 'UPDATE',
  List<String> columns = const [],
  String? actor = '演示-张三',
  DateTime? at,
}) =>
    AuditEntry(
      id: id,
      operation: operation,
      changedColumns: columns,
      actorName: actor,
      createdAt: at ?? DateTime(2026, 9, 24, 10, 30),
    );

Future<void> _pump(WidgetTester tester, _FakeCustomerService svc) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [customerServiceProvider.overrideWithValue(svc)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(
        body: SingleChildScrollView(child: CustomerAuditCard(customerId: '798')),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('① INSERT/UPDATE/DELETE → 建档 / 修改了 X、Y / 归档', (tester) async {
    await _pump(
      tester,
      _FakeCustomerService([
        _entry(
            id: '3',
            operation: 'UPDATE',
            columns: ['name', 'birthday_remind_days', 'updated_at'],
            at: DateTime(2026, 9, 24, 12, 0)),
        _entry(id: '2', operation: 'INSERT', columns: ['name', 'phone_encrypted']),
        _entry(id: '1', operation: 'DELETE', actor: null),
      ]),
    );

    expect(find.textContaining('建档'), findsOneWidget);
    expect(find.textContaining('修改了 姓名、生日提醒'), findsOneWidget,
        reason: '列名要翻成中文; updated_at 是噪音列不参与展示');
    expect(find.textContaining('归档 (删除)'), findsOneWidget);
    expect(find.textContaining('系统'), findsOneWidget,
        reason: '没有操作人 → 显示「系统」');
  });

  testWidgets('② 只有 updated_at 变化 → 显示「保存」(不显示噪音列名)', (tester) async {
    await _pump(
      tester,
      _FakeCustomerService([
        _entry(columns: ['updated_at', 'created_at']),
      ]),
    );

    expect(find.textContaining('保存'), findsOneWidget);
    expect(find.textContaining('updated_at'), findsNothing,
        reason: '列名不该以英文原文露出');
  });

  testWidgets('③ 空数据 → 「还没有改动记录」', (tester) async {
    await _pump(tester, _FakeCustomerService(const []));
    expect(find.text('还没有改动记录'), findsOneWidget);
  });

  testWidgets('④ 报错 → 显示错误 + 重试按钮 (不崩)', (tester) async {
    await _pump(tester, _FakeCustomerService(const [], error: Exception('boom')));
    expect(find.textContaining('加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });
}
