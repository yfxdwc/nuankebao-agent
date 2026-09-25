/// 客户推送 (Phase D / D-PRIV-3: 一期仅 Flutter)
///
/// 语义 (docs/customer-identity-system.md §6.5):
///   - 推送 = 归属人把**自己名下的客户**的可见性授予同枝某个下层 (不转移归属)
///   - 被推送人列表里出现该客户, 归属态 = `upline` → 文案「上级推送 · X」, 手机号明文 (D8)
///   - 可撤销 (需填原因); 禁止二次转发; 同一客户 active 推送 ≤ 5
library;

/// GET /api/customers/[id]/share/candidates 的一项
class ShareCandidate {
  final String userId;
  final String name;

  const ShareCandidate({required this.userId, required this.name});

  factory ShareCandidate.fromJson(Map<String, dynamic> json) => ShareCandidate(
        userId: (json['userId'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
      );
}

/// GET /api/customers/shares/received 的一项 (我收到的推送)
class ReceivedShare {
  final String customerId;
  final String customerName;
  final String fromUserId;
  final String? fromName;
  final String? note;

  const ReceivedShare({
    required this.customerId,
    required this.customerName,
    required this.fromUserId,
    this.fromName,
    this.note,
  });

  factory ReceivedShare.fromJson(Map<String, dynamic> json) => ReceivedShare(
        customerId: (json['customerId'] ?? '').toString(),
        customerName: (json['customerName'] ?? json['name'] ?? '').toString(),
        fromUserId: (json['fromUserId'] ?? '').toString(),
        fromName: json['fromName']?.toString(),
        note: json['note']?.toString(),
      );
}

/// 把推送 / 撤销失败的业务错误翻成人话 (Phase D §6.5 的 S1-S7 错误码)
///
/// 与 `humanClaimError` 同思路: 推送入口只有归属卡一处, 但错误码多, 集中一处维护。
String humanShareError(Object e) {
  final s = e.toString();
  if (s.contains('SHARE_NOT_OWNER')) return '只有归属人 (或管理员) 能推送';
  if (s.contains('TO_USER_NOT_IN_SAME_BRANCH')) return '只能推给同枝、位于你下层的同事';
  if (s.contains('ALREADY_SHARED')) return '已经推给过她 (撤销后可重推)';
  if (s.contains('SHARE_LIMIT_EXCEEDED')) return '这个客户已推给 5 个人, 先撤销一些';
  if (s.contains('DAILY_LIMIT_EXCEEDED')) return '今天推送条数已达上限 (100)';
  if (s.contains('REASON_REQUIRED')) return '撤销需要填原因';
  if (s.contains('403')) return '只有归属人 (或管理员) 能推送';
  if (s.contains('409')) return '已经推给过她 (撤销后可重推)';
  if (s.contains('404')) return '客户不存在或不在你的可见范围';
  return '操作失败: $e';
}
