// ============================================
// 暖客宝 Providers (Plan F2 合并版)
// 单文件包含全部 service provider
// ============================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../http/api_client.dart';
import '../services/api.dart';
import '../models/customer.dart';
import '../models/dashboard.dart';

/// 全局 ApiClient 单例
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient.create();
});

/// Dio (供各 service 用)
final dioProvider = Provider((ref) => ref.watch(apiClientProvider).dio);

// ============================================
// Services (合并自 8 个旧 service 文件)
// ============================================

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(dioProvider)),
);
final customerServiceProvider = Provider<CustomerService>(
  (ref) => CustomerService(ref.watch(dioProvider)),
);
final wellnessRecordServiceProvider = Provider<WellnessRecordService>(
  (ref) => WellnessRecordService(ref.watch(dioProvider)),
);
final dictionaryServiceProvider = Provider<DictionaryService>(
  (ref) => DictionaryService(ref.watch(dioProvider)),
);
final followUpServiceProvider = Provider<FollowUpService>(
  (ref) => FollowUpService(ref.watch(dioProvider)),
);
final interactionServiceProvider = Provider<InteractionService>(
  (ref) => InteractionService(ref.watch(dioProvider)),
);
final franchiseeServiceProvider = Provider<FranchiseeService>(
  (ref) => FranchiseeService(ref.watch(dioProvider)),
);
final aiServiceProvider = Provider<AiService>(
  (ref) => AiService(ref.watch(dioProvider)),
);
final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  final svc = DashboardService(ref.watch(dioProvider));
  return svc.stats();
});
final photoServiceProvider = Provider<PhotoService>(
  (ref) => PhotoService(ref.watch(dioProvider)),
);

// ============================================
// 数据 Providers (UI 层用)
// ============================================

/// 客户列表 (含搜索) - W5 RBAC 后置
final customersProvider = FutureProvider.family<List<dynamic>, String?>(
  (ref, search) async {
    return ref.watch(customerServiceProvider).list(
      search: search,
      limit: 50,
      offset: 0,
    );
  },
);

class _CustomerQuery {
  final String? search;
  const _CustomerQuery({this.search});

  @override
  bool operator ==(Object other) =>
      other is _CustomerQuery && other.search == search;

  @override
  int get hashCode => search?.hashCode ?? 0;
}

/// 客户详情
final customerDetailProvider = FutureProvider.family<dynamic, String>(
  (ref, id) async => ref.watch(customerServiceProvider).getById(id),
);

/// 客户的养生记录
final customerWellnessRecordsProvider =
    FutureProvider.family<List<dynamic>, String>(
  (ref, customerId) async {
    return ref.watch(wellnessRecordServiceProvider).list(
      customerId: customerId,
      limit: 50,
    );
  },
);

/// 我的客户推荐关系图 (客户页图谱视图用)
/// 边界: RBAC 过滤后的客户池, sales 只看自己
final myCustomerGraphProvider = FutureProvider<CustomerGraph>(
  (ref) async => ref.watch(customerServiceProvider).getReferralGraph(),
);

/// 加盟商列表
final franchiseesProvider = FutureProvider<List<dynamic>>(
  (ref) async => ref.watch(franchiseeServiceProvider).list(),
);

/// 我的加盟树 (Plan F3 图谱视图用)
final myFranchiseeTreeProvider = FutureProvider.family<dynamic, int>(
  (ref, depth) async {
    return ref.watch(franchiseeServiceProvider).getMyTree(depth: depth);
  },
);