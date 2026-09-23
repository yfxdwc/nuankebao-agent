// ============================================
// 暖客宝 API 客户端 (合并版, Plan F2)
// 替换原 8 个 service 文件 (auth / customer / wellness / misc / photo / prediction)
// 单文件 ~400 行, 易维护
// =================================

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/customer_charts.dart';
import '../models/customer_insight.dart';
import '../models/customer.dart';
import '../models/customer_ownership.dart';
import '../models/follow_up_info.dart';
import '../models/ai_insight.dart';
import '../models/wellness_record.dart';
import '../models/dictionaries.dart';
import '../models/follow_up.dart';
import '../models/dashboard.dart';
import '../models/franchisee.dart';
import '../models/placement_request.dart';
import '../models/me.dart';
import '../models/admin_user.dart';
import '../models/salon.dart';
import '../http/api_client.dart';

// ============================================
// AuthService (登录 / 登出 / 会话)
// ============================================

class AuthService {
  final Dio _dio;
  AuthService(this._dio);

  /// 账号密码登录 (2026-09-19 P2)
  /// [identifier] 登录名 (如 admin) 或 手机号; [password] 密码
  Future<void> login({required String identifier, required String password}) async {
    final csrfRes = await _dio.get('/auth/csrf');
    final csrf = csrfRes.data['csrfToken'] as String?;
    if (csrf == null) {
      throw Exception('获取安全令牌失败, 请检查网络后重试');
    }

    // R12 治本方案 A: dev + web 走专用 endpoint 拿 body token (HttpOnly 绕不过)
    if (kIsWeb) {
      try {
        await _loginDevWeb(identifier: identifier, password: password);
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
        'identifier': identifier,
        'password': password,
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
      throw Exception('账号或密码错误, 或尝试过于频繁');
    }
    // R12 治本: 拿到 session cookie 后从浏览器 document.cookie 同步 (web 平台)
    // dio onResponse 拦截器已经 set 了 (native 平台), 这里多一道兑底以防 web XHR
    // 头不可见。带后存储后 isLoggedIn() / _checkLogin() 能读到。
    await ApiClient.syncCookiesFromBrowser();
  }

  /// 修改密码 (P2: 首登后自助改密)
  /// PATCH /api/me/password { oldPassword, newPassword }
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _dio.patch('/me/password', data: {
      'oldPassword': oldPassword,
      'newPassword': newPassword,
    });
  }

  /// 修改登录手机号 (自助改号)
  /// PATCH /api/me/phone { password, newPhone }
  /// 成功 → caller 自己 invalidate me provider 拿新号
  Future<void> changePhone({
    required String password,
    required String newPhone,
  }) async {
    await _dio.patch('/me/phone', data: {
      'password': password,
      'newPhone': newPhone,
    });
  }

  /// R12 治本方案 A: dev + web 平台走专用 endpoint 拿 body 返回的 session token
  ///
  /// Auth.js 默认 httpOnly=true, JS 读不到。dio XHR 拿不到 Set-Cookie 头。
  /// 唯一可行的路径: 后端返回 body 带 token (dev 模式 only, prod  404)。
  ///
  /// 调用后:
  ///   - storage.session_cookie_name + session_token 已写入
  ///   - 后续 dio 请求从 storage 读 token 拼 Cookie 头
  Future<void> _loginDevWeb({
    required String identifier,
    required String password,
  }) async {
    // 用 dio 调 endpoint (dio web 平台 XHR 拿不到 Set-Cookie 头, 但能读 body)
    final resp = await _dio.post('/auth/flutter-login', data: {
      'identifier': identifier,
      'password': password,
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

  /// 退出登录: 清本地凭证 (服务端的 JWT 仍在有效期内, 但客户端不再使用)
  /// ⚠ 因为 JWT 是"长期有效"的 (ADR-0013), 服务端**无法**主动吊销单个 token ——
  ///   设备丢了要作废: 管理员停用账号 (user.is_active=false) 或换 AUTH_SECRET (全体失效)
  Future<void> logout() async {
    try {
      await ApiClient.storage.delete(key: ApiClient.sessionTokenKey);
      await ApiClient.storage.delete(key: ApiClient.sessionCookieNameKey);
    } catch (e) {
      // ignore: avoid_print
      print('[session] logout cleanup failed: $e');
    }
  }
}

// ============================================
// CustomerService (C 端客户)
// ============================================

class CustomerService {
  final Dio _dio;
  CustomerService(this._dio);

  /// 客户列表 (含跟进信息块; 主人 2026-09-20)
  /// [type] 类型筛选: null / 'all' = 不筛, 其余 = franchisee / seed / normal
  /// [sort] 排序: urgency (紧急度, **仅会员**) / recent (最近联系) / new (最近添加) / name
  ///        非会员请求 urgency → 后端降级为 new 且 result.urgencyLocked = true
  Future<CustomerListResult> list({
    String? search,
    String? type,
    String? sort,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _dio.get('/customers', queryParameters: {
      if (search != null && search.isNotEmpty) 'search': search,
      if (type != null && type.isNotEmpty && type != 'all') 'type': type,
      if (sort != null && sort.isNotEmpty) 'sort': sort,
      'limit': limit,
      'offset': offset,
    });
    return CustomerListResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// 客户跟进分析 (详情页「跟进分析」卡; 客观指标免费, aiTipAvailable = 会员能否看 AI 解读)
  Future<FollowUpAnalysis> followUpAnalysis(String customerId) async {
    final res =
        await _dio.get('/customers/$customerId/follow-up-analysis');
    return FollowUpAnalysis.fromJson(res.data as Map<String, dynamic>);
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

  /// 把一位**已注册用户**加为我的客户 (归属声明, ADR-0015 Q11/Q12/Q15)
  ///
  /// 后端规则 (先到先得):
  ///   无归属 → 成功; 已是我的 → 幂等成功; 已归属别人 → 409; 自己 → 400; 不存在 → 404
  Future<Customer> claim(String customerId) async {
    final res = await _dio.post('/customers/claim', data: {'customerId': customerId});
    final data = res.data as Map<String, dynamic>;
    return Customer.fromJson(data['customer'] as Map<String, dynamic>);
  }

  /// 合并重复客户 (P8)
  ///
  /// 语义: 把**这位**客户合并进 `intoCustomerId` (对方保留, 这位软删)。
  /// 搬的是 wellness_record / interaction / follow_up_task 三张子表 + 账号列连接。
  /// ⚠ 不可逆 (来源软删, App 内无恢复入口) —— 调用方必须先让用户确认。
  Future<Map<String, dynamic>> merge(
    String customerId, {
    required String intoCustomerId,
  }) async {
    final res = await _dio.post('/customers/$customerId/merge', data: {
      'intoCustomerId': intoCustomerId,
    });
    return res.data as Map<String, dynamic>;
  }

  /// 把客户归属转给同事 (P8)
  ///
  /// 接收人用**邀请码**定位 (不用 userId):
  ///   ① 客户端不该拿到别人的 user id; ② 邀请码是服务端可复核的身份锚 (ADR-0016 D1)。
  /// ⚠ 调用前先用 `BillingService.lookupReferralCode` 让用户确认是**哪个人**
  ///   (打码手机号 + 姓名), 再把同一个 code 传到这里 —— 服务端会重新解析。
  ///
  /// 权限: 只有当前归属人 (或系统管理员) 能转出。
  /// 返回转出后的新归属状态 (直接拿来回显, 不用再打一次 ownership)。
  Future<CustomerOwnership> transfer(
    String customerId, {
    required String toReferralCode,
  }) async {
    final res = await _dio.post('/customers/$customerId/transfer', data: {
      'toReferralCode': toReferralCode,
    });
    final data = res.data as Map<String, dynamic>;
    return CustomerOwnership.fromJson(
        (data['ownership'] as Map<String, dynamic>?) ?? const {});
  }

  /// 查客户的归属状态 (谁把她当客户在管) —— 管理 Tab 的「归属」卡用
  ///
  /// 返回体里的 `canClaim` 与后端 `claimCustomerOwnership` 的放行条件一一对应,
  /// 所以 UI 可以直接拿它决定按钮可用性 ("按钮能点 = 后端会放行")。
  Future<CustomerOwnership> ownership(String customerId) async {
    final res = await _dio.get('/customers/$customerId/ownership');
    return CustomerOwnership.fromJson(res.data as Map<String, dynamic>);
  }

  /// 绑定 app 身份: 填她的**邀请码** (身份识别码) 把手工客户与她账号合上
  ///   ADR-0016 场景: 客户先手工建档, 后来自已注册 app (手机号对不上 → 自动匹配不到)
  /// 后端: 只改 user.customer_id; 若她注册时系统已自动建了**空档案** → 接管 (删掉那条)
  Future<BindAccountResult> bindAccount(
    String customerId,
    String referralCode, {
    bool syncPhone = false,
  }) async {
    final res = await _dio.post('/customers/$customerId/bind-account', data: {
      'referralCode': referralCode,
      if (syncPhone) 'syncPhone': true,
    });
    return BindAccountResult.fromJson(res.data as Map<String, dynamic>);
  }

}

// ============================================
// WellnessRecordService (养生记录)
// ============================================

/// 客户洞察 (评分 + 行动指引; 免费层, 不烧 AI 额度)
class CustomerInsightService {
  final Dio _dio;
  CustomerInsightService(this._dio);

  /// GET /api/customers/[id]/insight
  /// 一次拿 [评分环] + [今日待办]; 确定性规则引擎, 不调 AI。
  Future<CustomerInsight> get(String customerId) async {
    final res = await _dio.get('/customers/$customerId/insight');
    return CustomerInsight.fromJson(res.data as Map<String, dynamic>);
  }
}

/// 客户分析图谱 (P4; 免费层)
class CustomerChartsService {
  final Dio _dio;
  CustomerChartsService(this._dio);

  /// GET /api/customers/[id]/charts
  /// 趋势 + 部位热力; 雷达图用 CustomerScore 的维度分, 不走这里。
  Future<CustomerCharts> get(String customerId) async {
    final res = await _dio.get('/customers/$customerId/charts');
    return CustomerCharts.fromJson(res.data as Map<String, dynamic>);
  }
}

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
    /// ★ P6 (ADR-0016 D1): 优先按**邀请码**找账号 (后端从账号带出姓名/手机号)
    String? newReferralCode,
    String? newPhone,
    String? newNotes,
    String? unjoinFid,
  }) async {
    final kind = unjoinFid != null ? 'unjoin' : 'create';
    final res = await _dio.post('/franchisees/placement-requests', data: {
      'kind': kind,
      'targetParentId': targetParentId,
      'side': side,
      if (newName != null) 'newName': newName,
      if (newReferralCode != null) 'newReferralCode': newReferralCode,
      if (newPhone != null) 'newPhone': newPhone,
      if (newNotes != null) 'newNotes': newNotes,
      if (unjoinFid != null) 'unjoinFid': unjoinFid,
    });
    return PlacementRequest.fromJson(res.data as Map<String, dynamic>);
  }

  /// 认领我的「上层点位」= 现实里的直接上级 (主人 2026-09-21 拍 B2 + 补充)
  ///   - 我必须是**树根** (服务端硬校验; = 我的上层点位空着)
  ///   - 上级已在 app 里 → 复用他那个节点 (两棵树合并); 不在 → 执行时新建 (他成为新根)
  ///   - 双方确认: 我 (发起人, 自动记 1 票) + 上级本人 (在自己的「加盟落位确认」里点同意)
  ///   - ⚠ **不传 side**: 主人拍「我在我的上级是处于 a线还是 b线由我的上级自己决定」
  ///     → 由上级本人在同意那一步挑一条自己空着的线
  ///   - 不需要 targetParentId: 锚点 = 我自己那个根 (服务端填)
  Future<PlacementRequest> claimUpline({
    /// 姓名可省 (后端按邀请码从账号带出真名)
    String? newName,
    /// ★ P6 (ADR-0016 D1): 按**邀请码**找账号 (主口径)
    String? newReferralCode,
    String? newPhone,
    String? newNotes,
  }) async {
    final res = await _dio.post('/franchisees/placement-requests', data: {
      'kind': 'promote',
      // ⚠ 后端 promote 不读 targetParentId (锚点=发起人自己); 传 0 只为兼容校验
      'targetParentId': '0',
      if (newName != null) 'newName': newName,
      if (newReferralCode != null) 'newReferralCode': newReferralCode,
      if (newPhone != null) 'newPhone': newPhone,
      if (newNotes != null) 'newNotes': newNotes,
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
  ///   - [side] 只有一种情况要传 (主人 2026-09-21 拍): **认领上级 (promote) 单里的上级本人**
  ///     同意时挑「这位下线放在我的 A线 还是 B线」(她两条线都空时才需要选)
  Future<PlacementRequest> decidePlacementRequest(
    String id, {
    required bool approve,
    String? side,
  }) async {
    final res = await _dio.post(
      '/franchisees/placement-requests/$id/decide',
      data: {
        'decision': approve ? 'approve' : 'reject',
        if (side != null) 'side': side,
      },
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
// AiService (AI 洞察)
// ============================================
// ⚠ P5 (主人 2026-09-23): 原先 4 个方法 (profileInsight / followUpInsight /
//   effectAnalysis / followUpSuggestion) 各自打一个后端路由、各自烧一次 AI。
//   现合并为 `insight()` —— **一次调用** 拿回三段内容 + 复购预测。

class AiService {
  final Dio _dio;
  AiService(this._dio);

  /// AI 洞察 (P5 唯一入口): 一次调用 → 画像 + 话术 + 效果 + 复购预测
  ///
  /// `reason` = 跟进理由 (只影响「话术」那段; 来自 L0 行动规则 / 用户下拉)
  Future<AiInsightResult> insight(String customerId, {String? reason}) async {
    final res = await _dio.post('/ai/insight', data: {
      'customerId': customerId,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    });
    return AiInsightResult.fromJson(res.data as Map<String, dynamic>);
  }

  /// 复购预测 (纯 DB 计算, **不消耗 AI**)
  ///
  /// 单独保留一个路由: 这张卡是**自动加载**的 (进页就看), 不能为了它去调 AI。
  Future<RepurchasePrediction> repurchasePrediction(String customerId) async {
    final res = await _dio.get('/ai/repurchase-prediction/$customerId');
    return RepurchasePrediction.fromJson(res.data as Map<String, dynamic>);
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
// BillingService (会员 / 推荐码, ADR-0012)
// ============================================

class ReferralSummary {
  final String code;
  final int grantedDays;
  final int invitedCount;
  final int rewardedCount;
  final int remainingThisMonth;
  final int remainingTotal;

  const ReferralSummary({
    this.code = '',
    this.grantedDays = 0,
    this.invitedCount = 0,
    this.rewardedCount = 0,
    this.remainingThisMonth = 0,
    this.remainingTotal = 0,
  });

  factory ReferralSummary.fromJson(Map<String, dynamic> json) =>
      ReferralSummary(
        code: json['code']?.toString() ?? '',
        grantedDays: (json['grantedDays'] as num?)?.toInt() ?? 0,
        invitedCount: (json['invitedCount'] as num?)?.toInt() ?? 0,
        rewardedCount: (json['rewardedCount'] as num?)?.toInt() ?? 0,
        remainingThisMonth: (json['remainingThisMonth'] as num?)?.toInt() ?? 0,
        remainingTotal: (json['remainingTotal'] as num?)?.toInt() ?? 0,
      );
}

/// 人工收款信息 (内测通道: 个人微信收款码 + 管理员核销)
class ManualPayProduct {
  final String planCode;
  final String label;
  final int amountCents;
  final int days;
  const ManualPayProduct({
    required this.planCode,
    required this.label,
    required this.amountCents,
    required this.days,
  });

  String get amountLabel => '¥${(amountCents / 100).toStringAsFixed(0)}';
  static ManualPayProduct fromJson(Map<String, dynamic> j) => ManualPayProduct(
        planCode: j['planCode']?.toString() ?? 'monthly',
        label: j['label']?.toString() ?? '',
        amountCents: (j['amountCents'] as num?)?.toInt() ?? 0,
        days: (j['days'] as num?)?.toInt() ?? 30,
      );
}

class ManualPayRequestView {
  final String id;
  final String status; // pending / approved / rejected
  final int amountCents;
  final int days;
  final String? rejectReason;
  const ManualPayRequestView({
    required this.id,
    required this.status,
    this.amountCents = 0,
    this.days = 0,
    this.rejectReason,
  });

  String get statusLabel => switch (status) {
        'pending' => '已提交, 等管理员确认',
        'approved' => '已开通',
        'rejected' => '未通过',
        _ => status,
      };

  static ManualPayRequestView fromJson(Map<String, dynamic> j) =>
      ManualPayRequestView(
        id: j['id']?.toString() ?? '',
        status: j['status']?.toString() ?? 'pending',
        amountCents: (j['amountCents'] as num?)?.toInt() ?? 0,
        days: (j['days'] as num?)?.toInt() ?? 0,
        rejectReason: j['rejectReason']?.toString(),
      );
}

class ManualPayInfo {
  final bool enabled;
  final String qrUrl;
  final bool isFallbackQr;

  /// 这张码现在能不能取到 (配置过 或 静态文件存在)
  final bool qrAvailable;
  final String payeeName;
  final String noteHint;
  final List<ManualPayProduct> products;
  final List<ManualPayRequestView> myRequests;

  const ManualPayInfo({
    this.enabled = true,
    this.qrUrl = '/payment/wechat-qr.png',
    this.isFallbackQr = true,
    this.qrAvailable = false,
    this.payeeName = '管理员',
    this.noteHint = '',
    this.products = const [],
    this.myRequests = const [],
  });

  ManualPayRequestView? get latestRequest =>
      myRequests.isEmpty ? null : myRequests.first;

  static ManualPayInfo fromJson(Map<String, dynamic> j) => ManualPayInfo(
        enabled: j['enabled'] as bool? ?? true,
        qrUrl: j['qrUrl']?.toString() ?? '/payment/wechat-qr.png',
        isFallbackQr: j['isFallbackQr'] as bool? ?? true,
        qrAvailable: j['qrAvailable'] as bool? ?? true,
        payeeName: j['payeeName']?.toString() ?? '管理员',
        noteHint: j['noteHint']?.toString() ?? '',
        products: (j['products'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ManualPayProduct.fromJson)
                .toList() ??
            const [],
        myRequests: (j['myRequests'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(ManualPayRequestView.fromJson)
                .toList() ??
            const [],
      );
}

/// 我推荐的人 (推荐人视角)
class MyReferral {
  final String id;
  final String name;
  final String phoneMasked;
  final String status; // pending / confirmed / rewarded / rejected

  /// 关系来源 (决定 pending 是不是"要你操作"):
  ///   admin       = 管理员代建 (对方已拿到 15 天; 这条只是等对方成为加盟者后给你发奖)
  ///   self_signup = 对方自己填你的码注册 → **要你点"这是我朋友"才发**
  final String source;
  final String createdAt;

  /// 对方的客户档案 id (建号即建档 §6.6; admin 豁免建档 = null)
  final String? customerId;

  /// 归属状态 (ADR-0015 Q11/Q12/Q15):
  ///   claimable  无归属 → 可「加为我的客户」
  ///   mine       已经是我的客户
  ///   others     已归属别人 (先到先得, 不能抢)
  ///   no_profile 对方无客户档案 (管理员等豁免建档)
  final String claimState;

  const MyReferral({
    required this.id,
    required this.name,
    this.phoneMasked = '',
    this.status = 'pending',
    this.source = 'admin',
    this.createdAt = '',
    this.customerId,
    this.claimState = 'no_profile',
  });

  /// 需要我点确认的 (只有自助注册 + 还没处理)
  bool get needsMyConfirmation => status == 'pending' && source == 'self_signup';

  /// 可以「加为我的客户」吗 (后端会再校验一次先到先得)
  bool get canClaim => claimState == 'claimable' && customerId != null;

  /// 归属状态文案 (null = 不显示)
  String? get claimLabel => switch (claimState) {
        'mine' => '✓ 已是我的客户',
        'others' => '已归属其他销售',
        _ => null,
      };

  String get statusLabel {
    if (needsMyConfirmation) return '等你确认';
    return switch (status) {
      'pending' => '已生效 (等对方成为加盟者后你得 15 天)',
      'confirmed' => '已确认 (对方得 15 天)',
      'rewarded' => '已完成 (你也拿到 15 天)',
      'rejected' => '已驳回',
      _ => status,
    };
  }

  static MyReferral fromJson(Map<String, dynamic> j) => MyReferral(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        phoneMasked: j['phoneMasked']?.toString() ?? '',
        status: j['status']?.toString() ?? 'pending',
        source: j['source']?.toString() ?? 'admin',
        createdAt: j['createdAt']?.toString() ?? '',
        customerId: j['customerId']?.toString(),
        claimState: j['claimState']?.toString() ?? 'no_profile',
      );
}

/// 按推荐码查到的人 (身份识别结果, ADR-0015 Q10)
///
/// 用途: 新建客户时填对方推荐码 → 识别到人 → 走 claim 把他加为我的客户
class ReferralLookup {
  final bool found;
  final String code;
  final String name;
  final String phoneMasked;
  final bool isMember;

  /// 对方的客户档案 id (admin 豁免建档 = null)
  final String? customerId;

  /// claimable | mine | others | no_profile | self
  final String claimState;

  const ReferralLookup({
    required this.found,
    this.code = '',
    this.name = '',
    this.phoneMasked = '',
    this.isMember = false,
    this.customerId,
    this.claimState = 'no_profile',
  });

  bool get canClaim => found && claimState == 'claimable' && customerId != null;

  /// 不能加时的原因文案 (claimable → 空串)
  String get claimLabel => switch (claimState) {
        'mine' => '已经是你的客户',
        'others' => '已归属其他销售 (先到先得)',
        'self' => '这是你自己的推荐码',
        'no_profile' => '该用户没有客户档案 (不参与客户维护)',
        _ => '',
      };

  static ReferralLookup fromJson(Map<String, dynamic> j) => ReferralLookup(
        found: j['found'] == true,
        code: j['code']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        phoneMasked: j['phoneMasked']?.toString() ?? '',
        isMember: j['isMember'] == true,
        customerId: j['customerId']?.toString(),
        claimState: j['claimState']?.toString() ?? 'no_profile',
      );
}

/// 绑定 app 身份的结果 (POST /customers/:id/bind-account)
///
/// 场景 (主人 2026-09-22): 客户先被手工建档, 后来自己注册了 app (手机号对不上 →
/// 系统自动匹配不到) → 在客户详情页填她的**邀请码**把两边合上。
class BindAccountResult {
  final bool alreadyBound;
  final bool phoneMismatch;
  final bool phoneSynced;
  /// 接管了她注册时系统自动建的空档案 (那条已删)
  final bool replacedEmptyProfile;
  final String accountName;
  final String accountPhoneMasked;
  final String message;

  const BindAccountResult({
    this.alreadyBound = false,
    this.phoneMismatch = false,
    this.phoneSynced = false,
    this.replacedEmptyProfile = false,
    this.accountName = '',
    this.accountPhoneMasked = '',
    this.message = '',
  });

  factory BindAccountResult.fromJson(Map<String, dynamic> j) {
    final acc = (j['account'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BindAccountResult(
      alreadyBound: j['alreadyBound'] == true,
      phoneMismatch: j['phoneMismatch'] == true,
      phoneSynced: j['phoneSynced'] == true,
      replacedEmptyProfile: j['replacedEmptyProfile'] == true,
      accountName: acc['name']?.toString() ?? '',
      accountPhoneMasked: acc['phoneMasked']?.toString() ?? '',
      message: j['message']?.toString() ?? '',
    );
  }
}

/// 管理员看到的待审申请
class AdminPayRequest {
  final String id;
  final String userId;
  final int amountCents;
  final String? payerNote;
  final String? proofUrl;
  final String createdAt;
  const AdminPayRequest({
    required this.id,
    required this.userId,
    this.amountCents = 0,
    this.payerNote,
    this.proofUrl,
    this.createdAt = '',
  });

  static AdminPayRequest fromJson(Map<String, dynamic> j) => AdminPayRequest(
        id: j['id']?.toString() ?? '',
        userId: j['userId']?.toString() ?? '',
        amountCents: (j['amountCents'] as num?)?.toInt() ?? 0,
        payerNote: j['payerNote']?.toString(),
        proofUrl: j['proofUrl']?.toString(),
        createdAt: j['createdAt']?.toString() ?? '',
      );
}

class BillingService {
  final Dio _dio;
  BillingService(this._dio);

  /// 填推荐码 (注册/首次使用时可选; 服务端保证一人一生一次)
  /// 返回给用户看的结果文案
  Future<({bool ok, String message})> claimReferralCode(String code) async {
    try {
      final res = await _dio.post('/billing/referral/claim', data: {'code': code});
      final data = res.data as Map<String, dynamic>;
      final granted = data['refereeGranted'] == true;
      return (
        ok: true,
        message: granted ? '推荐码已生效, 你获得 15 天会员' : '推荐码已记录',
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map ? data['error']?.toString() : null;
      return (ok: false, message: msg ?? '推荐码用不了, 请检查后重试');
    }
  }

  /// 我的推荐码 / 已获天数 / 剩余名额
  Future<ReferralSummary> referralSummary() async {
    final res = await _dio.get('/billing/referral/summary');
    return ReferralSummary.fromJson(res.data as Map<String, dynamic>);
  }

  /// 按推荐码查人 (身份识别, ADR-0015 Q10)
  ///
  /// 后端: 必须登录 + 限流 10 次/分 + 审计; 只返回姓名/打码手机号/会员标识/归属状态。
  /// 码不存在 → found=false (200, 不是错误)。
  Future<ReferralLookup> lookupReferralCode(String code) async {
    final res = await _dio.get('/referral/lookup', queryParameters: {'code': code});
    return ReferralLookup.fromJson(res.data as Map<String, dynamic>);
  }

  // ---------- 人工收款 (内测: 个人微信收款码) ----------

  /// 收款方式 + 我的申请状态
  Future<ManualPayInfo> manualPayInfo() async {
    final res = await _dio.get('/billing/pay-info');
    return ManualPayInfo.fromJson(res.data as Map<String, dynamic>);
  }

  /// 提交"我已支付"
  Future<({bool ok, String message})> submitManualPayment({
    required String planCode,
    String? payerNote,
    String? proofUrl,
  }) async {
    try {
      final res = await _dio.post('/billing/manual-payments', data: {
        'planCode': planCode,
        if (payerNote != null) 'payerNote': payerNote,
        if (proofUrl != null) 'proofUrl': proofUrl,
      });
      return (
        ok: true,
        message: (res.data as Map<String, dynamic>)['message']?.toString() ??
            '已提交, 等管理员确认',
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map ? data['error']?.toString() : null;
      return (ok: false, message: msg ?? '提交失败, 请检查网络后重试');
    }
  }

  // ---------- 自助注册 (B1) + 推荐人确认 ----------

  /// 凭推荐码注册 (成功后客户端用 手机号+密码 正常登录)
  Future<({bool ok, String message, String? username})> registerWithCode({
    required String code,
    required String name,
    required String phone,
    required String password,
  }) async {
    try {
      final res = await _dio.post('/auth/register', data: {
        'code': code,
        'name': name,
        'phone': phone,
        'password': password,
      });
      final data = res.data as Map<String, dynamic>;
      return (
        ok: true,
        message: data['message']?.toString() ?? '注册成功',
        username: data['username']?.toString(),
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map ? data['error']?.toString() : null;
      return (ok: false, message: msg ?? '注册失败, 请检查网络后重试', username: null);
    }
  }

  /// 我推荐的人 (待确认 / 已确认 / 已驳回)
  Future<List<MyReferral>> myReferrals() async {
    final res = await _dio.get('/billing/referral/pending');
    final list = (res.data as Map<String, dynamic>)['referrals'] as List? ?? [];
    return list.whereType<Map<String, dynamic>>().map(MyReferral.fromJson).toList();
  }

  /// 推荐人确认「这是我朋友」/ 否认
  Future<({bool ok, String message})> decideReferral({
    required String rewardId,
    required bool confirm,
    String? reason,
  }) async {
    try {
      final res = await _dio.post('/billing/referral/pending/$rewardId', data: {
        'decision': confirm ? 'confirm' : 'reject',
        if (reason != null) 'reason': reason,
      });
      final data = res.data as Map<String, dynamic>;
      return (
        ok: true,
        message: confirm
            ? (data['reason']?.toString() ?? '已确认')
            : '已驳回',
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map ? data['error']?.toString() : null;
      return (ok: false, message: msg ?? '操作失败, 请重试');
    }
  }

  // ---------- 管理员 (内测核销) ----------

  Future<List<AdminPayRequest>> adminManualPayments({
    String status = 'pending',
  }) async {
    final res = await _dio.get(
      '/billing/admin/manual-payments',
      queryParameters: {'status': status},
    );
    final list = (res.data as Map<String, dynamic>)['requests'] as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(AdminPayRequest.fromJson)
        .toList();
  }

  Future<({bool ok, String message})> adminDecidePayment({
    required String requestId,
    required bool approve,
    int? grantedDays,
    String? rejectReason,
  }) async {
    try {
      await _dio.post('/billing/admin/manual-payments/$requestId', data: {
        'decision': approve ? 'approve' : 'reject',
        if (grantedDays != null) 'grantedDays': grantedDays,
        if (rejectReason != null) 'rejectReason': rejectReason,
      });
      return (ok: true, message: approve ? '已开通' : '已驳回');
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map ? data['error']?.toString() : null;
      return (ok: false, message: msg ?? '操作失败, 请重试');
    }
  }

  /// 管理员设置收款码/收款人/备注提示
  Future<bool> adminSetPayInfo({
    String? qrUrl,
    String? payeeName,
    String? noteHint,
    bool? enabled,
  }) async {
    try {
      await _dio.post('/billing/admin/pay-info', data: {
        if (qrUrl != null) 'qrUrl': qrUrl,
        if (payeeName != null) 'payeeName': payeeName,
        if (noteHint != null) 'noteHint': noteHint,
        if (enabled != null) 'enabled': enabled,
      });
      return true;
    } on DioException {
      return false;
    }
  }
}

// ============================================
// SystemService (版本 / 更新 / 网络自检)
// ============================================

/// 管理员 · 用户管理 (全部注册用户 + 加盟节点总览 + 建根)
///   主人 2026-09-21 拍: 入口在「我的」(仅 admin 可见); 服务端每次重新判权
class AdminUsersService {
  final Dio _dio;
  AdminUsersService(this._dio);

  /// 全部注册用户 + 加盟节点 (含无账号节点) + 摘要
  Future<AdminUsersOverview> overview() async {
    final res = await _dio.get('/admin/users');
    return AdminUsersOverview.fromJson(res.data as Map<String, dynamic>);
  }

  /// 建根 (Bootstrap Root): 把一个**已注册**账号设为根节点
  ///   主人 2026-09-21 拍: 「建根 = 先有账号」—— 不新建账号, 只挂节点
  Future<({bool ok, String message, int rootCount})> createRoot({
    required String userId,
    required String note,
  }) async {
    try {
      final res = await _dio.post('/admin/users/$userId/root', data: {'note': note});
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
      final count = (data['rootCount'] as num?)?.toInt() ?? 0;
      return (
        ok: true,
        message: count > 1 ? '已建根 (现在共 $count 棵树)' : '已建根',
        rootCount: count,
      );
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map ? data['error']?.toString() : null;
      return (ok: false, message: msg ?? '建根失败, 请重试', rootCount: 0);
    }
  }

  /// 协商处理后**强改上层** (管理员专用, 单方生效 + 必填原因留痕)
  ///   主人 2026-09-21 拍: 「『上层』= 点位父 …… 上层一旦有人不能撤换,
  ///   除非联系系统管理员协商处理」→ 这是唯一的人工例外通道。
  ///   - [fid] 要调整的节点 (她的整棵子树跟着走)
  ///   - [newParentFid] 新的上层节点
  ///   - [side] 她在新上层下面哪条线 ('left' = A线 / 'right' = B线)
  ///   - [reason] 原因 (必填 2-200 字)
  Future<({bool ok, String message})> reparentNode({
    required String fid,
    required String newParentFid,
    required String side,
    required String reason,
  }) async {
    try {
      final res = await _dio.post('/admin/nodes/$fid/reparent', data: {
        'newParentFid': newParentFid,
        'side': side,
        'reason': reason,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
      final to = data['toParentName']?.toString() ?? '';
      final size = (data['subtreeSize'] as num?)?.toInt() ?? 1;
      final merged = data['mergedTrees'] == true;
      final roots = (data['rootCount'] as num?)?.toInt() ?? 0;
      final parts = <String>['已把「${data['moveName'] ?? ''}」改挂到「$to」'];
      if (size > 1) parts.add('整棵子树 $size 个节点一起移');
      if (merged) parts.add('两棵树合并了 (现在共 $roots 棵)');
      return (ok: true, message: parts.join(' · '));
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map ? data['error']?.toString() : null;
      return (ok: false, message: msg ?? '改上层失败, 请重试');
    }
  }
}

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

  /// Tab 计数: 我主理的 / 我受邀的 各有多少「进行中」的沙龙
  /// (口径 = status NOT IN 'finished','cancelled', 与 list(includeFinished=false) 一致)
  /// 用于子页面 tab 角标
  Future<SalonActiveCounts> activeCounts() async {
    final res = await _dio.get('/salons/counts');
    return SalonActiveCounts.fromJson(res.data as Map<String, dynamic>);
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

  /// 取消沙龙 (status=cancelled, 数据保留 + 系统动态记录 reason)
  /// reason: 主理人写给受邀者的详细说明, 后端必填 10-500 字
  Future<Salon> cancel(String id, {required String reason}) async {
    final res = await _dio.post('/salons/$id/cancel', data: {'reason': reason});
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

  /// 快速邀请建议 (创建沙龙用): 我的客户 + 图谱上层 ≤3 层
  /// 编辑模式请走 [addInvitation] 单条添加
  Future<QuickInviteSuggestions> quickInviteSuggestions() async {
    final res = await _dio.get('/salons/quick-invite-suggestions');
    return QuickInviteSuggestions.fromJson(
      res.data as Map<String, dynamic>,
    );
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

  /// 上传图片 → 返回 URL
  ///
  /// [purpose] 决定要不要会员 (ADR-0012 §5):
  ///   - 'wellness' (默认) / 'salon' / 'other' = 业务照片 → 会员功能 (免费用户 402)
  ///   - 'avatar' = 个人账号头像 → 免费 (换头像不该收费)
  Future<String> upload(
    String base64Data, {
    String? mimeType,
    String purpose = 'wellness',
  }) async {
    final res = await _dio.post('/photos', data: {
      'base64': base64Data,
      if (mimeType != null) 'mimeType': mimeType,
      'purpose': purpose,
    });
    return (res.data as Map<String, dynamic>)['url'] as String;
  }
}