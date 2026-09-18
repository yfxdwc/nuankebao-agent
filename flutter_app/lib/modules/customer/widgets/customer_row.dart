// 客户列表行 (中老年版, 80pt 行高 + 大头像 + 待办点)
import 'package:flutter/material.dart';
import '../../../core/models/customer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/franchise_chip.dart';
import '../../../core/utils/birthday.dart';

class CustomerRow extends StatelessWidget {
  final Customer customer;
  /// @deprecated 改用 [customerType] (保留兼容旧调用点; 两者不一致时以 customerType 为准)
  final bool isFranchisee;
  /// 客户类型徽章: franchisee 加盟 / seed 种子 / normal 普通
  /// null = 回退到 [isFranchisee] 推导 (老调用点)
  final String? customerType;
  final String? referrerName;
  final String? lastVisitDate;
  final int pendingCount;
  final VoidCallback onTap;

  const CustomerRow({
    super.key,
    required this.customer,
    required this.onTap,
    this.isFranchisee = false,
    this.customerType,
    this.referrerName,
    this.lastVisitDate,
    this.pendingCount = 0,
  });

  /// 距离生日还有几天 (只在「她设的提醒窗口内」返回, 否则 null → 不显示徽章)
  int? get _birthdayDays {
    final c = customer;
    if (c.birthMonth == null || c.birthDay == null) return null;
    if (c.birthdayRemindDays == null) return null;
    final d = daysUntilBirthday(
      month: c.birthMonth,
      day: c.birthDay,
      calendar: c.birthCalendar,
    );
    if (d == null || d > c.birthdayRemindDays!) return null;
    return d;
  }

  /// 实际展示的类型: 显式 customerType > customer 模型里的 customerType 字段 > isFranchisee 推导
  String get _type {
    final t = customerType ?? customer.customerType;
    if (t.isNotEmpty) return t;
    return isFranchisee ? 'franchisee' : 'normal';
  }

  @override
  Widget build(BuildContext context) {
    final isFranchisee = _type == 'franchisee';
    final isSeed = _type == 'seed';
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
                  : (isSeed
                      ? AppTheme.accent.withOpacity(0.2)
                      : AppTheme.primaryLight),
              child: Text(
                customer.name.isNotEmpty ? customer.name[0] : '?',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: isFranchisee
                      ? AppTheme.franchisee
                      : (isSeed ? AppTheme.accent : AppTheme.primaryDark),
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
                      FranchiseChip(type: _type),
                      // 🎂 生日提醒 (落在她设的提醒窗口内才显示; 主人 2026-09-18 拍)
                      if (_birthdayDays != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            _birthdayDays == 0 ? '🎂 今天' : '🎂 ${_birthdayDays}天',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: AppTheme.fontXs,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // 第二行: 上级 (加盟) 或 上次到店 (普通/种子)
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