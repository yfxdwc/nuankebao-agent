// 客户头像值解析单测 (跟后端 src/lib/avatar.ts 白名单同一套约定)
// 主人 2026-09-18 拍: 客户头像支持 内置候选 / 相册拍照上传 / 默认首字
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/models/customer.dart';

Customer _c({required Object? avatar}) => Customer.fromJson({
      'id': '1',
      'name': '王女士',
      'phone': '13912345678',
      'createdAt': '2026-09-01T00:00:00.000Z',
      'updatedAt': '2026-09-01T00:00:00.000Z',
      'avatar': avatar,
    });

void main() {
  test('内置候选 id 合法 → 保留', () {
    expect(_c(avatar: 'preset:leaf').avatar, 'preset:leaf');
    expect(_c(avatar: 'preset:water').avatar, 'preset:water');
  });

  test('未知候选 id → null (UI 退回首字, 不画白框)', () {
    expect(_c(avatar: 'preset:xxx').avatar, isNull);
  });

  test('本站上传路径 → 保留; 目录穿越/外链 → null', () {
    expect(_c(avatar: '/uploads/1788-abc.jpg').avatar, '/uploads/1788-abc.jpg');
    expect(_c(avatar: '/uploads/../secret.jpg').avatar, isNull);
    expect(_c(avatar: 'https://evil.com/a.jpg').avatar, isNull);
    expect(_c(avatar: 'http://x/a.png').avatar, isNull);
  });

  test('null / 空串 / 非字符串 → null', () {
    expect(_c(avatar: null).avatar, isNull);
    expect(_c(avatar: '').avatar, isNull);
    expect(_c(avatar: 123).avatar, isNull);
  });
}
