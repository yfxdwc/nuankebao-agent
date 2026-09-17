// ============================================
// 加盟商 model (Plan F2 手写版, 不依赖 freezed)
// 配套: ADR-0006 加盟体系 + 合规边界
// 边界: 不存任何金额字段 (入门费/佣金/对碰/层奖/见点/提成)
// ============================================

/// 加盟商 (用户 = 加盟商 = 销售员, 1:1)
class Franchisee {
  final String id;
  final String name;
  final String phone;

  /// 推荐人 (null = root 顶级加盟商)
  final String? referrerId;

  /// 位置 ('left' | 'right' | null=root)
  final String? placementSide;

  /// 二叉树 materialized path (例: 'L.R.L.')
  final String placementPath;

  /// 深度 (0 = root)
  final int placementDepth;

  final bool isActive;

  /// 备注 (建树时写, 编辑页可改)
  final String? notes;
  final DateTime? joinedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Franchisee({
    required this.id,
    required this.name,
    required this.phone,
    this.referrerId,
    this.placementSide,
    this.placementPath = '',
    this.placementDepth = 0,
    this.isActive = true,
    this.notes,
    this.joinedAt,
    this.createdAt,
    this.updatedAt,
  });

  factory Franchisee.fromJson(Map<String, dynamic> json) {
    return Franchisee(
      id: json['id']?.toString() ?? '',
      name: (json['name'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      referrerId: json['referrerId']?.toString(),
      placementSide: json['placementSide'] as String?,
      placementPath: (json['placementPath'] as String?) ?? '',
      placementDepth: (json['placementDepth'] as num?)?.toInt() ?? 0,
      isActive: json['isActive'] as bool? ?? true,
      notes: json['notes'] as String?,
      joinedAt: json['joinedAt'] != null ? DateTime.tryParse(json['joinedAt'].toString()) : null,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'].toString()) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'].toString()) : null,
    );
  }
}

/// 节点相对「我」的关系 (客户图谱三维区分: 线别 × 关系)
/// - root: 我自己 (树根)
/// - direct: 直推 (referrerId == 我)
/// - downline: 下级引荐 (我的下线引荐加盟的)
/// - upline: 上级引荐 (我不在推荐链上的, 上级引荐后放到我下线的; 含无推荐人异常数据)
enum FranchiseeRelation {
  root,
  direct,
  downline,
  upline;

  static FranchiseeRelation fromApi(String? raw) {
    switch (raw) {
      case 'direct':
        return FranchiseeRelation.direct;
      case 'downline':
        return FranchiseeRelation.downline;
      case 'upline':
        return FranchiseeRelation.upline;
      default:
        return FranchiseeRelation.root;
    }
  }

  /// 中文名 (UI 文案: 直推 / 下级引荐 / 上级引荐 / 我)
  String get label {
    switch (this) {
      case FranchiseeRelation.root:
        return '我';
      case FranchiseeRelation.direct:
        return '直推';
      case FranchiseeRelation.downline:
        return '下级引荐';
      case FranchiseeRelation.upline:
        return '上级引荐';
    }
  }
}

/// 树节点 (用于图谱视图, Plan F3 用)
class FranchiseeTreeNode {
  final String id;
  final String name;

  /// 谁推荐加盟 (直推判定源). null = 无推荐人
  final String? referrerId;
  final String? placementSide;
  final int placementDepth;

  /// 相对树根 (我) 的关系 (直推/下级引荐/上级引荐) — 由后端算好
  final FranchiseeRelation relation;
  final List<FranchiseeTreeNode> children;

  FranchiseeTreeNode({
    required this.id,
    required this.name,
    this.referrerId,
    required this.placementSide,
    required this.placementDepth,
    this.relation = FranchiseeRelation.root,
    required this.children,
  });

  factory FranchiseeTreeNode.fromJson(Map<String, dynamic> json) {
    return FranchiseeTreeNode(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      referrerId: json['referrerId']?.toString(),
      placementSide: json['placementSide'] as String?,
      placementDepth: (json['placementDepth'] as num?)?.toInt() ?? 0,
      relation: FranchiseeRelation.fromApi(json['relation'] as String?),
      children: ((json['children'] as List?) ?? [])
          .map((e) => FranchiseeTreeNode.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// 创建加盟商 input
class CreateFranchiseeInput {
  final String name;
  final String phone;
  final String? referrerId; // null = root (仅 admin 可)
  final String? sideHint; // 'left' | 'right'
  final String? notes;

  const CreateFranchiseeInput({
    required this.name,
    required this.phone,
    this.referrerId,
    this.sideHint,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'phone': phone,
        if (referrerId != null) 'referrerId': referrerId,
        if (sideHint != null) 'sideHint': sideHint,
        if (notes != null) 'notes': notes,
      };
}

/// 可用位置预览
class AvailablePosition {
  final bool leftOccupied;
  final bool rightOccupied;

  const AvailablePosition({
    required this.leftOccupied,
    required this.rightOccupied,
  });

  factory AvailablePosition.fromJson(Map<String, dynamic> json) =>
      AvailablePosition(
        leftOccupied: json['leftOccupied'] as bool? ?? false,
        rightOccupied: json['rightOccupied'] as bool? ?? false,
      );

  bool get hasLeftFree => !leftOccupied;
  bool get hasRightFree => !rightOccupied;
}