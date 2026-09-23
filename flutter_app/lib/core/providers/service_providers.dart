// ============================================
// 暖客宝 Providers (Plan F2 合并版)
// 单文件包含全部 service provider
// ============================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../http/api_client.dart';
import '../services/notifications/follow_up_reminder.dart';
import '../services/api.dart';
import '../models/customer_charts.dart';
import '../models/customer_insight.dart';
import '../models/customer_ownership.dart';
import '../models/dictionaries.dart';
import '../models/wellness_record.dart';
import '../models/follow_up_info.dart';
import '../models/dashboard.dart';
import '../models/follow_up.dart';
import '../models/me.dart';
import '../models/admin_user.dart';

/// 跟进提醒 (本地通知; web = 空实现, 见 follow_up_reminder.dart 平台差异说明)
final followUpReminderProvider = Provider<FollowUpReminder>(
  (ref) => createFollowUpReminder(),
);

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

/// 客户洞察 (评分 + 行动指引; 免费层)
final customerInsightServiceProvider = Provider<CustomerInsightService>(
  (ref) => CustomerInsightService(ref.watch(dioProvider)),
);

/// 客户归属 (管理维度 P7): 谁把她当客户在管 + 能不能认领
///
/// autoDispose: 关掉详情页就释放 —— 认领后归属会变, 不该跨会话长期缓存
/// (认领成功后调用方 `ref.invalidate(customerOwnershipProvider(id))` 刷新)
final customerOwnershipProvider =
    FutureProvider.autoDispose.family<CustomerOwnership, String>(
  (ref, customerId) => ref.watch(customerServiceProvider).ownership(customerId),
);

/// 客户分析图谱 (P4; 趋势 + 部位热力)
final customerChartsServiceProvider = Provider<CustomerChartsService>(
  (ref) => CustomerChartsService(ref.watch(dioProvider)),
);

/// 「分析」Tab 的图谱数据 (autoDispose: 关掉详情页就释放)
final customerChartsProvider =
    FutureProvider.autoDispose.family<CustomerCharts, String>(
  (ref, customerId) => ref.watch(customerChartsServiceProvider).get(customerId),
);

/// 详情页 L0 的洞察数据 (family: 按客户 id 缓存)
///
/// autoDispose: 详情页关了就该释放 (分数会随数据变化, 不该长期缓存)
final customerInsightProvider =
    FutureProvider.autoDispose.family<CustomerInsight, String>(
  (ref, customerId) =>
      ref.watch(customerInsightServiceProvider).get(customerId),
);
final dictionaryServiceProvider = Provider<DictionaryService>(
  (ref) => DictionaryService(ref.watch(dioProvider)),
);

/// 全局字典 (服务项目 / 部位 / 产品) —— **各页面共用一份**
///
/// 为什么要提到 core 层 (2026-09-23, 记录页完善):
///   原来它私有在 `wellness_record_{form,detail}_page.dart` 里 (`_dictProvider`),
///   客户详情页拿不到 → 记录列表只能显示 `serviceItemId` 数字, 列不出项目名/部位。
///   字典是**全 app 共用 + 几乎不变**的静态数据, 放 core 让所有页面复用。
///
/// 不用 autoDispose: 它要在客户列表/详情/录入/明细之间反复用到,
///   每次进页面重新拉一遍是浪费 (而且字典改动极少, 缓存不会陈旧)。
///   下拉刷新如果需要强制更新, `ref.invalidate(dictionariesProvider)` 即可。
final dictionariesProvider = FutureProvider<Dictionaries>(
  (ref) async => ref.watch(dictionaryServiceProvider).all(),
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
final meServiceProvider = Provider<MeService>(
  (ref) => MeService(ref.watch(dioProvider)),
);
final systemServiceProvider = Provider<SystemService>(
  (ref) => SystemService(ref.watch(dioProvider)),
);
final billingServiceProvider = Provider<BillingService>(
  (ref) => BillingService(ref.watch(dioProvider)),
);
final adminUsersServiceProvider = Provider<AdminUsersService>(
  (ref) => AdminUsersService(ref.watch(dioProvider)),
);

final salonServiceProvider = Provider<SalonService>(
  (ref) => SalonService(ref.watch(dioProvider)),
);

// ============================================
// 「我的」页数据
// ============================================

/// 个人资料 (账号 + 加盟身份 + 门店 + 数据概览)
/// 改完资料后 `ref.invalidate(meProfileProvider)` 就能刷新
final meProfileProvider = FutureProvider<MeProfile>(
  (ref) async => ref.watch(meServiceProvider).profile(),
);

/// 服务器版本 + 安装包 (只在「检查更新」时拉, 不做自动轮询)
final appReleaseProvider = FutureProvider<AppRelease>(
  (ref) async => ref.watch(systemServiceProvider).appRelease(),
);

/// 人工收款信息 (内测通道: 收款码 + 我的申请状态)
final manualPayInfoProvider = FutureProvider.autoDispose<ManualPayInfo>(
  (ref) async => ref.watch(billingServiceProvider).manualPayInfo(),
);

/// 我推荐的人 (B1: 推荐人确认「这是我朋友」; 列表里含 pending/confirmed/rewarded/rejected)
final myReferralsProvider = FutureProvider.autoDispose<List<MyReferral>>(
  (ref) async => ref.watch(billingServiceProvider).myReferrals(),
);

/// 管理员: 付款申请列表 (按状态; 内测人工核销用)
final adminPaymentsProvider =
    FutureProvider.family.autoDispose<List<AdminPayRequest>, String>(
  (ref, status) async =>
      ref.watch(billingServiceProvider).adminManualPayments(status: status),
);

/// 网络自检 (GET /api/health, 不需要登录): autoDispose —— 每次打开"网络自检"都要拿当前状态
final healthCheckProvider = FutureProvider.autoDispose<HealthInfo>(
  (ref) async => ref.watch(systemServiceProvider).health(),
);

// ============================================
// 数据 Providers (UI 层用)
// ============================================

/// 客户列表查询参数 (搜索 + 类型筛选)
///
/// 类型筛选走后端 (`/api/customers?type=`), 判定规则: 加盟 (franchisee 派生) > 种子 (is_seed) > 普通
/// 主人 2026-09-18 拍: 客户列表胶囊按键接真过滤
class CustomerListQuery {
  final String? search;
  /// null / 'all' = 不筛; 其余 = 'franchisee' | 'seed' | 'normal'
  final String? type;
  /// 排序 (主人 2026-09-20 拍): urgency 紧急度 (**仅会员**) / recent 最近联系 / new 最近添加 / name 姓名
  final String? sort;
  const CustomerListQuery({this.search, this.type, this.sort});

  @override
  bool operator ==(Object other) =>
      other is CustomerListQuery &&
      other.search == search &&
      other.type == type &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(search, type, sort);
}

/// 客户列表 (含搜索 + 类型筛选 + 跟进信息块) - W5 RBAC 后置
/// 主人 2026-09-20: 排序以跟进紧急度为第一规则 (**紧急度仅会员**, 非会员后端降级并在 result 里标 locked)
final customersProvider =
    FutureProvider.family<CustomerListResult, CustomerListQuery>(
  (ref, query) async {
    return ref.watch(customerServiceProvider).list(
      search: query.search,
      type: query.type,
      sort: query.sort,
      limit: 50,
      offset: 0,
    );
  },
);

/// 客户类型计数 (胶囊按键上的数量) — 按 search 缓存 (family 参数 = 搜索词)
/// 注: 计数不带 type (就是四个桶的总数), 所以传的是 String? 而不是 CustomerListQuery
final customerTypeCountsProvider =
    FutureProvider.family<Map<String, int>, String?>(
  (ref, search) async {
    return ref.watch(customerServiceProvider).typeCounts(search: search);
  },
);

/// 某客户的待办跟进任务 (客户详情页用, 主人 2026-09-18)
final customerFollowUpTasksProvider =
    FutureProvider.family<List<FollowUpTask>, String>((ref, customerId) async {
  return ref
      .watch(followUpServiceProvider)
      .list(customerId: customerId, status: 'pending');
});

/// 某客户的互动记录 (客户详情页用)
final interactionsForCustomerProvider =
    FutureProvider.family<List<Interaction>, String>((ref, customerId) async {
  return ref.watch(interactionServiceProvider).list(customerId: customerId);
});

/// 客户详情
final customerDetailProvider = FutureProvider.family<dynamic, String>(
  (ref, id) async => ref.watch(customerServiceProvider).getById(id),
);

/// 客户的养生记录
///
/// 类型从 `List<dynamic>` 收紧为 `List<WellnessRecord>` (2026-09-23 记录页):
///   service.list 本来就返回 `List<WellnessRecord>`, 写成 dynamic 只是把类型检查
///   推到了调用方手写 cast —— 而记录页要在卡片上读 `preCondition['pain_level']`,
///   类型一丢就是把错误从编译期推到用户面前。
final customerWellnessRecordsProvider =
    FutureProvider.family<List<WellnessRecord>, String>(
  (ref, customerId) async {
    return ref.watch(wellnessRecordServiceProvider).list(
      customerId: customerId,
      limit: 50,
    );
  },
);

/// 加盟商列表
final franchiseesProvider = FutureProvider<List<dynamic>>(
  (ref) async => ref.watch(franchiseeServiceProvider).list(),
);

/// 我的加盟树 (Plan F3 图谱视图用)
// v0.1.3 Phase 6.5 ★ 设计决策:
// 不强制走 RelationSystem 接口 (因为 FranchiseeTreeNode 是 Franchise 特有的
// 数据形状, 不是通用 RelationNode). 节点 CRUD 走 FranchiseeService (业务具体).
// 关系操作 (addRelation/removeRelation/getNode) 走 RelationSystem 接口 (抽象通用).
//
// 切换关系系统时 (e.g. → DistributionRelationSystem):
// - add_franchisee_page / franchise_tree_page 需重做 UI (因 FranchiseeTreeNode 是 franchise 特有)
// - franchisee_detail_page (getById → getNode) 已走接口, 零改动 ✓
//
// 详见 docs/adr/0007-modular-architecture.md + 关系接口边界说明
final myFranchiseeTreeProvider = FutureProvider.family<dynamic, int>(
  (ref, depth) async {
    // mode=placement: 图谱要的是「左右两区真二叉树」+ 直推/下级引荐/上级引荐 relation
    // (referrer 推荐树看不到「上级引荐但放在我下线」的人, 见 API route 注释)
    return ref
        .watch(franchiseeServiceProvider)
        .getMyTree(depth: depth, mode: 'placement');
  },
);
/// 落位「三方确认」: 待我拍板的数量 (客户页红点用)
final placementToConfirmCountProvider = FutureProvider<int>((ref) async {
  final svc = ref.watch(franchiseeServiceProvider);
  final items = await svc.listPlacementRequests(scope: 'to_confirm');
  return items.length;
});

/// 管理员 · 用户管理总览 (全部注册用户 + 加盟节点)
///   仅 admin 可见; 页面下拉刷新 / 建根成功后 invalidate 它
final adminUsersProvider = FutureProvider.autoDispose<AdminUsersOverview>(
  (ref) async => ref.watch(adminUsersServiceProvider).overview(),
);
