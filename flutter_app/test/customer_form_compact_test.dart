// ============================================
// 编辑客户页 —— 紧凑排版 + 吸底保存 (2026-09-25 主人)
//
// 主人原话: 「编辑客户页，排版要更紧凑，例如姓名、性别、电话完全可以并排到同一行，
//   其他条目你根据情况也做排版优化。保存键固定置底」。
//
// 守什么:
//   ① 姓名 / 性别 / 手机号 **同一行** (垂直中心对齐, 依次左→右)
//   ② 生日标题行里带「阳历 / 农历」(历法不再单独占一行)
//   ③ 保存键**吸底** —— 滚动列表时位置不动, 且贴着视口底部
//   ④ 窄屏 (390) 不溢出 (Compactness 不能靠"挤爆"换)
//
// 跑: cd flutter_app && flutter test test/customer_form_compact_test.dart
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/modules/customer/screens/customer_form_page.dart';

Future<void> _pump(WidgetTester tester, {Size? surface}) async {
  if (surface != null) {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const CustomerFormPage(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('① 姓名 / 性别 / 手机号 同一行 (中心对齐 + 左→右顺序)', (tester) async {
    await _pump(tester, surface: const Size(390, 844));

    final name = find.widgetWithText(TextFormField, '姓名 *');
    final gender = find.byType(DropdownButtonFormField<String>);
    final phone = find.widgetWithText(TextFormField, '手机号 *');

    expect(name, findsOneWidget);
    expect(gender, findsOneWidget);
    expect(phone, findsOneWidget);

    final nameRect = tester.getRect(name);
    final genderRect = tester.getRect(gender);
    final phoneRect = tester.getRect(phone);

    // 同一行 (垂直中心接近; 三栏字号一致 → 容差 4px)
    expect((genderRect.center.dy - nameRect.center.dy).abs(), lessThan(4.0),
        reason: '性别要和姓名同一行');
    expect((phoneRect.center.dy - nameRect.center.dy).abs(), lessThan(4.0),
        reason: '手机号要和姓名同一行');

    // 左→右: 姓名 | 性别 | 手机号
    expect(genderRect.left, greaterThan(nameRect.right - 1));
    expect(phoneRect.left, greaterThan(genderRect.right - 1));

    // 窄屏不溢出 (整行必须在视口内, 且没有渲染异常)
    expect(tester.takeException(), isNull, reason: '390 宽度下不能 RenderFlex overflow');
    expect(phoneRect.right, lessThanOrEqualTo(390.0));
  });

  testWidgets('② 生日标题行含「阳历 / 农历」(历法不再单独占一行)', (tester) async {
    await _pump(tester);

    final solar = find.text('阳历');
    final lunar = find.text('农历');
    expect(solar, findsOneWidget);
    expect(lunar, findsOneWidget);

    // 跟「生日」标题同一行
    final titleDy = tester.getCenter(find.text('生日')).dy;
    expect((tester.getCenter(solar).dy - titleDy).abs(), lessThan(6.0),
        reason: '历法切换应跟生日标题同一行 (省一行)');
  });

  testWidgets('③ 保存键吸底: 滚动列表时不动, 且贴视口底部', (tester) async {
    await _pump(tester, surface: const Size(390, 844));

    // FilledButton.icon 是私有子类 → 不能 byType; 用契约 key 抓
    final save = find.byKey(const ValueKey('customerFormSaveButton'));
    expect(save, findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    final before = tester.getRect(save);

    // 贴底: 按钮底边距视口底 ≤ SafeArea + padding (取 60 作宽松上限)
    expect(844 - before.bottom, lessThan(60.0),
        reason: '保存键应固定在底部');

    // 滚动列表 → 按钮位置不变 (吸底)
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    final after = tester.getRect(save);
    expect((after.top - before.top).abs(), lessThan(0.5),
        reason: '滚动时保存键不能跟着走');
  });
}
