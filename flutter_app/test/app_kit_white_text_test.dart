// ============================================
// app_kit_white_text_test —— 防「主题漏 color → 真机白字」再生
// ============================================
//
// 背景 (AGENTS §5 chip 白字教训, 2026-09-22 主人报告):
//   给 `ThemeData` 的组件样式 (`chipTheme.labelStyle` 等) 设了**非 null 但没 color** 的
//   TextStyle, 等于整个**顶掉** Flutter 的组件默认色:
//     RawChip 取样式 = `chipTheme.labelStyle ?? chipDefaults.labelStyle`
//     默认色来自 M3: 未选 `onSurfaceVariant` / 选中 `onSecondaryContainer`
//   → 文字 `color = null` → 引擎兜底色 = **白** (Android/Skia 实测 `#FFFFFF`)
//   → 白卡片上根本看不见
//
// 修法: 每个 `TextStyle` **必须显式写 color**; 本测试遍历本批 (B0a/B1/B2/B4)
//   引入 / 改造的组件, 断言 widget tree 里所有 Text widget 的解析后 style 都非 null color.
//
//   ⚠ 必须带真主题 (`MaterialApp(theme: AppTheme.light())`),
//     不带主题 → 走 Flutter 默认样式 → 永远绿通过, 漏 color 这类 bug 测不出来.
//
// 跑: cd flutter_app && flutter test test/app_kit_white_text_test.dart --concurrency=1
//
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/widgets/app_badge.dart';
import 'package:nuankebao/core/widgets/app_empty.dart';
import 'package:nuankebao/core/widgets/app_list_row.dart';
import 'package:nuankebao/core/widgets/app_section.dart';
import 'package:nuankebao/core/widgets/app_sheet_header.dart';
import 'package:nuankebao/core/widgets/app_skeleton.dart';
import 'package:nuankebao/core/widgets/app_stat_row.dart';

/// 测试夹具 —— 把 child 装进带真主题的 MaterialApp
Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    );

/// 在测试 widget tree 里收集所有 Text widget 的**解析后** style, 断言 color 非 null.
///
/// 关键: Text 自己的 `style` 常为 null, 真推下来的样式要 `DefaultTextStyle.of(context)`.
List<TextStyle> _allResolvedTextStyles(WidgetTester tester) {
  final styles = <TextStyle>[];
  for (final w in tester.widgetList<Text>(find.byType(Text))) {
    final ctx = tester.element(find.byWidget(w));
    styles.add(DefaultTextStyle.of(ctx).style);
  }
  return styles;
}

void main() {
  // 拼装一组样本 widget, 涵盖本批 (B0a/B1/B2/B4) 引入 / 改造的所有 B 档组件
  Widget sample() => _wrap(
        ListView(
          children: const [
            // B0a: 7 个 app_kit 组件
            AppListRow(title: Text('客户姓名')),
            AppListRow(
              title: Text('客户姓名'),
              subtitle: Text('副文'),
              meta: Text('3 天'),
            ),
            AppSection(title: '区块', child: Text('内容')),
            AppSectionHeader(title: '区块标题', subtitle: '副标题'),
            AppStatRow(label: '标签', value: '128'),
            AppSheetHeader(title: '弹层标题'),
            AppBadge(label: '徽章', tone: AppBadgeTone.brand),
            AppBadge(label: '徽章-成功', tone: AppBadgeTone.success),
            AppBadge(label: '徽章-危险', tone: AppBadgeTone.danger),
            AppBadge(label: '徽章-警告', tone: AppBadgeTone.warning),
            AppBadge(label: '徽章-信息', tone: AppBadgeTone.info),
            AppBadge(label: '徽章-金', tone: AppBadgeTone.gold),
            AppBadge(label: '徽章-灰', tone: AppBadgeTone.neutral),
            AppEmptyState(
              title: '空态标题',
              hint: '空态副标题',
              action: SizedBox(width: 80, height: 40),
              secondaryAction: SizedBox(width: 60, height: 30),
            ),
            AppSkeleton(width: 100, height: 16),
            AppSkeletonList(rows: 3),
          ],
        ),
      );

  group('防「主题漏 color → 真机白字」再生 (B0a/B1/B2/B4 组件集)', () {
    testWidgets('样本 widget tree 里所有 Text 的解析后样式 color 都不是 null', (tester) async {
      await tester.pumpWidget(sample());
      await tester.pumpAndSettle();

      final styles = _allResolvedTextStyles(tester);
      expect(styles, isNotEmpty, reason: '样本里至少应该有 Text 节点');

      var nullCount = 0;
      final offenders = <String>[];
      for (var i = 0; i < styles.length; i++) {
        final s = styles[i];
        if (s.color == null) {
          nullCount++;
          // 找这个 Text widget 显示什么
          final texts = tester.widgetList<Text>(find.byType(Text)).toList();
          if (i < texts.length) {
            offenders.add('「${texts[i].data ?? '<no data>'}」 color=null');
          }
        }
      }
      expect(
        nullCount,
        0,
        reason:
            '有 ${nullCount} 个 Text 解析后 color 为 null (会导致真机白字): ${offenders.take(5).join(", ")}',
      );
    });

    testWidgets('每个 AppBadge tone 单独验证: text.color 非 null', (tester) async {
      for (final tone in AppBadgeTone.values) {
        await tester.pumpWidget(_wrap(AppBadge(label: 'X', tone: tone)));
        final text = tester.widget<Text>(find.text('X'));
        expect(text.style!.color, isNotNull,
            reason: 'tone=${tone.name}: TextStyle.color 不能为 null (真机会白字)');
      }
    });

    testWidgets('AppListRow title 解析后 color 非 null', (tester) async {
      await tester.pumpWidget(_wrap(const AppListRow(title: Text('王女士'))));
      // 解析后样式走 DefaultTextStyle.of
      final ctx = tester.element(find.text('王女士'));
      final resolved = DefaultTextStyle.of(ctx).style;
      expect(resolved.color, isNotNull,
          reason: 'AppListRow.title 默认颜色必须显式声明 (防白字)');
    });

    testWidgets('AppStatRow value 解析后 color 非 null', (tester) async {
      await tester.pumpWidget(_wrap(const AppStatRow(label: 'L', value: 'V')));
      final ctx = tester.element(find.text('V'));
      final resolved = DefaultTextStyle.of(ctx).style;
      expect(resolved.color, isNotNull,
          reason: 'AppStatRow.value 默认颜色必须显式声明 (防白字)');
    });

    testWidgets('AppSectionHeader title 解析后 color 非 null', (tester) async {
      await tester.pumpWidget(_wrap(const AppSectionHeader(title: 'T')));
      final ctx = tester.element(find.text('T'));
      final resolved = DefaultTextStyle.of(ctx).style;
      expect(resolved.color, isNotNull,
          reason: 'AppSectionHeader.title 默认颜色必须显式声明 (防白字)');
    });

    testWidgets('AppEmptyState title 解析后 color 非 null', (tester) async {
      await tester.pumpWidget(_wrap(const AppEmptyState(title: 'T', hint: 'H')));
      final ctx = tester.element(find.text('T'));
      final resolved = DefaultTextStyle.of(ctx).style;
      expect(resolved.color, isNotNull,
          reason: 'AppEmptyState.title 默认颜色必须显式声明 (防白字)');
    });

    testWidgets('AppSheetHeader title 解析后 color 非 null', (tester) async {
      await tester.pumpWidget(_wrap(const AppSheetHeader(title: '新建客户')));
      final ctx = tester.element(find.text('新建客户'));
      final resolved = DefaultTextStyle.of(ctx).style;
      expect(resolved.color, isNotNull,
          reason: 'AppSheetHeader.title 默认颜色必须显式声明 (防白字)');
    });
  });
}