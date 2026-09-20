// 路由鉴权门单测 (2026-09-21 bug: 点「去注册」没反应)
//
// 根因: 新增 /register 路由时漏把它加进"公开路由白名单" → redirect 把未登录用户
//       从 /register 又踢回 /login。
// 这组测试锁住三件事:
//   ① 未登录能访问 /login 和 /register (公开页)
//   ② 未登录访问其他页面 → 踢回 /login
//   ③ 已登录访问公开页 → 回客户页
import 'package:flutter_test/flutter_test.dart';
import 'package:nuankebao/core/router/app_router.dart';

void main() {
  group('未登录 (去登录页的路上)', () {
    test('/login 放行', () {
      expect(resolveAuthRedirect(isLoggedIn: false, location: '/login'), isNull);
    });

    test('/register 放行 (★ 本组回归: 曾经被踢回登录页)', () {
      expect(resolveAuthRedirect(isLoggedIn: false, location: '/register'), isNull);
    });

    test('业务页一律踢回登录页', () {
      for (final loc in ['/customers', '/profile', '/profile/about', '/franchise-tree']) {
        expect(
          resolveAuthRedirect(isLoggedIn: false, location: loc),
          '/login',
          reason: '$loc 未登录时应跳 /login',
        );
      }
    });
  });

  group('已登录', () {
    test('访问登录/注册页 → 回客户页 (不需要再登录)', () {
      expect(resolveAuthRedirect(isLoggedIn: true, location: '/login'), '/customers');
      expect(resolveAuthRedirect(isLoggedIn: true, location: '/register'), '/customers');
    });

    test('业务页放行', () {
      for (final loc in ['/customers', '/profile', '/profile/referrals']) {
        expect(resolveAuthRedirect(isLoggedIn: true, location: loc), isNull);
      }
    });
  });

  test('公开路由白名单: 登录 + 注册 (新增公开页必须同时改这里 + 本测试)', () {
    expect(kPublicRoutes, {'/login', '/register'});
  });
}
