// ============================================
// 「我的」页数据模型 (手写 fromJson, 不引 codegen)
// ============================================
// 数据源: GET /api/me (后端一次 join 完账号 + 加盟身份 + 门店 + 数据概览)
// 后端: src/app/api/me/route.ts
//
// 为什么手写而不是 freezed:
//   - 字段基本只读、只在这一页用 (不需要 copyWith / ==)
//   - 跟 franchisee.dart 一样的手写风格, 保持一致
//   - 所有字段都有兜底: 后端加字段 / 老版本后端少字段都不会崩 (中老年用户不装新版)
//
// 边界: 每个块 (user / phone / franchisee / stats) 都可能为 null ——
//   - 账号行不存在 (dev mock 登录) → user.hasUserRecord = false
//   - 未加盟 → franchisee = null (合法状态, 不是错误)
//   - dev 空 session → stats = null
//   UI 必须按「这块有没有」分块渲染, 不能假设一定有

/// 手机号 (后端同时给明文 + 打码: 默认展示打码, 用户点“显示”才用 full)
class PhonePair {
  final String full;
  final String masked;

  const PhonePair({required this.full, required this.masked});

  static PhonePair? fromJson(dynamic json) {
    if (json is! Map) return null;
    final full = json['full']?.toString() ?? '';
    final masked = json['masked']?.toString() ?? '';
    if (full.isEmpty && masked.isEmpty) return null;
    return PhonePair(full: full, masked: masked.isEmpty ? full : masked);
  }

  /// 打码展示 (列表/详情默认)
  String get display => masked.isEmpty ? full : masked;

  bool get isEmpty => full.isEmpty && masked.isEmpty;
}

/// 账号 (user 表 + session 兜底)
class MeUser {
  final String id;
  final String name;
  final String role; // admin | manager | sales
  final String roleLabel; // 管理员 | 店长 | 销售员
  final bool isActive;
  final DateTime? createdAt;

  /// false = 后端没查到 user 行 (dev mock 登录), 资料不全需要提示
  final bool hasUserRecord;

  /// 自定义头像 (null = 默认首字 / 'preset:x' / '/uploads/x.jpg')
  /// 解析失败/未知值 → null (UI 退回首字, 不渲染破图)
  final String? avatarUrl;

  const MeUser({
    required this.id,
    required this.name,
    required this.role,
    required this.roleLabel,
    required this.isActive,
    this.createdAt,
    this.hasUserRecord = true,
    this.avatarUrl,
  });

  static MeUser? fromJson(dynamic json) {
    if (json is! Map) return null;
    return MeUser(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      role: json['role']?.toString() ?? 'sales',
      roleLabel: json['roleLabel']?.toString() ?? '销售员',
      isActive: json['isActive'] as bool? ?? true,
      createdAt: _parseDate(json['createdAt']),
      hasUserRecord: json['hasUserRecord'] as bool? ?? true,
      avatarUrl: _parseAvatarUrl(json['avatarUrl']),
    );
  }
}

/// 头像值兜底 (只认 preset: / /uploads/, 其余当没有)
/// 跟后端 src/lib/avatar.ts 同一套白名单 —— 客户端也要能挡住脏数据
String? _parseAvatarUrl(dynamic raw) {
  if (raw is! String) return null;
  final v = raw.trim();
  if (v.isEmpty) return null;
  if (v.startsWith('preset:')) {
    final id = v.substring('preset:'.length);
    return kAvatarPresetIds.contains(id) ? 'preset:$id' : null;
  }
  if (v.startsWith('/uploads/') && !v.contains('..') && v.length <= 200) {
    return v;
  }
  return null;
}

/// 内置候选 id 白名单 (跟后端 AVATAR_PRESETS 同步; 复制一份是为了
/// core/models 不依赖 widgets 层 —— 模型只做校验, 不画 UI)
const Set<String> kAvatarPresetIds = {
  'leaf',
  'blossom',
  'tea',
  'zen',
  'heart',
  'sun',
  'sprout',
  'water',
};

/// 门店 (user.default_store_id, 多数账号为空)
class MeStore {
  final String id;
  final String name;

  const MeStore({required this.id, required this.name});

  static MeStore? fromJson(dynamic json) {
    if (json is! Map) return null;
    final name = json['name']?.toString() ?? '';
    if (name.isEmpty) return null;
    return MeStore(id: json['id']?.toString() ?? '', name: name);
  }
}

/// 二叉树位置 (A线 / B线 / 顶级 —— 跟客户图谱同一套说法)
class MePlacement {
  final String? side; // left | right | null(顶级)
  final String sideLabel;
  final int depth;
  final String depthLabel;
  final String path;

  const MePlacement({
    this.side,
    required this.sideLabel,
    required this.depth,
    required this.depthLabel,
    required this.path,
  });

  static MePlacement? fromJson(dynamic json) {
    if (json is! Map) return null;
    return MePlacement(
      side: json['side']?.toString(),
      sideLabel: json['sideLabel']?.toString() ?? '未知位置',
      depth: (json['depth'] as num?)?.toInt() ?? 0,
      depthLabel: json['depthLabel']?.toString() ?? '',
      path: json['path']?.toString() ?? '',
    );
  }

  /// 图里显示的路径 (A线/B线 更直观, 空 = 顶级)
  String get pathLabel {
    if (path.isEmpty) return '(顶级)';
    return path
        .replaceAll('L.', 'A › ')
        .replaceAll('R.', 'B › ')
        .trim()
        .replaceAll(RegExp(r'›\s*$'), '')
        .trim();
  }
}

/// 我的上级 (只给直推上级, 不含手机号以外的隐私)
class MeReferrer {
  final String id;
  final String name;
  final PhonePair? phone;

  const MeReferrer({required this.id, required this.name, this.phone});

  static MeReferrer? fromJson(dynamic json) {
    if (json is! Map) return null;
    return MeReferrer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: PhonePair.fromJson(json['phone']),
    );
  }
}

/// 直接下级计数 (我下面有几个人 / A线 B线 各几个)
class MeDownline {
  final int total;
  final int left;
  final int right;
  final int unknown;

  const MeDownline({
    this.total = 0,
    this.left = 0,
    this.right = 0,
    this.unknown = 0,
  });

  static MeDownline fromJson(dynamic json) {
    if (json is! Map) return const MeDownline();
    return MeDownline(
      total: (json['total'] as num?)?.toInt() ?? 0,
      left: (json['left'] as num?)?.toInt() ?? 0,
      right: (json['right'] as num?)?.toInt() ?? 0,
      unknown: (json['unknown'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 我的加盟身份 (user ↔ franchisee 1:1, 可空)
class MeFranchisee {
  final String id;
  final String name;
  final PhonePair? phone;
  final bool isActive;
  final String? notes;
  final DateTime? joinedAt;
  final MePlacement? placement;
  final MeReferrer? referrer;
  final MeDownline downline;

  const MeFranchisee({
    required this.id,
    required this.name,
    this.phone,
    this.isActive = true,
    this.notes,
    this.joinedAt,
    this.placement,
    this.referrer,
    this.downline = const MeDownline(),
  });

  static MeFranchisee? fromJson(dynamic json) {
    if (json is! Map) return null;
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty || id == '0') return null; // 后端空态占位
    return MeFranchisee(
      id: id,
      name: json['name']?.toString() ?? '',
      phone: PhonePair.fromJson(json['phone']),
      isActive: json['isActive'] as bool? ?? true,
      notes: json['notes']?.toString(),
      joinedAt: _parseDate(json['joinedAt']),
      placement: MePlacement.fromJson(json['placement']),
      referrer: MeReferrer.fromJson(json['referrer']),
      downline: MeDownline.fromJson(json['downline']),
    );
  }
}

/// 数据概览 (口径跟客户列表一致: 全库非软删, 见后端 queries/dashboard.ts 注释)
class MeStats {
  final int customerCount;
  final int thisMonthVisits;
  final int pendingFollowUps;
  final int totalInteractions;
  final int newCustomersThisMonth;

  const MeStats({
    this.customerCount = 0,
    this.thisMonthVisits = 0,
    this.pendingFollowUps = 0,
    this.totalInteractions = 0,
    this.newCustomersThisMonth = 0,
  });

  static MeStats? fromJson(dynamic json) {
    if (json is! Map) return null;
    return MeStats(
      customerCount: (json['customerCount'] as num?)?.toInt() ?? 0,
      thisMonthVisits: (json['thisMonthVisits'] as num?)?.toInt() ?? 0,
      pendingFollowUps: (json['pendingFollowUps'] as num?)?.toInt() ?? 0,
      totalInteractions: (json['totalInteractions'] as num?)?.toInt() ?? 0,
      newCustomersThisMonth:
          (json['newCustomersThisMonth'] as num?)?.toInt() ?? 0,
    );
  }
}

/// GET /api/me 的完整响应
class MeProfile {
  final MeUser? user;
  final PhonePair? phone;
  final MeStore? store;
  final MeFranchisee? franchisee;
  final MeStats? stats;
  final bool authSkipped;
  final String? sessionUserId;

  const MeProfile({
    this.user,
    this.phone,
    this.store,
    this.franchisee,
    this.stats,
    this.authSkipped = false,
    this.sessionUserId,
  });

  factory MeProfile.fromJson(Map<String, dynamic> json) {
    final dev = json['dev'];
    return MeProfile(
      user: MeUser.fromJson(json['user']),
      phone: PhonePair.fromJson(json['phone']),
      store: MeStore.fromJson(json['store']),
      franchisee: MeFranchisee.fromJson(json['franchisee']),
      stats: MeStats.fromJson(json['stats']),
      authSkipped: dev is Map ? (dev['authSkipped'] as bool? ?? false) : false,
      sessionUserId: dev is Map ? dev['sessionUserId']?.toString() : null,
    );
  }

  /// 页面主标题: 加盟名优先 (加盟网络里认这个名字), 没加盟才退回账号名
  String get displayName {
    final f = franchisee?.name ?? '';
    if (f.isNotEmpty) return f;
    final u = user?.name ?? '';
    return u.isNotEmpty ? u : '我';
  }

  /// 账号名跟加盟名不一样时, 页面上补一行「账号: xxx」
  String? get accountAlias {
    final f = franchisee?.name ?? '';
    final u = user?.name ?? '';
    if (u.isEmpty || f.isEmpty || u == f) return null;
    return u;
  }

  bool get isFranchisee => franchisee != null;
}

/// ============================================
/// 系统 / 版本 (GET /api/app-version + GET /api/health)
/// ============================================

/// 服务器上的安装包元数据
class ApkArtifact {
  final int sizeBytes;
  final String mtimeLocal;
  final String md5;
  final String downloadPath;
  final String downloadUrl;

  const ApkArtifact({
    this.sizeBytes = 0,
    this.mtimeLocal = '',
    this.md5 = '',
    this.downloadPath = '/api/apk-download',
    this.downloadUrl = '',
  });

  static ApkArtifact? fromJson(dynamic json) {
    if (json is! Map) return null;
    return ApkArtifact(
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      mtimeLocal: json['mtimeLocal']?.toString() ?? '',
      md5: json['md5']?.toString() ?? '',
      downloadPath: json['downloadPath']?.toString() ?? '/api/apk-download',
      downloadUrl: json['downloadUrl']?.toString() ?? '',
    );
  }

  /// 23.3 MB (1024 进制, 跟手机设置里的单位一致)
  String get sizeLabel {
    if (sizeBytes <= 0) return '未知大小';
    final mb = sizeBytes / 1024 / 1024;
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// 服务器版本 + 安装包
class AppRelease {
  final String version;
  final int buildNumber;
  final ApkArtifact? apk;

  const AppRelease({
    this.version = '',
    this.buildNumber = 0,
    this.apk,
  });

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    return AppRelease(
      version: json['version']?.toString() ?? '',
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 0,
      apk: ApkArtifact.fromJson(json['apk']),
    );
  }

  String get label =>
      buildNumber > 0 ? 'v$version ($buildNumber)' : 'v$version';
}

/// GET /api/health (不需要登录, 网络自检用)
class HealthInfo {
  final String status;
  final String db;
  final String serverVersion;
  final String phase;
  final int latencyMs;

  const HealthInfo({
    this.status = 'unknown',
    this.db = 'unknown',
    this.serverVersion = '',
    this.phase = '',
    this.latencyMs = 0,
  });

  factory HealthInfo.fromJson(Map<String, dynamic> json, {int latencyMs = 0}) {
    final checks = json['checks'];
    return HealthInfo(
      status: json['status']?.toString() ?? 'unknown',
      db: checks is Map ? (checks['db']?.toString() ?? 'unknown') : 'unknown',
      serverVersion: json['version']?.toString() ?? '',
      phase: json['phase']?.toString() ?? '',
      latencyMs: latencyMs,
    );
  }

  bool get healthy => status == 'healthy' && (db == 'ok' || db == 'unknown');
}

DateTime? _parseDate(dynamic raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}

/// 版本比较 (服务器版本 vs 本机版本)
/// 返回 >0 = 服务器更新, <0 = 本机更新, 0 = 一样
/// 边界: 非数字片段 (dev / 手改坏) 当 0 比; 段数不齐按 0 补 (1.2 vs 1.2.0 = 相等)
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split(RegExp(r'[^0-9]'))
      .where((s) => s.isNotEmpty)
      .map((s) => int.tryParse(s) ?? 0)
      .toList();
  final pa = parts(a);
  final pb = parts(b);
  final len = pa.length > pb.length ? pa.length : pb.length;
  for (var i = 0; i < len; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}
