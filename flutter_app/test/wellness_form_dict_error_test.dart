// ============================================
// 养生记录表单 — 字典加载失败的「错误态」回归测试 (B4, 2026-09-24)
//
// 根因: `_loadDict()` 之前没 try/catch, 抛异常时 `_dict` 永远 == null,
//   body 又是 `body: _dict == null ? LoadingState() : ...` —— 永远 LoadingState,
//   永远转圈, 没出口。
//
// 修法: `_loadDict()` 加 try/catch → 失败时 setState(_dictError = e);
//   body 看到 _dictError != null → 走 AppEmptyState (有重试按钮)。
//
// 验证: 字典服务抛异常时, 渲染出错误态 + 重试按钮, **不能**是无限转圈。
//   真主题渲染 (AGENTS §5 chip 白字教训)。
//
// ============================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/widgets/app_empty.dart';
import 'package:nuankebao/modules/wellness/screens/wellness_record_form_page.dart';

/// 假 HTTP adapter: 字典接口永远抛 DioException —— 模拟后端挂了
class _FailingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionTimeout,
      message: '字典服务挂了 (模拟)',
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 假 HTTP adapter: 第一次抛, 第二次返回空字典 —— 模拟「重试能恢复」
class _FirstFailsThenOkAdapter implements HttpClientAdapter {
  _FirstFailsThenOkAdapter();
  int dictCalls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // 只计数字典接口 (/dictionaries/all); 其他接口 (wellness list, customer) 不计
    if (options.path.contains('dictionar')) {
      dictCalls++;
      if (dictCalls == 1) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
          message: '第一次失败 (模拟)',
        );
      }
      final payload = {
        'bodyParts': <Map<String, dynamic>>[],
        'serviceItems': <Map<String, dynamic>>[],
        'products': <Map<String, dynamic>>[],
      };
      return ResponseBody.fromString(
        jsonEncode(payload),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    // 其他接口: 返回空 (顾客详情 / wellness history 等), 表单只需要字典
    return ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  testWidgets('字典加载失败 → 渲染错误态 (无 LoadingState 死循环)', (tester) async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
      ..httpClientAdapter = _FailingAdapter();

    await tester.pumpWidget(ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: WellnessRecordFormPage(customerId: '1')),
    ));

    // 等异步 _loadDict() 完成 (它会 try/catch + setState)
    await tester.pumpAndSettle();

    // 关键断言 1: 不是 LoadingState (无限转圈的根因)
    expect(find.byType(LoadingState), findsNothing,
        reason: '字典加载失败时, **不能**继续渲染 LoadingState (= 死循环转圈)');
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '顶层不能有 CircularProgressIndicator (会一直被渲染)');

    // 关键断言 2: 错误态出现 (AppEmptyState + 「字典没加载出来」文案)
    expect(find.byType(AppEmptyState), findsOneWidget);
    expect(find.text('字典没加载出来'), findsOneWidget);
    // ⚠ hint 「先重试一下」含「重试」+ 按钮「重试」; find.text 是子串匹配
    // → FilledButton.icon 包出来的是 _FilledButtonWithIconChild (FilledButton 子类),
    //   find.widgetWithText(FilledButton) 找不到内部 child → 用 predicate 找
    //   「data 精确等于『重试』」的 Text (hint 是「先重试一下」, data 不同)
    expect(
      find.byWidgetPredicate((w) => w is Text && w.data == '重试'),
      findsOneWidget,
      reason: '错误态必须有「重试」按钮 (原则 8: 必须告诉下一步做什么) — hint 是「先重试一下」, 按钮是「重试」',
    );

    // 关键断言 3: 表单内容不出现 (避免「半加载」假象)
    expect(find.text('服务项目 (单选) *'), findsNothing);
    expect(find.text('身体部位 (可多选)'), findsNothing);
  });

  testWidgets('点「重试」会再次调用 _loadDict()', (tester) async {
    final adapter = _FirstFailsThenOkAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
      ..httpClientAdapter = adapter;

    await tester.pumpWidget(ProviderScope(
      overrides: [dioProvider.overrideWithValue(dio)],
      child: const MaterialApp(home: WellnessRecordFormPage(customerId: '1')),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AppEmptyState), findsOneWidget,
        reason: '第一次失败 → 错误态');
    expect(adapter.dictCalls, 1, reason: 'initState 时 _loadDict 调了一次');

    // 点重试 → _loadDict 再来一次 → 第二次成功 → 进入表单
    await tester.tap(find.byWidgetPredicate(
      (w) => w is Text && w.data == '重试',
    ));
    await tester.pumpAndSettle();

    expect(adapter.dictCalls, 2, reason: '重试后 _loadDict 被再次触发');
    expect(find.byType(AppEmptyState), findsNothing,
        reason: '重试成功后不再显示错误态');
    expect(find.text('服务项目 (单选) *'), findsOneWidget,
        reason: '表单正常渲染 (空字典也是合法的「加载完成」)');
  });
}