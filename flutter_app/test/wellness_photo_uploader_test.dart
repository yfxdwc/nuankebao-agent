// ============================================
// 部位照片条 —— 等宽一行 + 最多 5 张 (2026-09-24 主人诉求)
//
// 主人原话: 「拍照和相册这两个按键也可以收到与标题（部位照片）同一行。
//   上传照片最多5张，照片等宽排在同一行」。
//
// 守什么:
//   ① 默认 maxPhotos = 5
//   ② 照片条固定 5 个槽位, **永远一行**, 宽度彼此相等 (照片变多也不会忽大忽小)
//   ③ 「拍照」「相册」与标题「部位照片」在同一行 (垂直中心对齐)
//
// 跑: cd flutter_app && flutter test test/wellness_photo_uploader_test.dart
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/modules/wellness/widgets/wellness_photo_uploader.dart';

Future<void> _pump(WidgetTester tester, {required List<String> urls}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(AppThemes.sage),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: WellnessPhotoUploaderScope(
          upload: (_) async => 'https://example.test/uploaded.jpg',
          child: WellnessPhotoUploader(
            existingUrls: urls,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('① 默认最多 5 张', (tester) async {
    await _pump(tester, urls: const []);
    final w = tester.widget<WellnessPhotoUploader>(
        find.byType(WellnessPhotoUploader));
    expect(w.maxPhotos, 5, reason: '主人拍: 上传照片最多 5 张');
    expect(find.textContaining('已上传 0 / 5'), findsOneWidget);
  });

  testWidgets('② 照片条 = 固定 5 个等宽槽位, 永远一行', (tester) async {
    // 2 张已有照片 → 2 张缩略图 + 3 个空槽位
    await _pump(tester, urls: ['https://example.test/1.jpg', 'https://example.test/2.jpg']);

    final strip = find.byKey(const ValueKey('photoStrip'));
    expect(strip, findsOneWidget);

    final slots = find.descendant(of: strip, matching: find.byType(AspectRatio));
    expect(slots, findsNWidgets(5), reason: '固定 5 个槽位 (maxPhotos=5)');

    // 同一行 + 等宽
    final rects = [for (var i = 0; i < 5; i++) tester.getRect(slots.at(i))];
    for (final r in rects) {
      expect((r.top - rects.first.top).abs(), lessThan(0.5),
          reason: '5 个槽位必须在同一行');
      expect((r.width - rects.first.width).abs(), lessThan(0.5),
          reason: '槽位等宽 (照片数变化时不忽大忽小)');
    }

    // 空槽位数量正确 (3 个)
    expect(find.byKey(const ValueKey('photoSlot-empty-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('photoSlot-empty-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('photoSlot-empty-4')), findsOneWidget);
  });

  testWidgets('③ 已上传数量在标题右侧; 标题行的拍照/相册按钮已删除', (tester) async {
    await _pump(tester, urls: ['https://example.test/1.jpg']);

    // 2026-09-24 主人: 「已上传数量移动到标题右侧」
    final title = find.text('部位照片');
    final count = find.textContaining('已上传 1 / 5');
    expect(title, findsOneWidget);
    expect(count, findsOneWidget);

    final titleRect = tester.getRect(title);
    final countRect = tester.getRect(count);
    expect(countRect.left, greaterThan(titleRect.right),
        reason: '数量要在标题**右侧**');
    expect((countRect.center.dy - titleRect.center.dy).abs(), lessThan(2.0),
        reason: '同一行 (垂直居中对齐)');

    // 主人: 「区块右上角的拍照和相册按键可以删除了」—— 加照片统一走点空槽位
    expect(find.text('拍照'), findsNothing);
    expect(find.text('相册'), findsNothing);
  });

  testWidgets('④ 点空槽位 → 弹「拍照 / 从相册选」选择层', (tester) async {
    await _pump(tester, urls: const []);

    await tester.tap(find.byKey(const ValueKey('photoSlot-empty-0')));
    await tester.pumpAndSettle();

    expect(find.text('拍照'), findsOneWidget, reason: '弹层里有拍照');
    expect(find.textContaining('从相册选'), findsOneWidget, reason: '弹层里有相册 (可多选)');
  });
}
