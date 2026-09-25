// ============================================
// 分段控件 (胶囊) 垂直居中回归测试 —— 2026-09-25 主人报
// ============================================
// 现象: 客户列表右上角「列表 / 图谱」切换胶囊里, 文字**没垂直居中** (看着偏下)。
//
// 根因 (实测): M3 SegmentedButton 的自然高 = 48
//   (minimumSize 40 + tapTargetSize.padded 撑到 48);
//   而客户端 AppBar 高 52 + 上下内边距 → 可用高只有 36~44 < 48 →
//   **胶囊底被压扁, 文字仍按 48 的盒子排版** → 文字相对胶囊中心偏下 6.0px。
//   (body 场景 (约束宽松) 量出来 delta = 0.00 → 所以只在 AppBar 这种紧凑容器里看得见)
//
// 修法: 主题里把分段控件的高度**钉到令牌** (AppSize.buttonMinHeight) + 不撑 tapTarget
//   → 只要容器给够 40, 胶囊就不会被压扁 → 文字恒居中 (任何字号档位)。
//
// ⚠ 必须带真主题: 不带主题走 Flutter 默认样式, 量的是另一套数字 (AGENTS §5 教训)。
// ⚠ 长按/大字号: 带 textScaler 1.3 (中老年「特大」档) 再验一遍 —— 字号变大也不能歪。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';

enum _V { list, graph }

/// 与客户列表右上角**同构**的切换胶囊 (customer_list_page.dart 的 列表/图谱)
Widget _toggle() => SegmentedButton<_V>(
      segments: const [
        ButtonSegment(
          value: _V.list,
          label: Text('列表', style: TextStyle(fontSize: AppType.sm)),
        ),
        ButtonSegment(
          value: _V.graph,
          label: Text('图谱', style: TextStyle(fontSize: AppType.sm)),
        ),
      ],
      selected: const {_V.list},
      showSelectedIcon: false,
      onSelectionChanged: (_) {},
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool inAppBar,
  double toolbarHeight = AppSize.appBarHeight,
  double fontScale = 1.0,
  double verticalPadding = AppSpace.s4,
}) async {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final toggle = Padding(
    padding: EdgeInsets.symmetric(
      horizontal: AppSpace.s12,
      vertical: verticalPadding,
    ),
    child: _toggle(),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(fontScale)),
        child: child!,
      ),
      home: Scaffold(
        appBar: inAppBar
            ? AppBar(
                title: const Text('客户'),
                toolbarHeight: toolbarHeight,
                actions: [toggle],
              )
            : null,
        body: inAppBar ? const SizedBox() : Center(child: toggle),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 量「文字中线」与「胶囊底 (Material) 中线」的偏差
double _textVsPillDelta(WidgetTester tester, String label) {
  final textRect = tester.getRect(find.text(label));
  final pills = tester
      .widgetList<Material>(find.descendant(
        of: find.byType(SegmentedButton<_V>),
        matching: find.byType(Material),
      ))
      .toList();
  // 最外那个 Material = 整条胶囊的外框
  final pillRect = tester.getRect(find.byWidget(pills.first));
  return textRect.center.dy - pillRect.center.dy;
}

/// 整条胶囊实际高度 (压扁检测)
double _pillHeight(WidgetTester tester) =>
    tester.getRect(find.byType(SegmentedButton<_V>)).height;

void main() {
  group('分段控件垂直居中 (AppBar 右上角场景)', () {
    testWidgets('文字中线 == 胶囊中线 (±0.5px)', (tester) async {
      await _pump(tester, inAppBar: true);
      expect(_textVsPillDelta(tester, '列表'), closeTo(0, 0.5),
          reason: '列表: 文字没在胶囊里垂直居中');
      expect(_textVsPillDelta(tester, '图谱'), closeTo(0, 0.5),
          reason: '图谱: 文字没在胶囊里垂直居中');
    });

    testWidgets('胶囊高度 == 令牌高 (没被压扁)', (tester) async {
      await _pump(tester, inAppBar: true);
      expect(_pillHeight(tester), AppSize.buttonMinHeight,
          reason: '被容器压扁会让"文字盒"和"胶囊底"对不上 (本次 bug 的根因)');
    });

    testWidgets('特大字号 (1.3) 下依然居中', (tester) async {
      await _pump(tester, inAppBar: true, fontScale: 1.3);
      expect(_textVsPillDelta(tester, '列表'), closeTo(0, 0.5));
      expect(_textVsPillDelta(tester, '图谱'), closeTo(0, 0.5));
    });
  });

  group('visualDensity.compact (admin_tools 那种紧凑用法) 也不能歪', () {
    testWidgets('紧凑密度: 文字中线 == 胶囊中线', (tester) async {
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Center(
              child: SegmentedButton<_V>(
                // 与 admin_tools_page 的写法一致 (段头部里塞紧凑分段控件)
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(
                    value: _V.list,
                    label: Text('列表', style: TextStyle(fontSize: AppType.sm)),
                  ),
                  ButtonSegment(
                    value: _V.graph,
                    label: Text('图谱', style: TextStyle(fontSize: AppType.sm)),
                  ),
                ],
                selected: const {_V.list},
                showSelectedIcon: false,
                onSelectionChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_textVsPillDelta(tester, '列表'), closeTo(0, 0.5),
          reason: 'compact 密度下文字也要在胶囊里居中');
      expect(_textVsPillDelta(tester, '图谱'), closeTo(0, 0.5));
    });
  });

  group('分段控件垂直居中 (正文场景, 约束宽松)', () {
    testWidgets('文字中线 == 胶囊中线 (±0.5px)', (tester) async {
      await _pump(tester, inAppBar: false);
      expect(_textVsPillDelta(tester, '列表'), closeTo(0, 0.5));
      expect(_textVsPillDelta(tester, '图谱'), closeTo(0, 0.5));
    });

    testWidgets('高度 == 令牌高 (与 AppBar 场景一致, 不出现两套高)', (tester) async {
      await _pump(tester, inAppBar: false);
      expect(_pillHeight(tester), AppSize.buttonMinHeight);
    });
  });

  group('几何契约: AppBar 必须给得下胶囊的自然高', () {
    test('AppBar 高 - 上下内边距 ≥ buttonMinHeight (否则必被压扁)', () {
      // 这条是本次 bug 的算术根因 —— 将来谁调 appBarHeight / 内边距都会在这里被拦下
      const available = AppSize.appBarHeight - 2 * AppSpace.s4;
      expect(available, greaterThanOrEqualTo(AppSize.buttonMinHeight),
          reason: 'AppBar 里放分段控件至少要留 ${AppSize.buttonMinHeight}px, 现在只有 $available');
    });
  });
}
