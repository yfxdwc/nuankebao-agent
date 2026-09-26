// ============================================
// 会员标识单测 (主人 2026-09-21 拍)
// ============================================
// 「会员不仅在自己头像上有标识, 在别人的图谱 / 列表里也要有」
//
// 守护点:
//   1. 会员 = 金环 + 右上角 👑; 非会员 = 原样 (不画灰框, 人人带框 = 没区分度)
//   2. 客户类型角标 (右下角 🤝/🌱/👤) 与会员角标 (右上角 👑) **各占一角**, 不打架
//   3. 没有账号的节点不叠会员金边 (没有账号 = 没有会员/免费之分)
//   4. 模型层: 后端 member 字段缺失 (老后端) → 默认 false, 不崩
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/customer.dart';
import 'package:nuankebao/core/models/franchisee.dart';
import 'package:nuankebao/core/widgets/member_avatar.dart';
import 'package:nuankebao/core/widgets/typed_user_avatar.dart';
import 'package:nuankebao/modules/customer/widgets/customer_row.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
  await tester.pump();
}

Customer _customer({String name = '王女士', String type = 'normal'}) => Customer(
      id: '1',
      name: name,
      phone: '13800000000',
      customerType: type,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

void main() {
  group('MemberAvatar (账号头像三合一)', () {
    testWidgets('会员 → 画 👑 角标', (tester) async {
      await _pump(tester,
          const MemberAvatar(avatarUrl: null, name: '张三', size: 96, isMember: true));
      expect(find.text('👑'), findsOneWidget);
      expect(find.text('张'), findsOneWidget); // 头像本体还在
    });

    testWidgets('非会员 → 不画 👑 (不加灰框)', (tester) async {
      await _pump(tester,
          const MemberAvatar(avatarUrl: null, name: '张三', size: 96, isMember: false));
      expect(find.text('👑'), findsNothing);
      expect(find.text('张'), findsOneWidget);
    });

    testWidgets('没有账号的节点: 即使标了 member 也不叠会员标识', (tester) async {
      await _pump(tester,
          const MemberAvatar(avatarUrl: null, name: '李四', size: 48, isMember: true, noAccount: true));
      expect(find.text('👑'), findsNothing);
      expect(find.text('李'), findsOneWidget);
    });

    testWidgets('MemberCrown / MemberRing 可单独复用 (角标大小随头像)', (tester) async {
      await _pump(tester, const MemberCrown(avatarSize: 100));
      expect(find.text('👑'), findsOneWidget);
      final crown = tester.getSize(find.byType(MemberCrown));
      expect(crown.width, closeTo(42, 0.5)); // 0.42 * avatarSize
    });
  });

  group('TypedUserAvatar (列表头像: 类型 + 会员)', () {
    testWidgets('加盟 + 会员 → 右下角 🤝, 右上角 👑, 环是会员金 (不是加盟紫)', (tester) async {
      await _pump(tester,
          const TypedUserAvatar(
            avatarUrl: null,
            name: '赵老板',
            customerType: 'franchisee',
            size: 56,
            isMember: true,
          ));
      expect(find.text('🤝'), findsOneWidget);
      expect(find.text('👑'), findsOneWidget);
      // 金环: 找最外层 Container 的边框色
      final ring = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      expect((ring.border! as Border).top.color, kMemberGold);
    });

    testWidgets('加盟 + 非会员 → 只画 🤝 (环是加盟紫)', (tester) async {
      await _pump(tester,
          const TypedUserAvatar(
            avatarUrl: null,
            name: '赵老板',
            customerType: 'franchisee',
            size: 56,
            isMember: false,
          ));
      expect(find.text('🤝'), findsOneWidget);
      expect(find.text('👑'), findsNothing);
      final ring = tester
          .widgetList<Container>(find.byType(Container))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.border != null);
      expect((ring.border! as Border).top.color, isNot(kMemberGold));
    });

    testWidgets('小头像 (size < 40) 放不下第二个角标 → 只留金环', (tester) async {
      await _pump(tester,
          const TypedUserAvatar(
            avatarUrl: null,
            name: '王女士',
            customerType: 'normal',
            size: 32,
            isMember: true,
          ));
      expect(find.text('👑'), findsNothing);
    });

    testWidgets('无障碍: 会员头像的语义标签带上「会员」', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester,
          const TypedUserAvatar(
            avatarUrl: null,
            name: '王女士',
            customerType: 'normal',
            size: 56,
            isMember: true,
          ));
      // 读屏用户听到「王女士, 普通客户, 会员」(👑 是给眼睛看的, 文字说清楚)
      expect(find.bySemanticsLabel(RegExp('王女士.*会员')), findsOneWidget);
      handle.dispose();
    });
  });

  group('CustomerRow (客户列表行)', () {
    // 2026-09-26 v2 (主人拍): 列表行的会员标识**不再挂头像角标** (不双重编码),
    //   改为「客户名下面」的彩色图标条 → Icons.workspace_premium
    //   (头像角标仍用于其他屏 — 见本文件上方 TypedUserAvatar/MemberAvatar 用例)
    testWidgets('会员客户 → 名字下面有 Icons.workspace_premium', (tester) async {
      await _pump(tester,
          CustomerRow(customer: _customer(), isMember: true, onTap: () {}));
      expect(find.byIcon(Icons.workspace_premium), findsOneWidget);
      expect(find.text('王女士'), findsOneWidget);
      // 头像上不再有 👑 角标 (职责交给图标条)
      expect(find.text('👑'), findsNothing);
    });

    testWidgets('非会员客户 → 没有会员图标 (老后端不返回 isMember 也是这样)', (tester) async {
      await _pump(tester, CustomerRow(customer: _customer(), onTap: () {}));
      expect(find.byIcon(Icons.workspace_premium), findsNothing);
    });
  });

  group('模型层: member 字段解析', () {
    test('FranchiseeTreeNode: member=true 解析出来; 缺字段 → false', () {
      final m = FranchiseeTreeNode.fromJson({
        'id': '1',
        'name': '张三',
        'children': <dynamic>[],
        'member': true,
      });
      expect(m.member, isTrue);

      final old = FranchiseeTreeNode.fromJson({
        'id': '2',
        'name': '李四',
        'children': <dynamic>[],
      });
      expect(old.member, isFalse); // 老后端不返回 → 默认非会员
    });

    test('FranchiseeTreeNode.copyWith 保留 member (懒加载合并后标识不丢)', () {
      final m = FranchiseeTreeNode.fromJson({
        'id': '1',
        'name': '张三',
        'children': <dynamic>[],
        'member': true,
      });
      expect(m.copyWith(children: const []).member, isTrue);
    });

    test('图谱节点: member 解析 + 缺字段兜底 (原 CustomerGraphNode 已随 ADR-0015 Q4 死链路删除)', () {
      final on = FranchiseeTreeNode.fromJson(
          {'id': '1', 'name': 'a', 'children': <dynamic>[], 'member': true});
      final off = FranchiseeTreeNode.fromJson(
          {'id': '1', 'name': 'a', 'children': <dynamic>[]});
      expect(on.member, isTrue);
      expect(off.member, isFalse);
    });
  });
}
