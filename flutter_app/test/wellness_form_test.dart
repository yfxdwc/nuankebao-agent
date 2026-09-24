// ============================================
// 养生记录表单 — 「服务项目」下拉 (主人 2026-09-18 拍) 回归测试
//
// 拍板内容:
//   1) 服务项目 (单选) 置顶 — 在「身体部位 (可多选)」上面
//   2) 服务项目从 ChoiceChip 改成下拉选择框
//   3) 默认选中「碧波庭-脉动负压提拉按摩」(字典里有 → 自动选中; 没有 → 不硬编码)
//
// 跑: cd flutter_app && flutter test test/wellness_form_test.dart
// ============================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nuankebao/core/models/dictionaries.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/modules/wellness/screens/wellness_record_form_page.dart';

const _defaultServiceName = '碧波庭-脉动负压提拉按摩';

/// 假 HTTP adapter: 所有请求都返回同一份字典 JSON (不打网络)
class _FakeDictAdapter implements HttpClientAdapter {
  _FakeDictAdapter(this.payload);
  final Map<String, dynamic> payload;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(payload),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Dictionaries _dict({required bool withDefault}) => Dictionaries(
      bodyParts: const [
        BodyPart(id: '1', name: '肩颈'),
        BodyPart(id: '2', name: '腰部'),
      ],
      serviceItems: [
        const ServiceItem(id: '1', name: '肩颈经络理疗'),
        const ServiceItem(id: '2', name: '拔罐'),
        if (withDefault) const ServiceItem(id: '9', name: _defaultServiceName),
      ],
      products: const [],
    );

Future<void> _pumpForm(WidgetTester tester, Dictionaries dict) async {
  // 草稿功能会读 shared_preferences → 测试里给个空 mock (否则平台通道挂起)
  SharedPreferences.setMockInitialValues({});
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _FakeDictAdapter(dict.toJson());

  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: const MaterialApp(home: WellnessRecordFormPage(customerId: '1')),
  ));
  await tester.pumpAndSettle();
}

/// 下拉框当前选中值 (DropdownButtonFormField 内部就是一个 DropdownButton)
/// 当前选中的服务项目名 (2026-09-24: 下拉框 → 弹层+搜索; 选中值显示在 field 里)
String? _selectedServiceName(WidgetTester tester) {
  final t = tester.widget<Text>(
      find.byKey(const ValueKey('serviceItemName')));
  return (t.data ?? '').isEmpty ? null : t.data;
}

void main() {
  testWidgets('服务项目置顶 (在身体部位上面) + 用选择弹层', (tester) async {
    await _pumpForm(tester, _dict(withDefault: true));

    // 选择字段 (不再是 ChoiceChip / 不是下拉框: 2026-09-24 改弹层+搜索)
    expect(find.byKey(const ValueKey('serviceItemField')), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);

    // 置顶: 服务项目 label 在 身体部位 label 上面
    final serviceY = tester.getTopLeft(find.text('服务项目 (单选) *')).dy;
    final bodyY = tester.getTopLeft(find.text('身体部位 (可多选)')).dy;
    expect(serviceY, lessThan(bodyY));
  });

  testWidgets('默认选中「碧波庭-脉动负压提拉按摩」', (tester) async {
    await _pumpForm(tester, _dict(withDefault: true));

    expect(_selectedServiceName(tester), _defaultServiceName);
  });

  testWidgets('字典里没有该项目 → 不硬编码, 显示 hint 待用户选', (tester) async {
    await _pumpForm(tester, _dict(withDefault: false));

    expect(_selectedServiceName(tester), isNull);
    expect(find.text('请选择服务项目'), findsOneWidget);
  });

  testWidgets('默认项可改: 打开选择弹层选「拔罐」', (tester) async {
    await _pumpForm(tester, _dict(withDefault: true));

    await tester.tap(find.byKey(const ValueKey('serviceItemField')));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(3),
        reason: '弹层里应有 3 个服务项目 (含默认项)');
    await tester.tap(find.text('拔罐').last);
    await tester.pumpAndSettle();

    expect(_selectedServiceName(tester), '拔罐');
  });
}
