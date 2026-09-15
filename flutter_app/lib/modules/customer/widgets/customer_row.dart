// 客户列表行 (中老年版, 80pt 行高 + 大头像 + 待办点)
import 'package:flutter/material.dart';
import '../../../core/models/customer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/franchise_chip.dart';

class CustomerRow extends StatelessWidget {
  final Customer customer;
  final bool isFranchisee;
  final String? referrerName;
  final String? lastVisitDate;
  final int pendingCount;
  final VoidCallback onTap;

  const CustomerRow({
    super.key,
    required this.customer,
    required this.onTap,
    this.isFranchisee = false,
    this.referrerName,
    this.lastVisitDate,
    this.pendingCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppTheme.listRowHeight),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 大头像 (56pt)
            CircleAvatar(
              radius: AppTheme.avatarMd / 2,
              backgroundColor: isFranchisee
                  ? AppTheme.franchisee.withOpacity(0.2)
                  : AppTheme.primaryLight,
              child: Text(
                customer.name.isNotEmpty ? customer.name[0] : '?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: isFranchisee ? AppTheme.franchisee : AppTheme.primaryDark,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 中间信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 第一行: 姓名 + 加盟/普通徽章
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          customer.name,
                          style: const TextStyle(
                            fontSize: AppTheme.fontMd,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FranchiseChip(
                        type: isFranchisee ? 'franchisee' : 'normal',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 第二行: 上级 (加盟) 或 上次到店 (普通)
                  if (isFranchisee && referrerName != null)
                    Text(
                      '上级: $referrerName',
                      style: const TextStyle(
                        fontSize: AppTheme.fontXs,
                        color: AppTheme.franchisee,
                      ),
                    )
                  else if (lastVisitDate != null)
                    Text(
                      '上次到店 $lastVisitDate',
                      style: const TextStyle(
                        fontSize: AppTheme.fontXs,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            ),

            // 右侧: 待办红点
            if (pendingCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.danger,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '•$pendingCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTheme.fontXs,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right,
              color: AppTheme.textSecondary,
              size: 28,
            ),
          ],
        ),
      ),
    );
  }
}