// 登录态工具单测 (JWT 到期解析 + 人话文案)
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/http/session_token.dart';

/// 造一个 JWS 形状的 token (只有 payload 是 base64, 不验签)
String fakeJws({int? expSeconds}) {
  String b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${b64({'alg': 'HS256'})}.${b64({'sub': '1', if (expSeconds != null) 'exp': expSeconds})}.sig';
}

void main() {
  test('JWS (3 段): 能解出 exp', () {
    final exp = DateTime.now().add(const Duration(days: 3650));
    final token = fakeJws(expSeconds: exp.millisecondsSinceEpoch ~/ 1000);
    final got = sessionExpiry(token);
    expect(got, isNotNull);
    expect(got!.year, exp.year);
    expect(sessionTokenSegments(token), 3);
  });

  test('JWE (5 段, Auth.js 默认加密): 解不开 → null, 不报错', () {
    const jwe = 'eyJhbGciOiJkaXIiLCJlbmMiOiJBMjU2Q0JDLUhTNTEyIn0..abc.def.ghi';
    expect(sessionExpiry(jwe), isNull);
    expect(sessionTokenSegments(jwe), 5);
    // 拿不到 exp 时**不敢下结论**说"过期了" (交给服务端判)
    expect(isSessionDefinitelyExpired(jwe), isFalse);
  });

  test('脏数据 / 空值: 一律 null + 不当成过期', () {
    for (final bad in [null, '', 'garbage', 'a.b', 'a.b.c.d.e.f']) {
      expect(sessionExpiry(bad), isNull);
      expect(isSessionDefinitelyExpired(bad), isFalse);
    }
  });

  test('isSessionDefinitelyExpired: 过期=true / 未过期=false', () {
    final past = DateTime.now().subtract(const Duration(days: 1));
    final future = DateTime.now().add(const Duration(days: 1));
    expect(
      isSessionDefinitelyExpired(fakeJws(expSeconds: past.millisecondsSinceEpoch ~/ 1000)),
      isTrue,
    );
    expect(
      isSessionDefinitelyExpired(fakeJws(expSeconds: future.millisecondsSinceEpoch ~/ 1000)),
      isFalse,
    );
  });

  test('文案: 长期有效 / 剩余天数 / 已过期 三种说法', () {
    final longTerm = fakeJws(
      expSeconds: DateTime.now().add(const Duration(days: 3000)).millisecondsSinceEpoch ~/ 1000,
    );
    expect(sessionExpiryLabel(longTerm), contains('无需重复登录'));

    // 5 天整 会因为"秒截断 + inDays 向下取整"显示成 4 天 —— 这是**故意的保守值**
    // (宁可少说一天, 不承诺多余时间)
    final shortTerm = fakeJws(
      expSeconds: DateTime.now().add(const Duration(days: 5)).millisecondsSinceEpoch ~/ 1000,
    );
    expect(sessionExpiryLabel(shortTerm), matches(RegExp(r'还有 [45] 天')));

    final expired = fakeJws(
      expSeconds: DateTime.now().subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/ 1000,
    );
    expect(sessionExpiryLabel(expired), contains('已过期'));

    // JWE: 说实话"由服务器校验", 不瞎猜
    expect(sessionExpiryLabel('a.b.c.d.e'), contains('服务器校验'));
    expect(sessionExpiryLabel(null), contains('服务器校验'));
  });
}
