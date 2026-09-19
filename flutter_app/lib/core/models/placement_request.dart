// ============================================
// 加盟落位「三方确认」申请单 model (主人 2026-09-18 拍)
// 后端: src/lib/db/queries/franchisee-placement.ts + /api/franchisees/placement-requests
// ============================================

/// 三方确认角色
/// - initiator      设置者本人 (发起时自动记 1 票)
/// - new_franchisee 新加盟商本人 (create 按手机号匹配; move 是被移动节点本人)
/// - target_parent  新位置的上一个节点加盟商 (父节点 == 设置者时不需要)
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
  final String kind; // create | move
  final String status; // pending | executed | rejected | expired | cancelled
  final String initiatorFid;
  final String initiatorName;
  final String? newName;
  final String? moveFid;
  final String? moveName;
  final String targetParentFid;
  final String targetParentName;
  final String targetSide; // left | right
  final List<String> required;
  final List<PlacementConfirm> confirms;
  final String? myRole;
  final String? myDecision;
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
    this.moveFid,
    this.moveName,
    required this.targetParentFid,
    required this.targetParentName,
    required this.targetSide,
    required this.required,
    required this.confirms,
    this.myRole,
    this.myDecision,
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
      moveFid: json['moveFid']?.toString(),
      moveName: json['moveName'] as String?,
      targetParentFid: json['targetParentFid']?.toString() ?? '',
      targetParentName: (json['targetParentName'] as String?) ?? '?',
      targetSide: (json['targetSide'] as String?) ?? 'left',
      required: ((json['required'] as List?) ?? []).map((e) => e.toString()).toList(),
      confirms: ((json['confirms'] as List?) ?? [])
          .map((e) => PlacementConfirm.fromJson(e as Map<String, dynamic>))
          .toList(),
      myRole: json['myRole'] as String?,
      myDecision: json['myDecision'] as String?,
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
        return '${initiatorName} 想解除「${moveName ?? "加盟商"}」的加盟';
      case 'move':
        return '${initiatorName} 想把「${moveName ?? "节点"}」挪到 ${targetParentName} 的${sideText}';
      default:
        return '${initiatorName} 想把「${newName ?? "新加盟商"}」加到 ${targetParentName} 的${sideText}';
    }
  }

  bool get isUnjoin => kind == 'unjoin';

  int get approvedCount =>
      confirms.where((c) => c.decision == 'approve').length;

  int get requiredCount => required.length;

  bool get isPending => status == 'pending';

  /// 还在等我拍板 (有我的角色 + 我还没表态)
  bool get awaitingMe => isPending && myRole != null && myDecision == null;

  String get progressText => '$approvedCount/$requiredCount 方已确认';
}
