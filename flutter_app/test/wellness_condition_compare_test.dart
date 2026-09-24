// ============================================
// 养生记录表单 —— 「理疗前 → 后」对比卡 (2026-09-24 UI 优化)
//
// 主人原话: 「添加养生记录页面。整个页面都需要优化ui，特别是理疗前状态卡片和
//   理疗后效果卡片」。
//
// 守什么:
//   ① 前后**合并成一张卡**: 三项指标 (疼痛程度 / 睡眠质量 / 情绪) 同屏对比,
//      不再分散在两块一模一样的灰卡里
//   ② 每项指标 = 「前」「后」两个滑块 (共 6 个 Slider) + 一个差值徽章
//   ③ 差值徽章语义: 疼痛 5→3 = `↓2 改善` (越低越好); 睡眠/情绪 3→3 = `持平`
//   ④ 拖「后」疼痛滑块 → 徽章**实时**更新 (改成 10 → `↑5 变差`)
//
// 跑: cd flutter_app && flutter test test/wellness_condition_compare_test.dart
// ============================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/models/dictionaries.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/modules/wellness/screens/wellness_record_form_page.dart';

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

Dictionaries _dict() => const Dictionaries(
      bodyParts: [BodyPart(id: '1', name: '肩颈')],
      serviceItems: [ServiceItem(id: '1', name: '肩颈经络理疗')],
      products: [],
    );

Future<void> _pumpForm(WidgetTester tester) async {
  final dio = Dio(BaseOptions(baseUrl: 'http://test.local/api'))
    ..httpClientAdapter = _FakeDictAdapter(_dict().toJson());

  await tester.pumpWidget(ProviderScope(
    overrides: [dioProvider.overrideWithValue(dio)],
    child: const MaterialApp(home: WellnessRecordFormPage(customerId: '1')),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('① 前/后合并成一张卡: 三项指标 + 6 个滑块 + 3 个差值徽章', (tester) async {
    await _pumpForm(tester);

    // 区块标题 (旧版是「理疗前状态」「理疗后效果」两块)
    expect(find.text('理疗前 → 后'), findsOneWidget,
        reason: '前/后对比合并成一张卡');

    // 三项指标名都在
    expect(find.text('疼痛程度'), findsOneWidget);
    expect(find.text('睡眠质量'), findsOneWidget);
    expect(find.text('情绪'), findsOneWidget);

    // 每项 = 前 + 后 两个滑块 → 共 6 个
    expect(find.byType(Slider), findsNWidgets(6),
        reason: '3 项指标 × (前/后) = 6 个滑块');
    expect(find.text('前'), findsNWidgets(3));
    expect(find.text('后'), findsNWidgets(3));
  });

  testWidgets('② 差值徽章: 疼痛 5→3 = ↓2 改善; 睡眠/情绪未变 = 持平', (tester) async {
    await _pumpForm(tester);

    // 默认值: 疼痛 前5 → 后3 (改善), 睡眠/情绪 3→3 (持平)
    expect(find.text('↓2 改善'), findsOneWidget,
        reason: '疼痛越低越好 → 5→3 是改善');
    expect(find.text('持平'), findsNWidgets(2),
        reason: '睡眠/情绪未变 = 持平');
  });

  testWidgets('③ 拖「后」疼痛滑块到最大 → 徽章实时变「↑5 变差」', (tester) async {
    await _pumpForm(tester);

    // Slider 顺序: [疼痛前, 疼痛后, 睡眠前, 睡眠后, 情绪前, 情绪后]
    final painPost = find.byType(Slider).at(1);
    await tester.drag(painPost, const Offset(600, 0)); // 一路拖到最右 (10)
    await tester.pumpAndSettle();

    // 5 → 10 = +5, 疼痛变高 = 变差
    expect(find.text('↑5 变差'), findsOneWidget,
        reason: '徽章要跟着滑块实时更新 (差值语义: 疼痛升高 = 变差)');
    expect(find.text('↓2 改善'), findsNothing,
        reason: '旧的改善徽章应被替换');
  });
}
