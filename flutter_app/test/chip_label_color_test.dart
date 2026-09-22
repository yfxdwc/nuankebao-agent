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
// 注意: 本文件自己搭最小 harness (不去动 profile_page_test.dart):
//   - 只渲染「我的」页顶部区块, viewport 够高就能看到「显示与存储」的 chip
//   - appReleaseProvider 必须 override: 「邀请被推荐人」区块读它, 不 override 会一直
//     AsyncLoading → 里面是 CircularProgressIndicator (无限动画) → pumpAndSettle 永不收敛

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/me.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/providers/settings_provider.dart';
import 'package:nuankebao/core/services/api.dart' show MyReferral;
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/screens/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    meProfileProvider.overrideWith((ref) async => MeProfile.fromJson({
          'user': {'id': '1', 'name': '张三', 'roleLabel': '销售员'},
          'phone': {'full': '13800138000', 'masked': '138****8000'},
          'stats': {'customerCount': 3},
        })),
    myReferralsProvider.overrideWith((ref) async => const <MyReferral>[]),
    // 见文件头: 不 stub 这个 = 无限 spinner = 测试挂死
    appReleaseProvider.overrideWith((ref) async => const AppRelease()),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  testWidgets('字号档位 chip 的文字必须是深色 (null = 真机白字看不见)', (tester) async {
    final container = await _container();
    tester.view.physicalSize = const Size(393 * 3, 3400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          // 关键: 带真主题. 不带 = Flutter 默认样式, 测不出"主题顶掉默认色"这类 bug
          theme: AppTheme.light(),
          home: const ProfilePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 页面里 ChoiceChip 只有「显示与存储」的字号档位用 (小 / 标准 / 大 / 特大)
    expect(find.text('显示与存储'), findsOneWidget);
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
}
