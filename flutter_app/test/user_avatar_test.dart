// 头像组件单测 (8 个候选 + 默认首字 + 脏值兜底)
//
// 为什么单独一个文件: 「我的」页整页测试要编译整仓图 (含客户/图谱/路由), 慢且容易被
// 别的并发改动连坐; 头像组件本身只需要 material + cached_network_image
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/widgets/user_avatar.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: Center(child: child)),
  ));
  await tester.pump();
}

void main() {
  testWidgets('8 个候选头像都画得出来 (图标 + 配色, 不用联网)', (tester) async {
    expect(kAvatarPresets.length, 8);
    for (final preset in kAvatarPresets) {
      await _pump(
        tester,
        UserAvatar(avatarUrl: 'preset:${preset.id}', name: '张三', size: 96),
      );
      expect(
        find.byIcon(preset.icon),
        findsOneWidget,
        reason: '候选「${preset.label}」(${preset.id}) 应该画出 ${preset.icon}',
      );
      // 候选头像不该出现首字 (说明没走默认分支)
      expect(find.text('张'), findsNothing);
    }
  });

  testWidgets('没设头像 → 默认: 姓名首字', (tester) async {
    await _pump(tester, const UserAvatar(avatarUrl: null, name: '王女士', size: 96));
    expect(find.text('王'), findsOneWidget);
  });

  testWidgets('姓名为空 → 也不留白 (画「我」)', (tester) async {
    await _pump(tester, const UserAvatar(avatarUrl: null, name: '', size: 96));
    expect(find.text('我'), findsOneWidget);
  });

  testWidgets('脏值 / 未知候选 / 外链 → 一律退回首字 (绝不白框)', (tester) async {
    for (final bad in [
      'preset:hacker',
      'https://evil.example.com/a.png',
      '/uploads/../../etc/passwd.jpg',
      'garbage',
    ]) {
      await _pump(tester, UserAvatar(avatarUrl: bad, name: '李四', size: 96));
      expect(find.text('李'), findsOneWidget, reason: '脏值 $bad 应退回首字');
    }
  });

  testWidgets('上传路径 → 交给 CachedNetworkImage, 加载不出来时退回首字', (tester) async {
    // widget 测试里没有网络 (也不该有): 断言它至少不崩、最终显示首字兜底
    await _pump(
      tester,
      const UserAvatar(avatarUrl: '/uploads/abc123.jpg', name: '赵六', size: 96),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(find.text('赵'), findsOneWidget);
  });

  group('取值辅助', () {
    test('presetOf: 只认白名单里的 id', () {
      expect(presetOf('preset:leaf')?.id, 'leaf');
      expect(presetOf('preset:hacker'), isNull);
      expect(presetOf(null), isNull);
      expect(presetOf('/uploads/a.jpg'), isNull);
    });

    test('absoluteAvatarUrl: 只给本站上传路径拼 origin', () {
      final abs = absoluteAvatarUrl('/uploads/a.jpg');
      expect(abs, isNotNull);
      expect(abs!.endsWith('/uploads/a.jpg'), isTrue);
      expect(absoluteAvatarUrl('preset:leaf'), isNull);
      expect(absoluteAvatarUrl('https://evil/a.png'), isNull);
    });
  });
}
