// ============================================
// 路由 observer → screen_view 自动埋点
//
// 接在 GoRouter(observers: [...]) 上, 全路由自动覆盖 (不用逐页手写)
// 只上报路由模板 (数字段归一 :id), 不含 query / 客户姓名等内容
// ============================================

import 'package:flutter/widgets.dart';

import 'usage_service.dart';

class UsageNavigatorObserver extends NavigatorObserver {
  final UsageService service;
  UsageNavigatorObserver(this.service);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _track(route);
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // pop 后回到 previousRoute → 记为一次返回访问
    _track(previousRoute);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _track(newRoute);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  void _track(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty || !name.startsWith('/')) return;
    service.screenView(name);
  }
}
