// ============================================
// 客户档案「最近改动」卡 (管理 Tab, 2026-09-24 建议 #2)
//
// 为什么需要: 归属转移 / 合并 / 身份绑定 / 归档都是"动了别人东西"的操作,
//   在审计接口出现之前**没人能回答"谁改的、什么时候改的"**。
//   数据来自 `GET /api/customers/:id/audit` (Postgres 触发器写的 audit_log)。
//
// ⚠ 只展示「改了哪些列」(列名 → 中文标签), **不展示列值** —— 列值里可能是
//   pgcrypto 密文 / 手机号 / 病史 (后端也刻意不返回)。
//
// autoDispose provider: 切走 Tab 再回来会重新拉 → 天然看到最新改动。
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/audit_entry.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/tokens.g.dart';
import '../../../core/widgets/b2_no_chrome.dart';

/// 列名 → 中文标签 (audit_log.changed_fields 的 key 是**数据库列名**)
const Map<String, String> _columnLabels = {
  'name': '姓名',
  'phone_encrypted': '手机号',
  'gender': '性别',
  'birth_year': '出生年',
  'birth_month': '生日(月)',
  'birth_day': '生日(日)',
  'birth_calendar': '历法',
  'birthday_remind_days': '生日提醒',
  'health_tags_encrypted': '健康标签',
  'disease_history_encrypted': '既往病史',
  'allergy_history_encrypted': '过敏史',
  'notes_encrypted': '备注',
  'avatar': '头像',
  'is_seed': '种子标记',
  'owner_id': '归属',
  'deleted_at': '归档',
  'last_visit_at': '最近到店',
  'last_interaction_at': '最近联系',
  'phone_hash': '手机号',
};

/// 这些列每次 UPDATE 都会变 (噪音), 不参与"修改了什么"的展示
const Set<String> _noisyColumns = {'updated_at', 'created_at'};

class CustomerAuditCard extends ConsumerWidget {
  const CustomerAuditCard({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customerAuditProvider(customerId));
    final t = context.tokens;

    return B2NoChrome(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.cardPadding),
        child: async.when(
          loading: () => Row(
            children: [
              SizedBox(
                width: AppSpace.s18,
                height: AppSpace.s18,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: AppSpace.s8),
              Text('读取改动记录…',
                  style: TextStyle(fontSize: AppType.sm, color: t.textSecondary)),
            ],
          ),
          error: (e, _) => Row(
            children: [
              Expanded(
                child: Text('加载失败: $e',
                    style: TextStyle(fontSize: AppType.sm, color: t.danger)),
              ),
              TextButton(
                onPressed: () => ref.invalidate(customerAuditProvider(customerId)),
                child: const Text('重试'),
              ),
            ],
          ),
          data: (items) => items.isEmpty
              ? Text('还没有改动记录',
                  style: TextStyle(fontSize: AppType.sm, color: t.textTertiary))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpace.s8),
                      _AuditRow(entry: items[i]),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final when = DateFormat('MM-dd HH:mm').format(entry.createdAt.toLocal());
    final who = (entry.actorName?.trim().isNotEmpty ?? false)
        ? entry.actorName!.trim()
        : '系统';

    // 操作 → 人话 (INSERT = 建档 / DELETE = 归档 / UPDATE = 修改了 X、Y)
    final String what;
    if (entry.operation == 'INSERT') {
      what = '建档';
    } else if (entry.operation == 'DELETE') {
      what = '归档 (删除)';
    } else {
      final labels = <String>[];
      for (final col in entry.changedColumns) {
        if (_noisyColumns.contains(col)) continue;
        final label = _columnLabels[col] ?? col;
        if (!labels.contains(label)) labels.add(label);
      }
      what = labels.isEmpty ? '保存' : '修改了 ${labels.join('、')}';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.history, size: AppSize.iconSm, color: t.textTertiary),
        const SizedBox(width: AppSpace.s6),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$when ',
                  style: TextStyle(fontSize: AppType.xs, color: t.textTertiary),
                ),
                TextSpan(
                  text: '$who ',
                  style: TextStyle(
                    fontSize: AppType.xs,
                    fontWeight: AppWeight.semibold,
                    color: t.textPrimary,
                  ),
                ),
                TextSpan(
                  text: what,
                  style: TextStyle(fontSize: AppType.xs, color: t.textSecondary),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
