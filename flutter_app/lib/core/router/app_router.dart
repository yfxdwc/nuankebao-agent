// ============================================
// 暖客宝 路由 (Plan F2 极简版 + v0.1.5 沙龙)
// - 3 tab: 客户 / 沙龙 / 我的
// - 删 5 旧 tab (dashboard / wellness / follow-ups / interactions / ai / reports)
// - 加 /franchise-tree (Plan F3 接续)
// - 沙龙 (v0.1.5 Phase 7): /salons + /salons/:id + new/edit/manage/guests
// - 所有录入 (养生/联系/跟进) 必须从客户详情"+"进入
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../../modules/auth/screens/login_screen.dart';
import '../../modules/customer/screens/customers_page.dart';
import '../../modules/relation/screens/franchisee_detail_page.dart';
import '../../modules/relation/screens/add_franchisee_page.dart';
import '../../modules/relation/screens/edit_franchisee_page.dart';
import '../../modules/relation/screens/placement_requests_page.dart';
import '../../screens/about_page.dart';
import '../../screens/admin_tools_page.dart';
import '../../screens/profile_page.dart';
import '../../modules/wellness/screens/wellness_record_form_page.dart';
import '../../modules/wellness/screens/wellness_record_detail_page.dart';
import '../../modules/salon/screens/salon_list_page.dart';
import '../../modules/salon/screens/salon_detail_page.dart';
import '../../modules/salon/screens/salon_form_page.dart';
import '../../modules/salon/screens/salon_manage_page.dart';
import '../../modules/salon/screens/salon_guests_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    // fix-route (2026-09-17): 未知路由兜底 — 以前直接抛 GoException 红屏,
    // 现在给一个「页面不存在 + 回客户页」的友好页 (缺路由时不再吓到主人/销售)
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('页面不存在'), toolbarHeight: 64),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.explore_off_outlined,
                size: 56,
                color: Color(0xFF4A4A4A),
              ),
              const SizedBox(height: 12),
              Text(
                '找不到这个页面\n${state.uri}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: Color(0xFF4A4A4A)),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => context.go('/customers'),
                icon: const Icon(Icons.home_outlined, size: 22),
                label: const Text('回客户页', style: TextStyle(fontSize: 18)),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(200, 56),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
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

      // ============================================
      // 静态 "new" 路由 —— 必须声明在 ShellRoute (含 :id 动态子路由) 之前!
      // fix-router-order (2026-09-18 主人预览时发现): go_router 按声明顺序匹配,
      //   若 ShellRoute 在前, `/customers/new` / `/salons/new` 会被子路由 `:id` 吃掉
      //   (当成 id='new' 去拉详情 → 404 → 详情页错误态)。同理 `/franchisees/new`
      //   会被前面声明的 `/franchisees/:id` 吃掉。
      //   验证: 预览页 hash 直达 #/salons/new 与 #/customers/new 均应出表单。
      // ============================================
      GoRoute(
        path: '/salons/new',
        name: 'salon-new',
        builder: (context, state) => const SalonFormPage(),
      ),
      GoRoute(
        path: '/customers/new',
        name: 'customer-new',
        builder: (context, state) => const CustomerFormPage(),
      ),
      // 落位「三方确认」待办 (主人 2026-09-18 拍)
      GoRoute(
        path: '/franchisees/placement-requests',
        name: 'franchisee-placement-requests',
        builder: (context, state) => const PlacementRequestsPage(),
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
          // Tab 1: 沙龙 (v0.1.5 Phase 7)
          GoRoute(
            path: '/salons',
            name: 'salons',
            builder: (context, state) => const SalonListPage(),
            routes: [
              GoRoute(
                path: ':id',
                name: 'salon-detail',
                builder: (context, state) => SalonDetailPage(
                  salonId: state.pathParameters['id']!,
                ),
              ),
            ],
          ),
          // Tab 2: 我的
          GoRoute(
            path: '/profile',
            name: 'profile',
            builder: (context, state) => const ProfilePage(),
            routes: [
              // 关于与帮助 (使用帮助 / 数据安全说明) — 子路由, 保持 /profile 返回栈
              GoRoute(
                path: 'about',
                name: 'profile-about',
                builder: (context, state) => const AboutPage(),
              ),
              // 管理员工具 (内测人工收款核销; 入口只对 admin 显示, 服务端也会 403)
              GoRoute(
                path: 'admin',
                name: 'profile-admin',
                builder: (context, state) => const AdminToolsPage(),
              ),
            ],
          ),
        ],
      ),

      // 沙龙独立路由 (全屏, 不在 bottom nav 内)
      // 注: /salons/new 已上提到 ShellRoute 之前 (见顶部 fix-router-order)
      GoRoute(
        path: '/salons/:id/edit',
        name: 'salon-edit',
        builder: (context, state) => SalonFormPage(
          salonId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: '/salons/:id/manage',
        name: 'salon-manage',
        builder: (context, state) => SalonManagePage(
          salonId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/salons/:id/guests',
        name: 'salon-guests',
        builder: (context, state) => SalonGuestsPage(
          salonId: state.pathParameters['id']!,
        ),
      ),

      // 独立路由 (不在 shell 内, 全屏)
      // 注: /customers/new 已上提到 ShellRoute 之前 (见顶部 fix-router-order)
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
      // 编辑加盟商 (只改 姓名/手机号/备注/启用; 推荐人+位置 建树后不可改)
      // fix-route (2026-09-17 主人报: GoException no routes for /franchisees/81/edit)
      GoRoute(
        path: '/franchisees/:id/edit',
        name: 'franchisee-edit',
        builder: (context, state) => EditFranchiseePage(
          franchiseeId: state.pathParameters['id']!,
        ),
      ),
      // 注: /franchisees/new 已上提到最前 (见顶部 fix-router-order)

      // 我的加盟网络 (图谱视图, Plan F3 已实施)
      // v0.1.4: 重定向到 /customers?view=graph (客户页的"图谱"tab 画的是
      //   加盟客户的 2 线图谱, /franchise-tree 路由保留 redirect 兼容老入口)
      //   模块状态: modules/relation/ screens/franchise_tree_page.dart 标记
      //   为 deprecated, 1 周观察期后主人 review 删除.
      //   拍板: 2026-09-16 ask_user domain_split=reuse_franchisee
      //                       franchise_tree_page=redirect_to_customer
      GoRoute(
        path: '/franchise-tree',
        name: 'franchise-tree',
        redirect: (context, state) => '/customers?view=graph',
      ),
    ],
  );
});

// ============================================
// 主导航外壳 (Bottom Navigation 3 tab: 客户 / 沙龙 / 我的)
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
              context.go('/salons');
              break;
            case 2:
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
            icon: Icon(Icons.event_outlined, size: 28),
            selectedIcon: Icon(Icons.event, size: 28),
            label: '沙龙',
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
    if (location.startsWith('/salons')) return 1;
    if (location.startsWith('/profile')) return 2;
    return 0;
  }
}

// ============================================
// Placeholder screens (全部已实施, 无 placeholder)
// ============================================