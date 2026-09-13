import 'package:flutter_test/flutter_test.dart';

import 'package:nuankebao/services/api_client.dart';

void main() {
  group('normalizeApiBaseUrl', () {
    test('带 /api 的 URL 保持不变', () {
      expect(normalizeApiBaseUrl('https://nuankebao.tooyang.top/api'),
          'https://nuankebao.tooyang.top/api');
      expect(normalizeApiBaseUrl('http://192.168.1.200:3003/api'),
          'http://192.168.1.200:3003/api');
    });

    test('只有 origin (漏了 /api) 时自动补 /api — 防止全部请求 404', () {
      expect(normalizeApiBaseUrl('https://nuankebao.tooyang.top'),
          'https://nuankebao.tooyang.top/api');
    });

    test('去掉尾部斜杠', () {
      expect(normalizeApiBaseUrl('https://nuankebao.tooyang.top/'),
          'https://nuankebao.tooyang.top/api');
      expect(normalizeApiBaseUrl('https://nuankebao.tooyang.top/api/'),
          'https://nuankebao.tooyang.top/api');
    });
  });

  group('parseAuthSetCookie', () {
    test('https 下 session cookie (__Secure- 前缀) → isSession=true', () {
      final c = parseAuthSetCookie(
          '__Secure-authjs.session-token=eyJhbGciOiJkaXIiLCJlbmMiOiJBMjU2Q0JDLUhTNTEyIn0; Path=/; HttpOnly; Secure; SameSite=Lax');
      expect(c, isNotNull);
      expect(c!.name, '__Secure-authjs.session-token');
      expect(c.value, startsWith('eyJhbGciOiJkaXIi'));
      expect(c.isSession, isTrue);
    });

    test('https 下 csrf cookie (__Host- 前缀) → isSession=false', () {
      final c = parseAuthSetCookie(
          '__Host-authjs.csrf-token=abc123%7Cdef456; Path=/; HttpOnly; Secure; SameSite=Lax');
      expect(c, isNotNull);
      expect(c!.name, '__Host-authjs.csrf-token');
      expect(c.value, 'abc123%7Cdef456');
      expect(c.isSession, isFalse);
    });

    test('http 下无前缀 cookie 也要认', () {
      expect(parseAuthSetCookie('authjs.session-token=abc; Path=/; HttpOnly')!.isSession,
          isTrue);
      expect(parseAuthSetCookie('authjs.csrf-token=xyz; Path=/')!.name,
          'authjs.csrf-token');
      expect(parseAuthSetCookie('authjs.callback-url=https%3A%2F%2Fexample.com; Path=/')
              ?.isSession,
          isFalse);
    });

    test('非 Auth.js cookie 忽略', () {
      expect(parseAuthSetCookie('sessionid=abc; Path=/'), isNull);
      expect(parseAuthSetCookie('_ga=GA1.1.123; Path=/'), isNull);
    });
  });
}
