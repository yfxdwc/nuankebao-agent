// ============================================
// 客户归属模型 (管理维度, P7, 主人 2026-09-23)
// ============================================
// 对应后端 `GET /api/customers/[id]/ownership` → `getCustomerOwnership`
//
// 手写解析 (不引 freezed): 字段少 + 后端会演进, 缺字段要有兜底默认值
//
// ⚠ 口径说明 (ADR-0015 Q11): `owner_id` = "谁把她当客户在管" (谁的客户列表)。
//   与 `referrerId`(谁拉她进加盟) / `createdBy`(谁录入的) 是**三件不同的事**,
//   不要互相推导 —— 建档 ≠ 归属。
// ============================================

class CustomerOwnership {
  final String customerId;
  /// 归属人 user.id; null = 无归属
  final String? ownerId;
  final String? ownerName;
  /// 登录者就是归属人
  final bool isMine;
  /// 能不能认领 —— 与后端 `claimCustomerOwnership` 的放行条件一一对应
  final bool canClaim;
  /// 不能认领的原因 (人话); canClaim=true 时为 null
  final String? blockedReason;
  /// 一句话状态 (后端算好, 前端不拼文案 —— 免得两处措辞不一致)
  final String statusLabel;

  const CustomerOwnership({
    required this.customerId,
    this.ownerId,
    this.ownerName,
    this.isMine = false,
    this.canClaim = false,
    this.blockedReason,
    this.statusLabel = '',
  });

  factory CustomerOwnership.fromJson(Map<String, dynamic> json) {
    return CustomerOwnership(
      customerId: json['customerId']?.toString() ?? '',
      ownerId: json['ownerId']?.toString(),
      ownerName: json['ownerName'] as String?,
      isMine: (json['isMine'] as bool?) ?? false,
      canClaim: (json['canClaim'] as bool?) ?? false,
      blockedReason: json['blockedReason'] as String?,
      statusLabel: (json['statusLabel'] as String?) ?? '',
    );
  }

  /// 无归属 (谁都不在管)
  bool get hasNoOwner => ownerId == null;
}
