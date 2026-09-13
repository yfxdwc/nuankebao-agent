// ============================================
// 暖客宝 API 客户端 (合并版, Plan F2)
// 替换原 8 个 service 文件 (auth / customer / wellness / misc / photo / prediction)
// 单文件 ~400 行, 易维护
// =================================

import 'package:dio/dio.dart';
import '../models/customer.dart';
import '../models/wellness_record.dart';
import '../models/dictionaries.dart';
import '../models/follow_up.dart';
import '../models/dashboard.dart';
import '../models/franchisee.dart';
import 'api_client.dart';

// ============================================
// AuthService (登录 / 登出 / 会话)
// ============================================

class AuthService {
  final Dio _dio;
  AuthService(this._dio);

  Future<void> login({required String phone, required String code}) async {
    final csrfRes = await _dio.get('/auth/csrf');
    final csrf = csrfRes.data['csrfToken'] as String?;
    if (csrf == null) {
      throw Exception('获取安全令牌失败, 请检查网络后重试');
    }

    final loginRes = await _dio.post(
      '/auth/callback/credentials',
      data: {
        'csrfToken': csrf,
        'phone': phone,
        'code': code,
        'callbackUrl': ApiClient.baseOrigin,
      },
      options: Options(
        // Auth.js OAuth2 callback 标准是 form-encoded; 也是 CORS "safe POST" (不在 preflight 范围).
        // dio 默认会把 Map<String, dynamic> + contentType=application/x-www-form-urlencoded 转成
        // url-encoded body. (dio 默认 transformRequest 见 dio/lib/src/transformer.dart)
        // 之前 dio 在 base options 硬写 Content-Type: application/json → POST 也触发 preflight,
        // 跟 GET 一样被 Next.js server OPTIONS 没 ACAO 阻断.
        // (commit 2026-09-11 第二次修, 跟 w14 错开)
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (s) => s != null && s < 400,
      ),
    );

    final ok = loginRes.statusCode == 200 || loginRes.statusCode == 302;
    if (!ok) {
      throw Exception('登录失败, 请检查验证码');
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await ApiClient.storage.read(key: ApiClient.sessionTokenKey);
    return token != null && token.isNotEmpty;
  }

  Future<void> logout() async {
    await ApiClient.storage.delete(key: ApiClient.sessionTokenKey);
    await ApiClient.storage.delete(key: ApiClient.sessionCookieNameKey);
  }
}

// ============================================
// CustomerService (C 端客户)
// ============================================

class CustomerService {
  final Dio _dio;
  CustomerService(this._dio);

  Future<List<Customer>> list({String? search, int limit = 50, int offset = 0}) async {
    final res = await _dio.get('/customers', queryParameters: {
      if (search != null && search.isNotEmpty) 'search': search,
      'limit': limit,
      'offset': offset,
    });
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Customer.fromJson).toList();
  }

  Future<Customer> getById(String id) async {
    final res = await _dio.get('/customers/$id');
    return Customer.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Customer> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/customers', data: data);
    return Customer.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Customer> update(String id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/customers/$id', data: data);
    return Customer.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _dio.delete('/customers/$id');
  }

  /// 客户推荐关系图 (客户页图谱视图数据源)
  /// 返回节点列表, 边 = referrerId -> id 由前端构建
  /// 范围: RBAC 过滤后的客户池 (sales=自己, manager=本店, admin=全网)
  Future<CustomerGraph> getReferralGraph() async {
    final res = await _dio.get('/customers/graph');
    return CustomerGraph.fromJson(res.data as Map<String, dynamic>);
  }
}

// ============================================
// WellnessRecordService (养生记录)
// ============================================

class WellnessRecordService {
  final Dio _dio;
  WellnessRecordService(this._dio);

  Future<List<WellnessRecord>> list({String? customerId, int limit = 50}) async {
    final res = await _dio.get('/wellness-records', queryParameters: {
      if (customerId != null) 'customerId': customerId,
      'limit': limit,
    });
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(WellnessRecord.fromJson).toList();
  }

  Future<WellnessRecord> getById(String id) async {
    final res = await _dio.get('/wellness-records/$id');
    return WellnessRecord.fromJson(res.data as Map<String, dynamic>);
  }

  Future<WellnessRecord> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/wellness-records', data: data);
    return WellnessRecord.fromJson(res.data as Map<String, dynamic>);
  }

  Future<WellnessRecord> update(String id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/wellness-records/$id', data: data);
    return WellnessRecord.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _dio.delete('/wellness-records/$id');
  }
}

// ============================================
// DictionaryService (字典表)
// ============================================

class DictionaryService {
  final Dio _dio;
  DictionaryService(this._dio);

  Future<Dictionaries> all() async {
    final res = await _dio.get('/dictionaries');
    return Dictionaries.fromJson(res.data as Map<String, dynamic>);
  }
}

// ============================================
// FollowUpService (跟进任务)
// ============================================

class FollowUpService {
  final Dio _dio;
  FollowUpService(this._dio);

  Future<List<FollowUpTask>> list({String? customerId, String status = 'pending'}) async {
    final res = await _dio.get('/follow-ups', queryParameters: {
      if (customerId != null) 'customerId': customerId,
      'status': status,
    });
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(FollowUpTask.fromJson).toList();
  }

  Future<FollowUpTask> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/follow-ups', data: data);
    return FollowUpTask.fromJson(res.data as Map<String, dynamic>);
  }

  Future<FollowUpTask> complete(String id, {String? notes}) async {
    final res = await _dio.patch('/follow-ups/$id', data: {
      'status': 'done',
      if (notes != null) 'completedNotes': notes,
    });
    return FollowUpTask.fromJson(res.data as Map<String, dynamic>);
  }

  Future<FollowUpTask> cancel(String id) async {
    final res = await _dio.patch('/follow-ups/$id', data: {'status': 'cancelled'});
    return FollowUpTask.fromJson(res.data as Map<String, dynamic>);
  }
}

// ============================================
// InteractionService (联系记录)
// ============================================

class InteractionService {
  final Dio _dio;
  InteractionService(this._dio);

  Future<List<Interaction>> list({String? customerId}) async {
    final res = await _dio.get('/interactions', queryParameters: {
      if (customerId != null) 'customerId': customerId,
    });
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Interaction.fromJson).toList();
  }

  Future<Interaction> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/interactions', data: data);
    return Interaction.fromJson(res.data as Map<String, dynamic>);
  }
}

// ============================================
// FranchiseeService (Plan F1 + F2)
// 边界: 纯展示, 不算钱 (ADR-0006)
// ============================================

class FranchiseeService {
  final Dio _dio;
  FranchiseeService(this._dio);

  /// 列表
  /// scope = 'mine_downline' | 'mine_referrer' | 'all'
  Future<List<Franchisee>> list({
    String scope = 'all',
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _dio.get('/franchisees', queryParameters: {
      'scope': scope,
      if (search != null && search.isNotEmpty) 'search': search,
      'limit': limit,
      'offset': offset,
    });
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Franchisee.fromJson).toList();
  }

  Future<Franchisee> getById(String id) async {
    final res = await _dio.get('/franchisees/$id');
    return Franchisee.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Franchisee> create(CreateFranchiseeInput input) async {
    final res = await _dio.post('/franchisees', data: input.toJson());
    return Franchisee.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Franchisee> update(String id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/franchisees/$id', data: data);
    return Franchisee.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _dio.delete('/franchisees/$id');
  }

  /// 可用位置预览 (frontend UI 展示用)
  Future<AvailablePosition> getAvailablePosition(String referrerId) async {
    final res = await _dio.get('/franchisees/me/available-position',
        queryParameters: {'referrerId': referrerId});
    return AvailablePosition.fromJson(res.data as Map<String, dynamic>);
  }

  /// 以我为中心的二叉树 (Plan F3 用)
  Future<FranchiseeTreeNode> getMyTree({int depth = 3}) async {
    final res = await _dio.get('/franchisees/me/tree',
        queryParameters: {'depth': depth});
    return FranchiseeTreeNode.fromJson(res.data as Map<String, dynamic>);
  }
}

// ============================================
// AiService (AI 客户画像 + 跟进话术)
// ============================================

class AiService {
  final Dio _dio;
  AiService(this._dio);

  Future<String> profile(String customerId) async {
    final res = await _dio.get('/ai/profile/$customerId');
    return res.data['content'] as String? ?? '暂无画像';
  }

  Future<String> followUpSuggestion(Map<String, dynamic> data) async {
    final res = await _dio.post('/ai/follow-up', data: data);
    return res.data['suggestion'] as String? ?? '暂无建议';
  }
}

// ============================================
// DashboardService (轻量数据, "我的" 页用)
// ============================================

class DashboardService {
  final Dio _dio;
  DashboardService(this._dio);

  Future<DashboardStats> stats() async {
    final res = await _dio.get('/dashboard/stats');
    return DashboardStats.fromJson(res.data as Map<String, dynamic>);
  }
}

// ============================================
// PhotoService (上传照片 base64 → URL)
// ============================================

class PhotoService {
  final Dio _dio;
  PhotoService(this._dio);

  Future<String> upload(String base64Data, {String? mimeType}) async {
    final res = await _dio.post('/photos', data: {
      'base64': base64Data,
      if (mimeType != null) 'mimeType': mimeType,
    });
    return (res.data as Map<String, dynamic>)['url'] as String;
  }
}