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
        return '${initiatorName} 想把「${newName ?? "上级"}」认领为自己的**上级** '
            '(接在 ${targetParentName} 上方, 整棵树下降一层)';
      default:
        return '${initiatorName} 想把「${newName ?? "新加盟商"}」加到 ${targetParentName} 的${sideText}';
    }
  }

  bool get isUnjoin => kind == 'unjoin';

  /// 向上认领上级 (把现实里的上级接进 app)
  bool get isPromote => kind == 'promote';

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
