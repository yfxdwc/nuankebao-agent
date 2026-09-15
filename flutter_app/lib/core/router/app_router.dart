// ============================================
// 暖客宝 路由 (Plan F2 极简版)
// - 2 tab: 客户 / 我的
// - 删 5 旧 tab (dashboard / wellness / follow-ups / interactions / ai / reports)
// - 加 /franchise-tree (Plan F3 接续)
// - 所有录入 (养生/联系/跟进) 必须从客户详情"+"进入
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../../modules/auth/screens/login_screen.dart';
import '../../modules/customer/screens/customers_page.dart';
import '../../modules/relation/screens/franchise_tree_page.dart';
import '../../modules/relation/screens/franchisee_detail_page.dart';
import '../../modules/relation/screens/add_franchisee_page.dart';
import '../../screens/profile_page.dart';
import '../../modules/wellness/screens/wellness_record_form_page.dart';
import '../../modules/wellness/screens/wellness_record_detail_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final isLoggedIn = authState.isLoggedIn;
      final isLoginRoute = state.matchedLocation == '/login';

      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/customers';
      return null;
    },
    routes: [
      // 登录
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),

      // 主导航 (Bottom Nav 2 tab)
      ShellRoute(
        builder: (context, state, child) => _MainShell(child: child),
        routes: [
          // Tab 0: 客户 (默认入口)
          GoRoute(
            path: '/customers',
            name: 'customers',
            builder: (context, state) => const CustomersListPage(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'customer-detail',
                builder: (context, state) => CustomerDetailPage(
                  customerId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          // Tab 1: 我的
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfilePage(),
          ),
        ],
      ),

      // 独立路由 (不在 shell 内, 全屏)
      GoRoute(
        path: '/customers/new',
        name: 'customer-new',
        builder: (context, state) => const CustomerFormPage(),
      ),
      GoRoute(
        path: '/customers/:id/edit',
        name: 'customer-edit',
        builder: (context, state) => CustomerFormPage(
          customerId: state.pathParameters['id'],
        ),
      ),

      // 养生录入 (强绑 customerId, 来自"+"弹窗)
      GoRoute(
        path: '/wellness-records/new',
        name: 'wellness-record-new',
        builder: (context, state) {
          final customerId = state.uri.queryParameters['customerId'];
          if (customerId == null || customerId.isEmpty) {
            // 强约束: 必须从客户详情进入
            return Scaffold(
              appBar: AppBar(title: const Text('错误'), toolbarHeight: 64),
              body: const Center(
                child: Text('请从客户详情页"添加记录"进入', style: TextStyle(fontSize: 18)),
              ),
            );
          }
          return WellnessRecordFormPage(customerId: customerId);
        },
      ),
      GoRoute(
        path: '/wellness-records/:id',
        name: 'wellness-record-detail',
        builder: (context, state) => WellnessRecordDetailPage(
          recordId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/wellness-records/:id/edit',
        name: 'wellness-record-edit',
        builder: (context, state) => WellnessRecordFormPage(
          recordId: state.pathParameters['id'],
        ),
      ),

      // 加盟商详情 (F3.5)
      GoRoute(
        path: '/franchisees/:id',
        name: 'franchisee-detail',
        builder: (context, state) => FranchiseeDetailPage(
          franchiseeId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/franchisees/new',
        name: 'franchisee-new',
        builder: (context, state) {
          final parentId = state.uri.queryParameters['parentId'];
          final sideHint = state.uri.queryParameters['sideHint'];
          return AddFranchiseePage(
            parentId: parentId,
            sideHint: sideHint,
          );
        },
      ),

      // 我的加盟网络 (图谱视图, Plan F3 已实施)
      GoRoute(
        path: '/franchise-tree',
        name: 'franchise-tree',
        builder: (context, state) => const FranchiseTreePage(),
      ),
    ],
  );
});

// ============================================
// 主导航外壳 (Bottom Navigation 2 tab)
// ============================================

class _MainShell extends StatelessWidget {
  final Widget child;
  const _MainShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final selectedIndex = _getIndex(location);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/customers');
              break;
            case 1:
              context.go('/profile');
              break;
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline, size: 28),
            selectedIcon: Icon(Icons.people, size: 28),
            label: '客户',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline, size: 28),
            selectedIcon: Icon(Icons.person, size: 28),
            label: '我的',
          ),
        ],
      ),
    );
  }

  int _getIndex(String location) {
    if (location.startsWith('/customers')) return 0;
    if (location.startsWith('/profile')) return 1;
    return 0;
  }
}

// ============================================
// Placeholder screens (全部已实施, 无 placeholder)
// ============================================