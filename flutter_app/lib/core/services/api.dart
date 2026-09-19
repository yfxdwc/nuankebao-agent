// ============================================
// 暖客宝 API 客户端 (合并版, Plan F2)
// 替换原 8 个 service 文件 (auth / customer / wellness / misc / photo / prediction)
// 单文件 ~400 行, 易维护
// =================================

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/customer.dart';
import '../models/ai_insight.dart';
import '../models/wellness_record.dart';
import '../models/dictionaries.dart';
import '../models/follow_up.dart';
import '../models/dashboard.dart';
import '../models/franchisee.dart';
import '../models/placement_request.dart';
import '../models/me.dart';
import '../models/salon.dart';
import '../http/api_client.dart';

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

    // R12 治本方案 A: dev + web 走专用 endpoint 拿 body token (HttpOnly 绕不过)
    if (kIsWeb) {
      try {
        await _loginDevWeb(phone: phone, code: code);
        return; // dev web 登录成功, storage 有 token
      } catch (e) {
        // dev 专用 endpoint 不可用 (prod? 部署环境不同?) fallback 老 Auth.js callback
        // (老路径 web 仍会循环, 但 native / prod 仍能走)
      }
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
    // R12 治本: 拿到 session cookie 后从浏览器 document.cookie 同步 (web 平台)
    // dio onResponse 拦截器已经 set 了 (native 平台), 这里多一道兑底以防 web XHR
    // 头不可见。带后存储后 isLoggedIn() / _checkLogin() 能读到。
    await ApiClient.syncCookiesFromBrowser();
  }

  /// R12 治本方案 A: dev + web 平台走专用 endpoint 拿 body 返回的 session token
  ///
  /// Auth.js 默认 httpOnly=true, JS 读不到。dio XHR 拿不到 Set-Cookie 头。
  /// 唯一可行的路径: 后端返回 body 带 token (dev 模式 only, prod  404)。
  ///
  /// 调用后:
  ///   - storage.session_cookie_name + session_token 已写入
  ///   - 后续 dio 请求从 storage 读 token 拼 Cookie 头
  Future<void> _loginDevWeb({required String phone, required String code}) async {
    // 用 dio 调 endpoint (dio web 平台 XHR 拿不到 Set-Cookie 头, 但能读 body)
    final resp = await _dio.post('/auth/flutter-login', data: {
      'phone': phone,
      'code': code,
    }, options: Options(contentType: Headers.jsonContentType));
    if (resp.statusCode != 200 || resp.data is! Map) {
      throw Exception('登录响应格式错误');
    }
    final body = resp.data as Map;
    if (body['sessionToken'] is! String) {
      throw Exception(body['error']?.toString() ?? '登录失败');
    }
    final cookieName = (body['cookieName'] as String?) ?? 'authjs.session-token';
    final sessionToken = body['sessionToken'] as String;
    // R12 治本 (web): flutter_secure_storage 强制 AES 加密, raw token 不可注入.
    // 改存 ApiClient 内存变量. 跳 storage 路径 — 冷启动会丢, 但 dev 模式接受.
    ApiClient.setWebSession(cookieName: cookieName, token: sessionToken);
    // 另存 storage 作兜底 (native 路径仍用, web 路径优先内存变量)
    // fix-dev-web-login (2026-09-18 预览多账号时发现): storage.write 在 web 平台
    //   可能抛异常 (flutter_secure_storage 强制 AES, iframe/隐私模式常见)。
    //   以前异常会冒泡到 login() 的 try/catch → 回退调 Auth.js callback →
    //   callback 的浏览器 cookie 是 W1 mock (恒 user 1), 把 flutter-login 刚下发的
    //   正确身份 cookie 覆盖掉 → 多账号预览/联调全变成 user 1。
    //   这里把 storage 写入降级为「失败即忽略」(内存 token 已 set, cookie 已下发)。
    try {
      await ApiClient.storage.write(
          key: ApiClient.sessionCookieNameKey, value: cookieName);
      await ApiClient.storage.write(
          key: ApiClient.sessionTokenKey, value: sessionToken);
    } catch (e) {
      // ignore: avoid_print
      print('[dev-web login] storage 写入失败 (忽略, 用内存 token + cookie): $e');
    }
  }

  Future<bool> isLoggedIn() async {
    // R12 治本 (web): 优先读内存变量 (flutter_secure_storage web 强制 AES 加密,
    // 外部注入 / 冷启动拿不到). native 走 storage.
    final wsTok = ApiClient.webSessionToken;
    if (wsTok != null && wsTok.isNotEmpty) {
      // ignore: avoid_print
      print('[R12 debug] isLoggedIn: web mem token present, returning true');
      return true;
    }
    final token = await ApiClient.storage.read(key: ApiClient.sessionTokenKey);
    // ignore: avoid_print
    print('[R12 debug] isLoggedIn: storage.token.len=${token?.length ?? 0}');
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

  /// 客户列表
  /// [type] 类型筛选 (胶囊按键): null / 'all' = 不筛, 其余 = franchisee / seed / normal
  Future<List<Customer>> list({
    String? search,
    String? type,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _dio.get('/customers', queryParameters: {
      if (search != null && search.isNotEmpty) 'search': search,
      if (type != null && type.isNotEmpty && type != 'all') 'type': type,
      'limit': limit,
      'offset': offset,
    });
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Customer.fromJson).toList();
  }

  /// 客户类型计数 (胶囊上的数量, 主人 2026-09-18 拍)
  /// GET /api/customers/stats → { all, franchisee, seed, normal }
  /// 口径与 list() 一致 (同名 search); 三类互斥穷尽 → 相加 == all
  Future<Map<String, int>> typeCounts({String? search}) async {
    final res = await _dio.get('/customers/stats', queryParameters: {
      if (search != null && search.isNotEmpty) 'search': search,
    });
    final data = res.data as Map<String, dynamic>;
    return {
      'all': (data['all'] as num?)?.toInt() ?? 0,
      'franchisee': (data['franchisee'] as num?)?.toInt() ?? 0,
      'seed': (data['seed'] as num?)?.toInt() ?? 0,
      'normal': (data['normal'] as num?)?.toInt() ?? 0,
    };
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

  /// 以我为中心的加盟树 (Plan F3 图谱用)
  ///
  /// [mode]:
  ///   - `placement` (图谱默认): 二叉树 (按 placement_path 连) + 每节点 relation
  ///     (直推/下级引荐/上级引荐) — 「对碰」视图要的就是左右两区真二叉树
  ///   - `referrer`: 推荐树 (按 referrer_id 连), 无 relation 语义
  ///
  /// [depth] = 「本次取多少层」的载荷旋钮 (不是业务层级上限, ADR-0011: 层级不限)
  ///   图谱改懒加载后只请求 1-2 层, 其余点节点展开 (见 getChildren)
  Future<FranchiseeTreeNode> getMyTree({
    int depth = 2,
    String mode = 'placement',
  }) async {
    final res = await _dio.get('/franchisees/me/tree',
        queryParameters: {'depth': depth, 'mode': mode});
    return FranchiseeTreeNode.fromJson(res.data as Map<String, dynamic>);
  }

  /// 懒加载: 取某个节点的**直接子级** (ADR-0011, 主人 2026-09-18 拍「按需展开」)
  ///
  /// 层级不限后全量拉树会爆 JSON (满二叉 16 层 = 13 万节点) → 图谱先画 1-2 层,
  /// 用户点节点展开时一次只拉一级 (GET /api/franchisees/:id/children)
  Future<List<FranchiseeTreeNode>> getChildren(String nodeId) async {
    final res = await _dio.get('/franchisees/$nodeId/children');
    final items = (res.data['children'] as List?) ?? [];
    return items
        .map((e) => FranchiseeTreeNode.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ==========================================
  // 落位「三方确认」工作流 (主人 2026-09-18 拍)
  // ==========================================

  /// 发起落位/移动申请 (需要三方确认才真正生效)
  Future<PlacementRequest> createPlacementRequest({
    required String targetParentId,
    required String side,
    String? newName,
    String? newPhone,
    String? newNotes,
    String? moveFid,
    String? unjoinFid,
  }) async {
    final kind = unjoinFid != null
        ? 'unjoin'
        : (moveFid == null ? 'create' : 'move');
    final res = await _dio.post('/franchisees/placement-requests', data: {
      'kind': kind,
      'targetParentId': targetParentId,
      'side': side,
      if (newName != null) 'newName': newName,
      if (newPhone != null) 'newPhone': newPhone,
      if (newNotes != null) 'newNotes': newNotes,
      if (moveFid != null) 'moveFid': moveFid,
      if (unjoinFid != null) 'moveFid': unjoinFid,
    });
    return PlacementRequest.fromJson(res.data as Map<String, dynamic>);
  }

  /// 列表: scope=mine (我发起的) / to_confirm (等我拍板的)
  Future<List<PlacementRequest>> listPlacementRequests({
    String scope = 'mine',
    String status = 'pending',
  }) async {
    final res = await _dio.get('/franchisees/placement-requests',
        queryParameters: {'scope': scope, 'status': status});
    final items = (res.data['items'] as List?) ?? [];
    return items
        .map((e) => PlacementRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 三方之一拍板
  Future<PlacementRequest> decidePlacementRequest(
    String id, {
    required bool approve,
  }) async {
    final res = await _dio.post(
      '/franchisees/placement-requests/$id/decide',
      data: {'decision': approve ? 'approve' : 'reject'},
    );
    return PlacementRequest.fromJson(res.data as Map<String, dynamic>);
  }

  /// 发起人撤回
  Future<void> cancelPlacementRequest(String id) async {
    await _dio.post('/franchisees/placement-requests/$id/cancel');
  }

  /// admin 强删 (绕过三方确认; 仅 admin; 仍有下线会被拒)
  Future<void> forceUnjoinFranchisee(String id) async {
    await _dio.post('/franchisees/$id/force-unjoin');
  }
}

// ============================================
// AiService (AI 客户画像 + 跟进话术)
// ============================================

class AiService {
  final Dio _dio;
  AiService(this._dio);

  /// AI 客户画像 (旧接口: 只拿 content 文本)
  Future<String> profile(String customerId) async {
    final res = await _dio.get('/ai/profile/$customerId');
    return res.data['content'] as String? ?? '暂无画像';
  }

  /// AI 客户画像 (结构化: 总结 + 近期记录摘要)
  Future<CustomerProfileInsight> profileInsight(String customerId) async {
    final res = await _dio.get('/ai/profile/$customerId');
    return CustomerProfileInsight.fromJson(res.data as Map<String, dynamic>);
  }

  /// AI 跟进话术 (可选 reason = 为什么跟进)
  Future<FollowUpSuggestion> followUpInsight(
    String customerId, {
    String? reason,
  }) async {
    final res = await _dio.post('/ai/follow-up', data: {
      'customerId': customerId,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return FollowUpSuggestion.fromJson(res.data as Map<String, dynamic>);
  }

  Future<String> followUpSuggestion(Map<String, dynamic> data) async {
    final res = await _dio.post('/ai/follow-up', data: data);
    return res.data['suggestion'] as String? ?? '暂无建议';
  }

  /// 复购预测 (纯 DB 计算, 不消耗 AI 额度)
  Future<RepurchasePrediction> repurchasePrediction(String customerId) async {
    final res = await _dio.get('/ai/repurchase-prediction/$customerId');
    return RepurchasePrediction.fromJson(res.data as Map<String, dynamic>);
  }

  /// 效果分析 (多疗程趋势 + AI 总结)
  Future<EffectAnalysis> effectAnalysis(String customerId) async {
    final res = await _dio.get('/ai/effect-analysis/$customerId');
    return EffectAnalysis.fromJson(res.data as Map<String, dynamic>);
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
// MeService (「我的」页: 个人资料 + 自改资料)
// ============================================

class MeService {
  final Dio _dio;
  MeService(this._dio);

  /// GET /api/me — 账号 + 加盟身份 + 门店 + 数据概览 (一次拉完)
  Future<MeProfile> profile() async {
    final res = await _dio.get('/me');
    return MeProfile.fromJson(res.data as Map<String, dynamic>);
  }

  /// PATCH /api/me — 只改头像 (null = 恢复默认首字; 'preset:x'; '/uploads/x.jpg')
  /// 服务端有白名单 + user 表审计触发器, 客户端不做二次校验
  Future<String?> updateAvatar(String? avatarUrl) async {
    final res = await _dio.patch('/me', data: {'avatarUrl': avatarUrl});
    return (res.data as Map<String, dynamic>)['avatarUrl'] as String?;
  }

  /// PATCH /api/franchisees/{id} — 只能改自己的姓名/备注
  /// (后端 Schema 还允许 phone / isActive, 但页面不给入口: 手机号是登录账号,
  ///  停用自己会把账号锁死 —— 这两项找管理员)
  Future<void> updateMyFranchisee(
    String franchiseeId, {
    String? name,
    String? notes,
  }) async {
    await _dio.patch('/franchisees/$franchiseeId', data: {
      if (name != null) 'name': name,
      if (notes != null) 'notes': notes,
    });
  }
}

// ============================================
// SystemService (版本 / 更新 / 网络自检)
// ============================================

class SystemService {
  final Dio _dio;
  SystemService(this._dio);

  /// GET /api/app-version — 服务器版本 + 安装包元数据
  Future<AppRelease> appRelease() async {
    final res = await _dio.get('/app-version');
    return AppRelease.fromJson(res.data as Map<String, dynamic>);
  }

  /// GET /api/health — 不需要登录, 网络不通时也能告诉用户“服务器没连上”
  /// 自己计时 (dio 的 connectTimeout 是超时上限, 不是实测值)
  Future<HealthInfo> health() async {
    final sw = Stopwatch()..start();
    final res = await _dio.get('/health');
    sw.stop();
    return HealthInfo.fromJson(
      res.data as Map<String, dynamic>,
      latencyMs: sw.elapsedMilliseconds,
    );
  }
}

// ============================================
// SalonService (沙龙, v0.1.5 Phase 7)
// 三种角色: 主理人 / 会务 / 受邀者; 手机号仅主理人/会务/本人可见
// ============================================

class SalonService {
  final Dio _dio;
  SalonService(this._dio);

  /// 列表: role = organizing (我主理的) / invited (我受邀的) / all (并集)
  Future<List<Salon>> list({
    String role = 'all',
    bool includeFinished = true,
    int limit = 50,
  }) async {
    final res = await _dio.get('/salons', queryParameters: {
      'role': role,
      'includeFinished': includeFinished ? '1' : '0',
      'limit': limit,
    });
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Salon.fromJson).toList();
  }

  Future<Salon> getById(String id) async {
    final res = await _dio.get('/salons/$id');
    return Salon.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Salon> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/salons', data: data);
    return Salon.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Salon> update(String id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/salons/$id', data: data);
    return Salon.fromJson(res.data as Map<String, dynamic>);
  }

  /// 取消沙龙 (status=cancelled, 数据保留)
  Future<Salon> cancel(String id) async {
    final res = await _dio.post('/salons/$id/cancel');
    return Salon.fromJson(res.data as Map<String, dynamic>);
  }

  /// 删除沙龙 (软删, 仅草稿建议用)
  Future<void> delete(String id) async {
    await _dio.delete('/salons/$id');
  }

  // ---------- 邀请 ----------

  Future<List<SalonInvitation>> invitations(
    String salonId, {
    bool includeCancelled = false,
  }) async {
    final res = await _dio.get('/salons/$salonId/invitations', queryParameters: {
      if (includeCancelled) 'includeCancelled': '1',
    });
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(SalonInvitation.fromJson).toList();
  }

  Future<SalonInvitation> addInvitation(
    String salonId,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.post('/salons/$salonId/invitations', data: data);
    return SalonInvitation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<SalonInvitation> updateInvitation(
    String salonId,
    String invitationId,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.patch(
      '/salons/$salonId/invitations/$invitationId',
      data: data,
    );
    return SalonInvitation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> removeInvitation(String salonId, String invitationId) async {
    await _dio.delete('/salons/$salonId/invitations/$invitationId');
  }

  // ---------- RSVP ----------

  /// 受邀者回复: accepted / declined / tentative + 预计带约人数 + 留言
  Future<SalonInvitation> rsvp(
    String salonId, {
    required String status,
    int? expectedGuestCount,
    String? notes,
    Map<String, dynamic>? registrationData,
  }) async {
    final res = await _dio.post('/salons/$salonId/rsvp', data: {
      'status': status,
      if (expectedGuestCount != null) 'expectedGuestCount': expectedGuestCount,
      if (notes != null) 'notes': notes,
      if (registrationData != null) 'registrationData': registrationData,
    });
    return SalonInvitation.fromJson(res.data as Map<String, dynamic>);
  }

  // ---------- 带约任务 ----------

  Future<List<SalonQuota>> quotas(String salonId) async {
    final res = await _dio.get('/salons/$salonId/quotas');
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(SalonQuota.fromJson).toList();
  }

  /// 分配/调整 (同人已有 active 任务 → 更新)
  Future<SalonQuota> upsertQuota(
    String salonId, {
    required String assignedToUserId,
    required int quotaValue,
    String? deadlineAt,
    String? note,
  }) async {
    final res = await _dio.post('/salons/$salonId/quotas', data: {
      'assignedToUserId': assignedToUserId,
      'quotaValue': quotaValue,
      if (deadlineAt != null) 'deadlineAt': deadlineAt,
      if (note != null) 'note': note,
    });
    return SalonQuota.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> cancelQuota(String salonId, String quotaId) async {
    await _dio.delete('/salons/$salonId/quotas/$quotaId');
  }

  // ---------- 二级客人 ----------

  /// mine=true → 只看自己带来的 (受邀者默认只看自己)
  Future<List<SalonGuest>> guests(String salonId, {bool mine = false}) async {
    final res = await _dio.get('/salons/$salonId/guests', queryParameters: {
      if (mine) 'mine': '1',
    });
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(SalonGuest.fromJson).toList();
  }

  Future<SalonGuest> addGuest(String salonId, Map<String, dynamic> data) async {
    final res = await _dio.post('/salons/$salonId/guests', data: data);
    return SalonGuest.fromJson(res.data as Map<String, dynamic>);
  }

  Future<SalonGuest> updateGuest(
    String salonId,
    String guestId,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.patch('/salons/$salonId/guests/$guestId', data: data);
    return SalonGuest.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteGuest(String salonId, String guestId) async {
    await _dio.delete('/salons/$salonId/guests/$guestId');
  }

  // ---------- 动态 ----------

  Future<List<SalonActivity>> activities(String salonId) async {
    final res = await _dio.get('/salons/$salonId/activities');
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(SalonActivity.fromJson).toList();
  }

  Future<SalonActivity> addActivity(
    String salonId,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.post('/salons/$salonId/activities', data: data);
    return SalonActivity.fromJson(res.data as Map<String, dynamic>);
  }

  // ---------- 资料 ----------

  Future<List<SalonAttachment>> attachments(String salonId) async {
    final res = await _dio.get('/salons/$salonId/attachments');
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(SalonAttachment.fromJson).toList();
  }

  Future<SalonAttachment> addAttachment(
    String salonId,
    Map<String, dynamic> data,
  ) async {
    final res = await _dio.post('/salons/$salonId/attachments', data: data);
    return SalonAttachment.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> deleteAttachment(String salonId, String attachmentId) async {
    await _dio.delete('/salons/$salonId/attachments/$attachmentId');
  }

  // ---------- 聚合 (主理人/会务) ----------

  Future<SalonAggregates> aggregates(String salonId) async {
    final res = await _dio.get('/salons/$salonId/aggregates');
    return SalonAggregates.fromJson(res.data as Map<String, dynamic>);
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