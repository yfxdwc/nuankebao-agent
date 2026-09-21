// ============================================
// 管理员 · 用户总览模型 (手写, 不走 build_runner)
// ============================================
// 后端: GET /api/admin/users  → { users, nodes, summary }
//   - users = 全部**注册账号** (含会员 / 推荐码 / 加盟绑定)
//   - nodes = 全部**加盟节点** (含没有账号的历史节点, 否则图谱会断)
//   - 手机号只有打码值 (明文不出服务端)
//
// 主人 2026-09-21 拍: 管理员的「我的」→ 用户管理 (列表 + 图谱), 图谱区分
//   加盟 (接入了节点树的) / 未加盟 (独立节点); 付费会员头像上有会员标识
// ============================================

/// 会员状态 (role=admin 视为永久会员 → permanent=true)
class AdminMember {
  final bool isMember;
  final bool permanent;
  final String? until;

  const AdminMember({
    this.isMember = false,
    this.permanent = false,
    this.until,
  });

  factory AdminMember.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const AdminMember();
    return AdminMember(
      isMember: j['isMember'] == true,
      permanent: j['permanent'] == true,
      until: j['until']?.toString(),
    );
  }
}

/// 一个注册账号
class AdminUser {
  final String id;
  final String name;
  final String? username;
  final String role;
  final bool isActive;
  final String? avatarUrl;
  final String phoneMasked;
  final String? referralCode;
  final AdminMember member;

  /// null = 未加盟 (图谱里的独立节点)
  final String? franchiseeId;
  final String createdAt;

  const AdminUser({
    required this.id,
    required this.name,
    this.username,
    this.role = 'sales',
    this.isActive = true,
    this.avatarUrl,
    this.phoneMasked = '',
    this.referralCode,
    this.member = const AdminMember(),
    this.franchiseeId,
    this.createdAt = '',
  });

  bool get isAdmin => role == 'admin';
  bool get isJoined => franchiseeId != null;

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        username: j['username']?.toString(),
        role: j['role']?.toString() ?? 'sales',
        isActive: j['isActive'] != false,
        avatarUrl: j['avatarUrl']?.toString(),
        phoneMasked: j['phoneMasked']?.toString() ?? '',
        referralCode: j['referralCode']?.toString(),
        member: AdminMember.fromJson(
          j['member'] is Map ? Map<String, dynamic>.from(j['member'] as Map) : null,
        ),
        franchiseeId: j['franchiseeId']?.toString(),
        createdAt: j['createdAt']?.toString() ?? '',
      );

  /// 注册时间 (只显示到日; 空值不留白)
  String get createdDate {
    if (createdAt.isEmpty) return '';
    return createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;
  }
}

/// 一个加盟节点 (可能没有账号)
class AdminNode {
  final String fid;

  /// 节点名 = 加盟商名 (业务身份)
  final String name;

  /// 绑定账号的姓名 (与节点名不同时补一行)
  final String? accountName;
  final String? parentFid;
  final String? side;
  final int depth;

  /// 二叉树路径 (例: 'L.R.'; 树根 = '') —— 只在同一棵树内唯一
  /// 「改上层」选候选上层时用它算: ① 谁在她子树里 (不能选) ② 那条线是否有人
  final String path;

  /// 归属的加盟树 = 根节点编号 (同 rootFid 的一批节点才是同一棵树)
  final String rootFid;
  final bool isRoot;
  final String? userId;
  final String? avatarUrl;
  final bool member;

  const AdminNode({
    required this.fid,
    required this.name,
    this.accountName,
    this.parentFid,
    this.side,
    this.depth = 0,
    this.path = '',
    this.rootFid = '',
    this.isRoot = false,
    this.userId,
    this.avatarUrl,
    this.member = false,
  });

  bool get hasAccount => userId != null;

  /// 我在我的上层下面哪条线 ('left' = A线 / 'right' = B线; 空 = 树根)
  String? get sideFromPath {
    if (path.endsWith('L.')) return 'left';
    if (path.endsWith('R.')) return 'right';
    return null;
  }

  factory AdminNode.fromJson(Map<String, dynamic> j) => AdminNode(
        fid: j['fid']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        accountName: j['accountName']?.toString(),
        parentFid: j['parentFid']?.toString(),
        side: j['side']?.toString(),
        depth: (j['depth'] as num?)?.toInt() ?? 0,
        path: j['path']?.toString() ?? '',
        rootFid: j['rootFid']?.toString() ?? '',
        isRoot: j['isRoot'] == true,
        userId: j['userId']?.toString(),
        avatarUrl: j['avatarUrl']?.toString(),
        member: j['member'] == true,
      );
}

class AdminUsersSummary {
  final int total;
  final int joined;
  final int notJoined;
  final int members;
  final int roots;
  final int nodesWithoutAccount;

  const AdminUsersSummary({
    this.total = 0,
    this.joined = 0,
    this.notJoined = 0,
    this.members = 0,
    this.roots = 0,
    this.nodesWithoutAccount = 0,
  });

  factory AdminUsersSummary.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const AdminUsersSummary();
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return AdminUsersSummary(
      total: n('total'),
      joined: n('joined'),
      notJoined: n('notJoined'),
      members: n('members'),
      roots: n('roots'),
      nodesWithoutAccount: n('nodesWithoutAccount'),
    );
  }
}

class AdminUsersOverview {
  final List<AdminUser> users;
  final List<AdminNode> nodes;
  final AdminUsersSummary summary;

  const AdminUsersOverview({
    this.users = const [],
    this.nodes = const [],
    this.summary = const AdminUsersSummary(),
  });

  /// 未加盟账号 (图谱下半部分「独立节点」)
  List<AdminUser> get notJoinedUsers =>
      users.where((u) => !u.isJoined).toList(growable: false);

  factory AdminUsersOverview.fromJson(Map<String, dynamic> j) => AdminUsersOverview(
        users: (j['users'] as List? ?? [])
            .whereType<Map>()
            .map((e) => AdminUser.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
        nodes: (j['nodes'] as List? ?? [])
            .whereType<Map>()
            .map((e) => AdminNode.fromJson(Map<String, dynamic>.from(e)))
            .toList(growable: false),
        summary: AdminUsersSummary.fromJson(
          j['summary'] is Map ? Map<String, dynamic>.from(j['summary'] as Map) : null,
        ),
      );
}
