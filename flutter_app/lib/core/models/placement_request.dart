// ============================================
// 加盟落位「三方确认」申请单 model (主人 2026-09-18 拍)
// 后端: src/lib/db/queries/franchisee-placement.ts + /api/franchisees/placement-requests
// ============================================

/// 三方确认角色
/// - initiator      设置者本人 (发起时自动记 1 票)
/// - new_franchisee 新加盟商本人 (create/promote 按手机号匹配; unjoin 是被解除节点本人)
/// - target_parent  新位置的上一个节点加盟商 (父节点 == 设置者时不需要;
///                  promote 的更特殊: app 里没有"上上层"这个人 → 也不需要)
class PlacementConfirm {
  final String role;
  final String decision; // approve | reject
  final String verifiedBy; // in_app | backfill
  final DateTime? decidedAt;

  const PlacementConfirm({
    required this.role,
    required this.decision,
    required this.verifiedBy,
    this.decidedAt,
  });

  factory PlacementConfirm.fromJson(Map<String, dynamic> json) {
    return PlacementConfirm(
      role: (json['role'] as String?) ?? '',
      decision: (json['decision'] as String?) ?? '',
      verifiedBy: (json['verifiedBy'] as String?) ?? 'in_app',
      decidedAt: json['decidedAt'] != null
          ? DateTime.tryParse(json['decidedAt'].toString())
          : null,
    );
  }
}

class PlacementRequest {
  final String id;
  final String kind; // create | unjoin | promote
  final String status; // pending | executed | rejected | expired | cancelled
  final String initiatorFid;
  final String initiatorName;
  final String? newName;
  /// unjoin 单: 要解除的加盟商节点 id / 名字 (字段名沿用后端 JSON: unjoinFid/unjoinName)
  final String? unjoinFid;
  final String? unjoinName;
  final String targetParentFid;
  final String targetParentName;
  /// promote 单: 认领的上级**已在 app 里**时的现存节点 id (null = 上级还没进 app)
  final String? uplineFid;
  /// promote 单: 上级节点名字
  final String? uplineName;
  /// promote 单: 上级**当前空着的**点位 (由上级本人在同意时挑一个; 两条都空才需他选)
  final List<String> availableSides;
  final String targetSide; // left | right
  final List<String> required;
  final List<PlacementConfirm> confirms;
  final String? myRole;
  final String? myDecision;
  /// 执行结果: create/promote → 新节点 id; unjoin → 被解除节点 id
  final String? resultFid;
  final bool backfilled;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  const PlacementRequest({
    required this.id,
    required this.kind,
    required this.status,
    required this.initiatorFid,
    required this.initiatorName,
    this.newName,
    this.unjoinFid,
    this.unjoinName,
    required this.targetParentFid,
    required this.targetParentName,
    this.uplineFid,
    this.uplineName,
    this.availableSides = const [],
    required this.targetSide,
    required this.required,
    required this.confirms,
    this.myRole,
    this.myDecision,
    this.resultFid,
    this.backfilled = false,
    this.expiresAt,
    this.createdAt,
  });

  factory PlacementRequest.fromJson(Map<String, dynamic> json) {
    return PlacementRequest(
      id: json['id']?.toString() ?? '',
      kind: (json['kind'] as String?) ?? 'create',
      status: (json['status'] as String?) ?? 'pending',
      initiatorFid: json['initiatorFid']?.toString() ?? '',
      initiatorName: (json['initiatorName'] as String?) ?? '?',
      newName: json['newName'] as String?,
      unjoinFid: (json['unjoinFid'] ?? json['moveFid'])?.toString(),
      unjoinName: (json['unjoinName'] ?? json['moveName']) as String?,
      targetParentFid: json['targetParentFid']?.toString() ?? '',
      targetParentName: (json['targetParentName'] as String?) ?? '?',
      uplineFid: json['uplineFid']?.toString(),
      uplineName: json['uplineName'] as String?,
      availableSides: ((json['availableSides'] as List?) ?? [])
          .map((e) => e.toString())
          .toList(),
      targetSide: (json['targetSide'] as String?) ?? 'left',
      required: ((json['required'] as List?) ?? []).map((e) => e.toString()).toList(),
      confirms: ((json['confirms'] as List?) ?? [])
          .map((e) => PlacementConfirm.fromJson(e as Map<String, dynamic>))
          .toList(),
      myRole: json['myRole'] as String?,
      myDecision: json['myDecision'] as String?,
      resultFid: json['resultFid']?.toString(),
      backfilled: json['backfilled'] as bool? ?? false,
      expiresAt: json['expiresAt'] != null
          ? DateTime.tryParse(json['expiresAt'].toString())
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  /// 左/右 → A线/B线 (主人 2026-09-17 命名)
  static String sideLabel(String side) => side == 'left' ? 'A线' : 'B线';

  /// 角色中文名
  static String roleLabel(String role) {
    switch (role) {
      case 'initiator':
        return '设置者';
      case 'new_franchisee':
        return '本人';
      case 'target_parent':
        return '上级';
      default:
        return role;
    }
  }

  String get sideText => sideLabel(targetSide);

  /// 一句话说明 (列表里显示)
  String get summary {
    switch (kind) {
      case 'unjoin':
        return '${initiatorName} 想解除「${unjoinName ?? "加盟商"}」的加盟';
      case 'promote':
        // 往上长 (主人 2026-09-21 拍 B2): 我是现根, 把现实里的直接上级拉进来当我上面这层
        // 主人拍: 「我在上级的 A线/B线 由上级自己决定」→ 文案不提线别, 由上级挑
        return '${initiatorName} 想把「${newName ?? "上级"}」认领为自己的上级 '
            '(接在 ${targetParentName} 上方, 整棵树下降一层; '
            '放在她的哪条线由她本人定)';
      default:
        return '${initiatorName} 想把「${newName ?? "新加盟商"}」加到 ${targetParentName} 的${sideText}';
    }
  }

  bool get isUnjoin => kind == 'unjoin';

  /// 向上认领上级 (把现实里的上级接进 app)
  bool get isPromote => kind == 'promote';

  /// 我这张 promote 单要不要先挑线再同意 (主人拍 ④):
  ///   只有**上级本人**且两条线都空时才要他选; 只剩一条空位 → 服务端自动落那一条
  bool get needsSidePick =>
      isPromote && myRole == 'new_franchisee' && availableSides.length >= 2;

  /// 「移动到其他点位」已下线 (主人 2026-09-19 拍): 老存量单只读展示, 不再产生新单

  int get approvedCount =>
      confirms.where((c) => c.decision == 'approve').length;

  int get requiredCount => required.length;

  bool get isPending => status == 'pending';

  /// 还在等我拍板 (有我的角色 + 我还没表态)
  bool get awaitingMe => isPending && myRole != null && myDecision == null;

  /// 管理员单 (免多方确认): 不显示 "1/0 方已确认" 这种怪话
  String get progressText => requiredCount == 0
      ? '管理员设置, 免多方确认'
      : '$approvedCount/$requiredCount 方已确认';
}

// ============================================
// 直推者候选 (Phase B §6 E1, docs/customer-identity-system.md)
// GET /api/franchisees/placement-requests/candidates?targetParentId=xxx
// 返回落位后**她的祖先链** = targetParent 本身 + 其上层直系 3 层
// ============================================

/// 单个候选直推者
class ReferrerCandidate {
  /// 节点 id (字符串大整数)
  final String id;

  /// 姓名 (前端直接展示)
  final String name;

  /// 该候选的绝对层号 (相对所在树根, 根=0)
  final int depth;

  /// 该候选相对 targetParent 的层数 (0 = 自己, 1 = 直接上层, 2 = 上 2 层, 3 = 上 3 层)
  final int level;

  /// 是否就是发起人 (actor.fid == this.id); 前端默认高亮「我」
  final bool isSelf;

  const ReferrerCandidate({
    required this.id,
    required this.name,
    required this.depth,
    required this.level,
    required this.isSelf,
  });

  factory ReferrerCandidate.fromJson(Map<String, dynamic> json) {
    return ReferrerCandidate(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '?',
      depth: (json['depth'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 0,
      isSelf: json['isSelf'] == true,
    );
  }

  /// 人话标签 (前端展示用)
  ///   level=0: 目标点位父 (「张姐」)
  ///   level=1: 「张姐的直接上级 — 李总」
  ///   level=2: 「李总的上级 — 王总」
  String get levelLabel {
    switch (level) {
      case 0:
        return '目标点位父';
      case 1:
        return '直接上层';
      case 2:
        return '上 2 层';
      case 3:
        return '上 3 层';
      default:
        return '上层 #$level';
    }
  }
}

/// 直推者候选响应
class ReferrerCandidatesResponse {
  /// targetParent 的 id (字符串)
  final String targetParentId;

  /// 候选列表 (由近到远: targetParent 自身 → 上 1 层 → 上 2 层 → 上 3 层)
  final List<ReferrerCandidate> candidates;

  /// 服务端推荐默认直推者 (发起人在链内 → 她; 否则 = targetParent)
  final String defaultReferrerFid;

  /// 发起人 (actor.fid) 是否在候选链内 (admin 也不该"自己推荐自己")
  final bool actorInCandidates;

  const ReferrerCandidatesResponse({
    required this.targetParentId,
    required this.candidates,
    required this.defaultReferrerFid,
    required this.actorInCandidates,
  });

  factory ReferrerCandidatesResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['candidates'] as List?) ?? const [];
    return ReferrerCandidatesResponse(
      targetParentId: (json['targetParentId'] as String?) ?? '',
      candidates: list
          .map((e) => ReferrerCandidate.fromJson(e as Map<String, dynamic>))
          .toList(),
      defaultReferrerFid: (json['defaultReferrerFid'] as String?) ?? '',
      actorInCandidates: json['actorInCandidates'] == true,
    );
  }
}
