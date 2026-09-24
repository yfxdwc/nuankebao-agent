// ============================================
// 审计条目 (客户档案的改动记录, 2026-09-24)
//
// 来源: `GET /api/customers/:id/audit` (管理 Tab「最近改动」)
//
// ⚠ 后端**只给"改了哪些列"(列名), 不给列值** —— 列值可能是密文/手机号/病史,
//   没必要透到前端。中文标签由 UI 侧映射 (见 audit_trail_card.dart)。
// ============================================

import 'package:freezed_annotation/freezed_annotation.dart';

part 'audit_entry.freezed.dart';
part 'audit_entry.g.dart';

@freezed
class AuditEntry with _$AuditEntry {
  const factory AuditEntry({
    required String id,
    /// INSERT / UPDATE / DELETE (触发器原始操作名)
    required String operation,
    /// 发生变化的列名 (INSERT/DELETE = 整行所有列)
    @Default([]) List<String> changedColumns,
    /// 操作人姓名; null = 系统 / 脚本 / dev skip-auth
    String? actorName,
    required DateTime createdAt,
  }) = _AuditEntry;

  factory AuditEntry.fromJson(Map<String, dynamic> json) =>
      _$AuditEntryFromJson(json);
}
