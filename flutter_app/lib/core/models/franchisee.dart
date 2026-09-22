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

  /// 推荐人 (null = root 顶级加盟商) —— 「谁把她拉进来的」
  ///
  /// ⚠ 与 [placementParentId] 是两件事 (拆栏 2026-09-21, ADR-0014 §3.9):
  /// 「推荐人那侧满了 → BFS 顺延到别人名下」时两者可以不是同一个人
  final String? referrerId;

  /// 点位父 (她的"上层点位") —— 「她挂在谁下面」= 详情页「上级加盟商」卡
  /// (null = 树根, 没有上层)
  final String? placementParentId;

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
    this.placementParentId,
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
      placementParentId: json['placementParentId']?.toString(),
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

/// 我的「上层点位」= **点位父** (不是推荐码提供人!) —— 主人 2026-09-21 拍
///   图谱在「我」上面画这一个节点; 每个用户有且只有一个上层节点。
///   - 后端 `GET /franchisees/me/tree?mode=placement` 顶层 `upline` 字段
///   - null = 我是 app 这棵树的根 (上层虚位以待) → 只有这种用户能去「认领上级」
///   - ⚠ 上层一旦有人就不可撤换 (联系系统管理员协商处理, 仓内无换上层入口)
class FranchiseeUpline {
  final String id;
  final String name;
  /// 我在她下面的线别 (left = A线 / right = B线)
  final String? side;
  final int depth;
  final bool member;

  const FranchiseeUpline({
    required this.id,
    required this.name,
    required this.side,
    required this.depth,
    this.member = false,
  });

  factory FranchiseeUpline.fromJson(Map<String, dynamic> json) =>
      FranchiseeUpline(
        id: json['id']?.toString() ?? '',
        name: (json['name'] as String?) ?? '',
        side: json['side'] as String?,
        depth: (json['depth'] as num?)?.toInt() ?? 0,
        member: json['member'] as bool? ?? false,
      );

  String get sideLabel => side == 'right' ? 'B线' : 'A线';
}

/// 我发起、还在等上级本人确认的「认领上级」单 (图谱上层那格显示「待她确认」)
class UplineRequest {
  final String id;
  final String? newName;
  final String? uplineFid;

  const UplineRequest({required this.id, this.newName, this.uplineFid});

  factory UplineRequest.fromJson(Map<String, dynamic> json) => UplineRequest(
        id: json['id']?.toString() ?? '',
        newName: json['newName'] as String?,
        uplineFid: json['uplineFid']?.toString(),
      );
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

  /// 我的「上层点位」(只有返回树的根节点有; 见 [FranchiseeUpline])
  ///   null = 上层虚位以待 (我是树根, 可以去认领一位上级进来)
  ///   ⚠ 兼容旧字段; 新代码用 [uplines] (上 3 层)
  final FranchiseeUpline? upline;

  /// 上层直系链 (ADR-0015 Q13, 主人 2026-09-22 拍「上行最多 3 层直系」)
  ///   由近到远 (level 1 = 直接上层); 我是树根 = 空列表
  ///   老后端只返回单条 `upline` → 退化为 `[upline]` (长度 1), 不崩
  final List<FranchiseeUpline> uplines;

  /// 我发起的认领上级单 (还在等上级本人确认) — 只有根节点有
  final UplineRequest? uplineRequest;

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
    this.upline,
    this.uplines = const [],
    this.uplineRequest,
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
      upline: json['upline'] == null
          ? null
          : FranchiseeUpline.fromJson(json['upline'] as Map<String, dynamic>),
      // 新字段 uplines (上 3 层); 老后端没有 → 用单条 upline 退化 (长度 1)
      uplines: (() {
        final raw = json['uplines'];
        if (raw is List && raw.isNotEmpty) {
          return raw
              .whereType<Map<String, dynamic>>()
              .map(FranchiseeUpline.fromJson)
              .toList();
        }
        final single = json['upline'];
        if (single is Map<String, dynamic>) {
          return [FranchiseeUpline.fromJson(single)];
        }
        return const <FranchiseeUpline>[];
      })(),
      uplineRequest: json['uplineRequest'] == null
          ? null
          : UplineRequest.fromJson(
              json['uplineRequest'] as Map<String, dynamic>),
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
      // ★ 同 pendingPlacements 的教训: copyWith 漏带 → 懒加载拷贝根节点后整格消失
      upline: upline,
      // ★ 同上: 上 3 层直系链必须一起带 (漏了 = 懒加载后只剩 1 层旧字段)
      uplines: uplines,
      uplineRequest: uplineRequest,
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