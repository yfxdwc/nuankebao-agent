// ============================================
// 主题令牌契约测试 (Flutter 侧)
// ============================================
// 守护的东西:
//   ① 每个主题都能装出可用 ThemeData (换肤不会白屏 / 不炸)
//   ② 组件的 TextStyle **全都有显式 color** —— 2026-09-22 主人报的「字号 chip 白字」根因。
//      ⚠ 这类 bug 只有带真主题的 widget test 才测得出:
//        不带 theme → 走 Flutter 默认样式 → 永远绿通过。
//   ③ 对比度门槛 (中老年可读性): 生成器已按亮度推导, 这里对**装配后的 ThemeData** 复验
//   ④ AppTheme 兼容层 == 默认主题 (存量 54 个文件语义不变)
//
// 跑: cd flutter_app && flutter test test/theme_tokens_test.dart
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/core/theme/theme_ext.dart';
import 'package:nuankebao/core/theme/tokens.g.dart';

/// WCAG 对比度
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('① 主题目录', () {
    test('至少 5 个主题, id 唯一, 恰好一个默认', () {
      expect(AppThemes.all.length, greaterThanOrEqualTo(5));
      final ids = AppThemes.all.map((t) => t.id).toSet();
      expect(ids.length, AppThemes.all.length, reason: '主题 id 有重复');
      expect(ids.where((id) => id == AppThemes.defaultId).length, 1);
    });

    test('resolve() 对未知/空 id 安全回落到默认 (旧版本遗留的偏好值)', () {
      expect(AppThemes.resolve(null).id, AppThemes.defaultId);
      expect(AppThemes.resolve('不存在的主题').id, AppThemes.defaultId);
      expect(AppThemes.resolve('').id, AppThemes.defaultId);
      expect(AppThemes.resolve('spring').id, 'spring');
    });

    test('grouped 覆盖全部主题 (设置页分组渲染不漏项)', () {
      final flat = AppThemes.grouped.values.expand((v) => v).toList();
      expect(flat.length, AppThemes.all.length);
      expect(AppThemes.grouped.keys, contains('品牌'));
      expect(AppThemes.grouped.keys, contains('季节'));
    });

    test('每个主题的 label/group 非空 (UI 上不会出现空标签)', () {
      for (final t in AppThemes.all) {
        expect(t.label.trim(), isNotEmpty, reason: '${t.id} 缺 label');
        expect(t.group.trim(), isNotEmpty, reason: '${t.id} 缺 group');
        expect(t.id.trim(), isNotEmpty);
      }
    });
  });

  group('② 每个主题都能装出可用 ThemeData', () {
    for (final theme in AppThemes.all) {
      test('${theme.label}: light() 不抛异常且关键主题项就位', () {
        final td = AppTheme.light(theme);

        expect(td.useMaterial3, isTrue);
        expect(td.colorScheme.primary, theme.primary);
        expect(td.colorScheme.surface, theme.surface);
        expect(td.scaffoldBackgroundColor, theme.surface);

        // 令牌挂上去了 (否则 context.tokens 会静默退回默认主题)
        final attached = td.extension<AppTokensTheme>();
        expect(attached, isNotNull, reason: '${theme.id} 没挂 AppTokensTheme');
        expect(attached!.tokens.id, theme.id);

        // 中老年尺寸底线
        expect(td.appBarTheme.toolbarHeight, AppSize.appBarHeight);
        expect(
          td.floatingActionButtonTheme.sizeConstraints?.maxWidth,
          AppSize.fabSize,
        );
      });
    }
  });

  group('③ 组件 TextStyle 必须显式写 color (白字 bug 防线)', () {
    for (final theme in AppThemes.all) {
      test('${theme.label}: chip 的 labelStyle / secondaryLabelStyle 有 color', () {
        final chip = AppTheme.light(theme).chipTheme;
        // RawChip 取样式 = chipTheme.labelStyle ?? defaults.labelStyle ——
        // 只要我们的非空但没 color, 就把 M3 默认色顶掉 → 文字 color=null → 引擎兜底白字
        expect(chip.labelStyle?.color, isNotNull,
            reason: '${theme.id} chip labelStyle 没写 color → 白卡片上看不见');
        expect(chip.secondaryLabelStyle?.color, isNotNull,
            reason: '${theme.id} chip secondaryLabelStyle 没写 color → 选中态看不见');
        expect(chip.labelStyle!.fontSize, AppType.md);
      });

      test('${theme.label}: 全 ThemeData 里不存在"写了字号却漏 color"的文本样式', () {
        final td = AppTheme.light(theme);
        final offenders = <String>[];

        void check(String where, TextStyle? style) {
          if (style == null) return;
          if (style.fontSize != null && style.color == null) {
            offenders.add('$where (fontSize=${style.fontSize})');
          }
        }

        final tt = td.textTheme;
        final textStyles = <String, TextStyle?>{
          'displayLarge': tt.displayLarge,
          'displayMedium': tt.displayMedium,
          'displaySmall': tt.displaySmall,
          'headlineLarge': tt.headlineLarge,
          'headlineMedium': tt.headlineMedium,
          'headlineSmall': tt.headlineSmall,
          'titleLarge': tt.titleLarge,
          'titleMedium': tt.titleMedium,
          'titleSmall': tt.titleSmall,
          'bodyLarge': tt.bodyLarge,
          'bodyMedium': tt.bodyMedium,
          'bodySmall': tt.bodySmall,
          'labelLarge': tt.labelLarge,
          'labelMedium': tt.labelMedium,
          'labelSmall': tt.labelSmall,
          'appBar.title': td.appBarTheme.titleTextStyle,
          'chip.label': td.chipTheme.labelStyle,
          'chip.secondaryLabel': td.chipTheme.secondaryLabelStyle,
          'listTile.title': td.listTileTheme.titleTextStyle,
          'listTile.subtitle': td.listTileTheme.subtitleTextStyle,
          'bottomNav.selected': td.bottomNavigationBarTheme.selectedLabelStyle,
          'bottomNav.unselected':
              td.bottomNavigationBarTheme.unselectedLabelStyle,
          'dialog.title': td.dialogTheme.titleTextStyle,
          'dialog.content': td.dialogTheme.contentTextStyle,
          'snackBar.content': td.snackBarTheme.contentTextStyle,
          'popupMenu': td.popupMenuTheme.textStyle,
          'tabBar.label': td.tabBarTheme.labelStyle,
          'tabBar.unselected': td.tabBarTheme.unselectedLabelStyle,
          'input.label': td.inputDecorationTheme.labelStyle,
          'input.hint': td.inputDecorationTheme.hintStyle,
          'input.helper': td.inputDecorationTheme.helperStyle,
          'input.error': td.inputDecorationTheme.errorStyle,
          'tooltip': td.tooltipTheme.textStyle,
        };
        textStyles.forEach(check);

        // 按钮样式里的 textStyle (styleFrom 也会顶掉默认色)
        check('elevatedButton', td.elevatedButtonTheme.style?.textStyle?.resolve({}));
        check('outlinedButton', td.outlinedButtonTheme.style?.textStyle?.resolve({}));
        check('textButton', td.textButtonTheme.style?.textStyle?.resolve({}));

        expect(offenders, isEmpty,
            reason: '这些样式只设了字号没设 color → 会把 Flutter 默认色整个顶掉:\n'
                '${offenders.join('\n')}');
      });
    }
  });

  group('④ 对比度门槛 (在装配后的 ThemeData 上复验)', () {
    for (final theme in AppThemes.all) {
      test('${theme.label}: 主要配对 ≥ AA, 正文 ≥ AAA', () {
        // 硬门槛: primary 是按钮底色, 上面永远压白字。
      // 2026-09-23 主人拍板从 AAA 降到 AA 换调色自由度 —— AA 是业界标准 (微信/Linear/Stripe 都按 AA)。
      // 不能再降; 但也不必 AAA。
      expect(_contrast(theme.primary, theme.onPrimary), greaterThanOrEqualTo(4.5),
            reason: '按钮底/字 AA 硬门槛 (design-tokens.json → contrast.minOnColorRatio)');
        expect(_contrast(theme.accent, theme.onAccent), greaterThanOrEqualTo(4.5),
            reason: '强调色底/字');
        expect(_contrast(theme.textPrimary, theme.surface),
            greaterThanOrEqualTo(7), reason: '正文/背景');
        expect(_contrast(theme.textSecondary, theme.surface),
            greaterThanOrEqualTo(7), reason: '副文/背景');
        expect(_contrast(theme.border, theme.surfaceCard),
            greaterThanOrEqualTo(1.5), reason: '边框在卡片上的可见性');
      });

      test('${theme.label}: contrastReport() 全达标', () {
        final report = theme.contrastReport();
        expect(report.length, 6);
        for (final entry in report.entries) {
          final floor = entry.key.contains('border') ? 1.5 : 4.5;
          expect(entry.value, greaterThanOrEqualTo(floor),
              reason: '${theme.id} ${entry.key} = ${entry.value.toStringAsFixed(2)}');
        }
      });
    }

    test('浅暖橙 accent 不能配白字 (旧配色表的坑)', () {
      final sage = AppThemes.resolve(null);
      expect(_contrast(sage.accent, const Color(0xFFFFFFFF)), lessThan(3.0));
      expect(sage.onAccent, const Color(0xFF1A1A1A),
          reason: '浅底必须自动配深前景');
    });
  });

  group('⑤ 尺度令牌 (不随主题变, 中老年底线)', () {
    test('字号档位满足可读性底线 (B 档: 正文 ≥15, 副信息 ≥13, 角标 ≥12)', () {
      // 2026-09-23 主人拍板从适老化改为紧凑专业(B 档): 正文 18 → 15。
      // 中文 15px 是企业应用主流 (微信 17 / iOS 17 / Linear 14-15),
      // 一屏能多看约 80% 信息。
      expect(AppType.md, greaterThanOrEqualTo(15));
      expect(AppType.sm, greaterThanOrEqualTo(13));
      // xs (角标) 12 / micro (画布) 11 —— 仅在特定场景用, 不是 UI 底线
      expect(AppType.xs, greaterThanOrEqualTo(12));
      expect(AppType.micro, greaterThanOrEqualTo(11));
      expect(AppType.xs, lessThan(AppType.sm));
      expect(AppType.sm, lessThan(AppType.md));
      expect(AppType.md, lessThan(AppType.lg));
      expect(AppType.lg, lessThan(AppType.xl));
      expect(AppType.xl, lessThan(AppType.xxl));
    });

    test('触摸目标 ≥48pt (WCAG 2.5.5) — 「紧凑」不等于「难点」', () {
      // 设计原则 (docs/ui-principles.md §3.1): 视觉可以小, 热区不能小。
      // 2026-09-23 B 档把 buttonLgHeight 64 → 48 (Material 标准), tapMin 仍是 48。
      // 视觉 32px 的图标按钮: iconSize:32 + padding:8 → hit box 48。
      expect(AppSize.tapMin, greaterThanOrEqualTo(48));
      // 主按钮 (buttonLgHeight) 必须等于 tapMin (紧凑化后的最大值 = 热区下限)
      expect(AppSize.buttonLgHeight, AppSize.tapMin);
      // 次按钮 (buttonMinHeight) 可以 < tapMin —— 视觉紧凑, 用 padding 撑热区
      expect(AppSize.buttonMinHeight, lessThanOrEqualTo(AppSize.tapMin));
    });

    test('spacing 尺度单调递增且都是正数', () {
      final vals = [AppSpace.s0, AppSpace.s4, AppSpace.s8, AppSpace.s12,
        AppSpace.s16, AppSpace.s20, AppSpace.s24, AppSpace.s32];
      for (var i = 1; i < vals.length; i++) {
        expect(vals[i], greaterThan(vals[i - 1]));
      }
    });

    test('语义间距别名指向真实档位 (B 档)', () {
      // 2026-09-23 B 档: 紧凑化
      expect(AppSpace.pagePadding, AppSpace.s16);    // 不变
      expect(AppSpace.cardPadding, AppSpace.s14);   // 16 → 14
      expect(AppSpace.cardGap, AppSpace.s10);       // 12 → 10
      expect(AppSpace.sectionGap, AppSpace.s20);    // 24 → 20
      expect(AppSpace.listRowPadding, AppSpace.s14);// 16 → 14
      expect(AppSpace.formFieldGap, AppSpace.s10);   // 12 → 10
      expect(AppRadius.card, AppRadius.r10);        // 12 → 10
      expect(AppRadius.button, AppRadius.r8);        // 12 → 8
      expect(AppRadius.badge, AppRadius.r4);         // 8 → 4 (小元素小圆角)
      // chip → 全圆 (避免半吊子圆角显廉价)
      expect(AppRadius.chip, 999.0);
    });

    test('动效时长有序', () {
      expect(AppDuration.fast.inMilliseconds,
          lessThan(AppDuration.base.inMilliseconds));
      expect(AppDuration.base.inMilliseconds,
          lessThan(AppDuration.slow.inMilliseconds));
    });
  });

  group('⑥ AppTheme 兼容层 (存量 54 个文件语义不变)', () {
    test('旧常量 == 默认主题的槽位值', () {
      final d = AppThemes.resolve(null);
      expect(AppTheme.primary, d.primary);
      expect(AppTheme.primaryLight, d.primaryLight);
      expect(AppTheme.primaryDark, d.primaryDark);
      expect(AppTheme.accent, d.accent);
      expect(AppTheme.danger, d.danger);
      expect(AppTheme.bgWarm, d.surface);
      expect(AppTheme.bgCard, d.surfaceCard);
      expect(AppTheme.textPrimary, d.textPrimary);
      expect(AppTheme.textSecondary, d.textSecondary);
      expect(AppTheme.border, d.borderInput);
      expect(AppTheme.franchisee, d.graphFranchiseeB);
      expect(AppTheme.franchiseeA, d.graphFranchiseeA);
    });

    test('AppTheme.light() 无参 == 默认主题 (旧调用点不炸)', () {
      expect(AppTheme.light().colorScheme.primary, AppTheme.primary);
    });

    test('旧字号/尺寸常量 == 生成的尺度令牌', () {
      expect(AppTheme.fontXs, AppType.xs);
      expect(AppTheme.fontSm, AppType.sm);
      expect(AppTheme.fontMd, AppType.md);
      expect(AppTheme.fontLg, AppType.lg);
      expect(AppTheme.fontXl, AppType.xl);
      expect(AppTheme.fontXxl, AppType.xxl);
      expect(AppTheme.buttonLgHeight, AppSize.buttonLgHeight);
      expect(AppTheme.fabSize, AppSize.fabSize);
      expect(AppTheme.listRowHeight, AppSize.listRowHeight);
    });
  });

  group('⑦ context.tokens 真的跟随主题 (换肤链路端到端)', () {
    testWidgets('换 MaterialApp.theme → context.tokens 跟着变', (tester) async {
      late AppTokens seen;
      late String seenId;

      Widget probe() => Builder(
            builder: (ctx) {
              seen = ctx.tokens;
              seenId = ctx.themeId;
              return const SizedBox.shrink();
            },
          );

      for (final theme in AppThemes.all) {
        await tester.pumpWidget(
          MaterialApp(theme: AppTheme.light(theme), home: probe()),
        );
        // MaterialApp 内部是 AnimatedTheme: 换肤会 lerp kThemeAnimationDuration,
        // 不等它跑完拿到的还是上一个主题 (我们的 lerp 是离散的, t<0.5 返回旧主题)
        await tester.pumpAndSettle();
        expect(seenId, theme.id, reason: '${theme.id} 没切过去');
        expect(seen.primary, theme.primary);
        expect(seen, same(theme), reason: '应拿到该主题的实例');
      }
    });

    testWidgets('没挂 ThemeData 时安全兜底 (不抛异常)', (tester) async {
      late AppTokens fallback;
      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: (ctx) {
          fallback = ctx.tokens;
          return const SizedBox.shrink();
        })),
      );
      expect(fallback.id, AppThemes.defaultId);
    });

    testWidgets('带真主题的 chip 能渲染出正确字色 (不带主题就测不出白字 bug)', (tester) async {
      final spring = AppThemes.resolve('spring');
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(spring),
        home: Scaffold(
          body: Center(
            child: ChoiceChip(
              label: const Text('标准'),
              selected: true,
              onSelected: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final rp = tester.renderObject<RenderParagraph>(find.text('标准'));
      final rendered = rp.text.style?.color;
      expect(rendered, isNotNull,
          reason: 'chip 文字没色 = 白字不可见 (2026-09-22 复发点)');
      // 真正的复现路径: 白底白字。渲染色必须跟当前主题的底色可区分
      expect(rendered, isNot(const Color(0xFFFFFFFF)));
      expect(_contrast(rendered!, spring.surfaceCard), greaterThanOrEqualTo(4.5),
          reason: 'chip 文字对卡片底必须可读');
      expect(find.text('标准'), findsOneWidget);
    });
  });
}
