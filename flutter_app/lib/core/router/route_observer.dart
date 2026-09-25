import 'package:flutter/widgets.dart';

/// R-10 L2 (2026-09-26): 全局路由观察者 —— 列表页用 `RouteAware.didPopNext()`
/// 在「从详情页返回」时刷新, 避免推送/撤销/改归属后列表仍显示旧行。
///
/// 为什么单独一个文件 (而不是放 app_router.dart):
///   screen → router 的反向 import 会成环 (router 也 import screens);
///   全局 observer 是两者都需要的共享常量, 放这里各自 import 即可。
///
/// 详见 docs/r9-r10-optimization.md §5.1。
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();
