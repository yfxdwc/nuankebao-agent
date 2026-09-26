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

import 'package:dio/dio.dart';
import 'package:nuankebao/core/models/customer.dart';
import 'package:nuankebao/core/providers/service_providers.dart';
import 'package:nuankebao/core/services/api.dart';
import 'package:nuankebao/core/theme/app_theme.dart';
import 'package:nuankebao/modules/customer/screens/customer_form_page.dart';

/// 编辑模式要 getById (表单 initState 就会拉档案)
class _FakeCustomerService extends CustomerService {
  _FakeCustomerService() : super(Dio());

  @override
  Future<Customer> getById(String id) async => Customer(
        id: id,
        name: '演示-蒋金娣',
        phone: '13800001111',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
}

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
    // ⚠ 表单现在有 **两个** DropdownButtonFormField: 性别 (本行) + 客户来源 (Phase C 新增, 在生日前)
    //   → 取 .first = 性别 (布局上第一个), 本用例只关心第一行
    final gender = find.byType(DropdownButtonFormField<String>).first;
    final phone = find.widgetWithText(TextFormField, '手机号 *');

    expect(name, findsOneWidget);
    expect(gender, findsOneWidget);
    expect(phone, findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2),
        reason: '性别 + 客户来源 = 2 个下拉');

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

  testWidgets('④-a 新建: **没有**「🌱 种子客户」模块 (2026-09-25 D3 种子退出类型轴), 但有「客户来源」',
      (tester) async {
    // ⚠ 视口调高: 这些模块在表单靠下, 默认 600 高时 ListView 还没构建到它
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pump(tester);
    // 种子已退出客户类型轴 (主人 D3): 新建页也不再出现
    expect(find.textContaining('种子客户'), findsNothing);
    // 取而代之的是 Phase C 新增的「客户来源」(§1 维度 6, D6)
    expect(find.textContaining('客户来源'), findsOneWidget);
  });

  testWidgets('④-b 编辑: 没有「种子客户」模块 (客户类型去管理 Tab 改)',
      (tester) async {
    // 主人 2026-09-25: 「编辑客户页中不需要这个模块」
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        customerServiceProvider.overrideWithValue(_FakeCustomerService()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const CustomerFormPage(customerId: '1'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('种子客户'), findsNothing,
        reason: '编辑页不该再有这个重复模块');
    // 顺带: 编辑模式该有的东西还在
    expect(find.text('保存修改'), findsOneWidget);
    expect(find.textContaining('推荐码'), findsNothing,
        reason: '推荐码本来就只在新建时出现');
  });

}
