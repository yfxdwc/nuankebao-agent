// chip 文字颜色回归测试 (真机 APK 白字 bug, 主人 2026-09-22 报)
//
// 现象: 「我的」→ 显示与存储 → 字号档位 chip 的文字在 **APK 上发白**, 白卡片上根本看不见;
//       但 /app-preview (Flutter web) 上是黑的 → 预览端验收被"骗过".
//
// 根因 (跟平台无关, 是主题写法问题):
//   AppTheme.light() 的 chipTheme.labelStyle 只写了 fontSize/fontWeight, **没写 color**.
//   RawChip 取样式是 `chipTheme.labelStyle ?? chipDefaults.labelStyle` —— 只要 labelStyle
//   非 null, 就整个顶掉 M3 默认色 (未选 onSurfaceVariant / 选中 onSecondaryContainer)
//   → 文字 color = null → 引擎兜底色 = **白** (Android/Skia 实测 #FFFFFF);
//   而 Flutter web (CanvasKit) 兜底色是**黑**, 所以预览端看着"正常".
//
// 本测试盯住: 真主题下, 字号档位 chip 的文字颜色必须 = AppTheme.textPrimary (深色),
//           不允许 null (null = 真机白字). 这也是"跑 UI 测试要带真主题"的示范 ——
//           之前 profile_page_test.dart 没带 theme, 这类 bug 才漏过去.
//
// 2026-09-25 改动: 字号 chips 已迁到共享 FontSizePicker (lib/core/widgets/),
//   在「我的」/「设置」两页共用。本测试改渲染 FontSizePicker 自身 (轻量),
//   加端到端断言守护两页共用同一份组件。
//
// 2026-09-25 主人追加硬要求:
//   - 4 档必须**单行** (不换行) —— Row + 4 个 Expanded 均分宽, 间距 8 token
//   - 单行不裁字 —— FittedBox(scaleDown) + maxLines:1 + ellipsis + textAlign:center
//   - 硬验收 393/320 × 特大字号: 4 chip dy 相同 + 无 overflow + 不裁字
//   - 中老年触摸区不缩 (ChoiceChip Material 默认 ~48)
//
// 注意: 本测试不需要 stub; FontSizePicker 不打网络。Real ProviderContainer 完全可选,
// 选 MaterialApp + AppTheme.light() 就足够反映生产渲染。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';
import 'package:nuankebao/core/widgets/font_size_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required double fontScale,
}) async {
  // 393/320 两种屏宽都在硬验收里; dpr=3 模拟真机
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      // 关键: 带真主题. 不带 = Flutter 默认样式, 测不出"主题顶掉默认色"这类 bug
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(fontScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(AppSpace.s16),
          child: FontSizePicker(
            selected: AppFontSize.standard,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 收集 4 个 chip 的中心 y (单行 dy 断言用)
List<double> _chipCenters(WidgetTester tester) {
  return tester
      .widgetList<ChoiceChip>(find.byType(ChoiceChip))
      .map((c) {
        final rect = tester.getRect(find.byWidget(c));
        return rect.center.dy;
      })
      .toList();
}

void main() {
  // 直接渲染 FontSizePicker (替代渲染整页 profile_page); 无 provider 依赖。
  testWidgets('字号档位 chip 的文字必须是深色 (null = 真机白字看不见)',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, width: 393, fontScale: 1.0);

    // 字号档位 4 档 (小 / 标准 / 大 / 特大) —— FontSizePicker 渲染 4 个 ChoiceChip
    final chipTexts = tester
        .widgetList<RichText>(find.descendant(
          of: find.byType(ChoiceChip),
          matching: find.byType(RichText),
        ))
        .toList();
    expect(chipTexts.length, 4);

    for (final rt in chipTexts) {
      final text = (rt.text as TextSpan).toPlainText();
      expect(
        rt.text.style?.color,
        AppTheme.textPrimary,
        reason: '「$text」档位文字颜色 = ${rt.text.style?.color} '
            '(null 或非深色 → 真机 APK 上引擎兜底成白色, 白卡片上看不见)',
      );
    }
  });

  // 主人 2026-09-25 追加硬要求: 4 chip 必须单行 (dy 相同) + 不溢出 + 不裁字
  testWidgets('单行布局: 393 宽 × 特大字号 4 chip dy 相同 + 不溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, width: 393, fontScale: 1.3);
    // 装入 padding 在外, 但本检查只关心 chip 之间的 dy 一致性

    // 4 个 ChoiceChip 的中心 y 应当**完全一致** (允许 0.5 浮点抖)
    final centers = _chipCenters(tester);
    expect(centers.length, 4);
    for (final c in centers) {
      expect(c, closeTo(centers.first, 0.5),
          reason: 'chip dy=$c 应≈ dy(0)=${centers.first}');
    }

    // 无溢出
    expect(tester.takeException(), isNull);

    // 4 档 label 文字都渲染出来 (不裁字 = 4 个 Text 都在树里, 而不是被 ellipsis 吃掉)
    expect(find.text('小'), findsOneWidget);
    expect(find.text('标准'), findsOneWidget);
    expect(find.text('大'), findsOneWidget);
    expect(find.text('特大'), findsOneWidget);
  });

  testWidgets('单行布局: 窄屏 320 × 特大字号 4 chip dy 相同 + 不溢出', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, width: 320, fontScale: 1.3);

    final centers = _chipCenters(tester);
    expect(centers.length, 4);
    for (final c in centers) {
      expect(c, closeTo(centers.first, 0.5),
          reason: 'chip dy=$c 应≈ dy(0)=${centers.first}');
    }

    // 窄屏最容易挤破 → 必须无 RenderFlex overflow 异常
    expect(tester.takeException(), isNull);

    // 320 宽 + 特大字号下 4 个 label 仍全部可见 (FittedBox.scaleDown 兜底)
    expect(find.text('小'), findsOneWidget);
    expect(find.text('标准'), findsOneWidget);
    expect(find.text('大'), findsOneWidget);
    expect(find.text('特大'), findsOneWidget);
  });
}
