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

/// 待确认的落位点位 (三方确认工作流; 只挂在树的根节点上)
///   - 图谱里画成「虚线虚位」, 点位 pending 期间预占 (别人抢不到)
class PendingPlacement {
  final String requestId;
  final String targetParentFid;
  final String targetSide; // left | right
  final String label; // 「张三 (待确认)」/「节点 #12 (待移动)」
  final String initiatorFid;

  const PendingPlacement({
    required this.requestId,
    required this.targetParentFid,
    required this.targetSide,
    required this.label,
    required this.initiatorFid,
  });

  factory PendingPlacement.fromJson(Map<String, dynamic> json) {
    return PendingPlacement(
      requestId: json['requestId']?.toString() ?? '',
      targetParentFid: json['targetParentFid']?.toString() ?? '',
      targetSide: (json['targetSide'] as String?) ?? 'left',
      label: (json['label'] as String?) ?? '待确认',
      initiatorFid: json['initiatorFid']?.toString() ?? '',
    );
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

  /// 子树内「待确认」的落位点位 (只有根节点会带; 图谱画虚位用)
  final List<PendingPlacement> pendingPlacements;

  /// 该节点是否有下级 (**全深度真值**, 不受本次请求 depth 限制) — ADR-0011 懒加载
  /// true + children.isEmpty = 还没展开, 前端给「展开下级」入口
  final bool hasChildren;

  /// 仅树根有: 我的下级全深度总数 (不受 depth 影响; 顶部「共 N 位」用)
  final int? totalDescendants;

  /// 会员标识 (主人 2026-09-21 拍: 「会员在别人的图谱里也要有明显标识」)
  ///   口径 = 该节点绑定账号是不是会员 (role=admin 或 member_until > now()), 后端每次现算
  ///   → 充值转会员 / 到期掉会员, 下次拉树即变 (无需同步任务)
  ///   老后端不返回该字段 → 默认 false (非会员/无账号)
  final bool member;

  FranchiseeTreeNode({
    required this.id,
    required this.name,
    this.referrerId,
    required this.placementSide,
    required this.placementDepth,
    this.relation = FranchiseeRelation.root,
    required this.children,
    this.hasChildren = false,
    this.totalDescendants,
    this.pendingPlacements = const [],
    this.member = false,
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
      hasChildren: json['hasChildren'] as bool? ?? false,
      totalDescendants: (json['totalDescendants'] as num?)?.toInt(),
      pendingPlacements: ((json['pendingPlacements'] as List?) ?? [])
          .map((e) => PendingPlacement.fromJson(e as Map<String, dynamic>))
          .toList(),
      member: json['member'] as bool? ?? false,
    );
  }

  /// 拷贝 + 替换 children (懒加载合并用; 不 mutate 原对象, 保持 provider 树干净)
  FranchiseeTreeNode copyWith({
    List<FranchiseeTreeNode>? children,
    bool? hasChildren,
  }) {
    return FranchiseeTreeNode(
      id: id,
      name: name,
      referrerId: referrerId,
      placementSide: placementSide,
      placementDepth: placementDepth,
      relation: relation,
      children: children ?? this.children,
      hasChildren: hasChildren ?? this.hasChildren,
      totalDescendants: totalDescendants,
      // ★ 修 (主人 2026-09-19 虚位可点排查发现): copyWith 漏带 pendingPlacements →
      //   _withLazyChildren 拷贝根节点后「待确认虚位」整个消失 (图谱不画 + 点不到)
      pendingPlacements: pendingPlacements,
      member: member,
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