// 临时视觉验证 (主人 2026-09-18「客户列表筛选胶囊」任务, 验证后删)
// 目的: 393x852 真机尺寸渲染 customers page 顶部 (搜索框 + 筛选手胶囊), 出 PNG 肉眼验
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/modules/customer/screens/customers_page.dart';

Future<void> _loadCjkFont() async {
  // Noto Sans CJK (.ttc, index 0) — 让 golden 里的中文是真字形不是豆腐块
  const path = '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc';
  final file = File(path);
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  final loader = FontLoader('NotoSansCJK')
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

void main() {
  testWidgets('客户列表页 筛选手胶囊 393x852', (tester) async {
    await _loadCjkFont();
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const CustomersListPage()),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          customersProvider.overrideWith((ref, arg) async => <dynamic>[]),
          myFranchiseeTreeProvider.overrideWith((ref, depth) async => null),
        ],
        child: MaterialApp.router(
          theme: AppTheme.light().copyWith(
            textTheme: AppTheme.light().textTheme.apply(fontFamily: 'NotoSansCJK'),
          ),
          routerConfig: router,
        ),
      ),
    );
    // 不用 pumpAndSettle: loading spinner / RefreshIndicator 一直在动, 会挂死
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));

    // 溢出 = 测试直接红, 这里显式断言一次 (胶囊 4 段平分 393pt)
    expect(tester.takeException(), isNull);

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/tmp_filter_capsule_list.png'),
    );

    // 选中态也截一张 (点「普通」)
    await tester.tap(find.text('🟢 普通'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/tmp_filter_capsule_list_selected.png'),
    );
  });
}
