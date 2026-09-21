// ============================================
// 客户跟进信息 (客户列表用) — 手写模型, 不依赖代码生成
// ============================================
// 为什么手写: 本机 build_runner 代码生成坏了 (.dart_tool/build_resolvers/sdk.sum 生成不出来),
// freezed/json_serializable 跑不动 → 新增模型一律手写 fromJson (见 docs/backlog.md ②)
//
// 后端口径 (docs/follow-up-list-plan.md + 主人 2026-09-20 拍板):
//   - 分数/级别/理由: **仅会员** (非会员为 null → 前端显示 🔒, 不显示空白)
//   - 标签 tags: 免费档拿非会员标签 (该回访了/新客首访/掉线了/久未联系), 会员额外有生日/复购
//   - 排序: 紧急度只给会员; 非会员请求 → 后端降级 + urgencyLocked=true

import 'customer.dart';

/// 推荐标签 (名字右侧; 最多 2 个 = 1 动作 + 1 日历)
class FollowUpTagInfo {
  final String key;
  final String emoji;
  final String label;
  /// danger / accent / franchisee / primary
  final String color;
  final String hint;

  const FollowUpTagInfo({
    required this.key,
    required this.emoji,
    required this.label,
    required this.color,
    required this.hint,
  });

  factory FollowUpTagInfo.fromJson(Map<String, dynamic> json) {
    return FollowUpTagInfo(
      key: (json['key'] as String?) ?? '',
      emoji: (json['emoji'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      color: (json['color'] as String?) ?? 'primary',
      hint: (json['hint'] as String?) ?? '',
    );
  }

  static const empty = FollowUpTagInfo(
    key: '',
    emoji: '',
    label: '',
    color: 'primary',
    hint: '',
  );
}

/// 跟进信息块 (后端 lib/follow-up/attach.ts 下发)
class FollowUpInfo {
  /// 距上次联系 (天); null = 从没联系过
  final int? daysSinceContact;
  final DateTime? lastContactAt;
  final String? lastContactType;
  final int? daysSinceVisit;
  final DateTime? lastVisitAt;
  final int openTaskCount;
  final DateTime? nextDueAt;
  final List<FollowUpTagInfo> tags;

  /// ↓ 会员专属 (非会员 = null)
  final int? urgency;
  final String? level;
  final String? levelLabel;
  final String? reason;

  const FollowUpInfo({
    this.daysSinceContact,
    this.lastContactAt,
    this.lastContactType,
    this.daysSinceVisit,
    this.lastVisitAt,
    this.openTaskCount = 0,
    this.nextDueAt,
    this.tags = const [],
    this.urgency,
    this.level,
    this.levelLabel,
    this.reason,
  });

  factory FollowUpInfo.fromJson(Map<String, dynamic> json) {
    return FollowUpInfo(
      daysSinceContact: (json['daysSinceContact'] as num?)?.toInt(),
      lastContactAt: _parseDate(json['lastContactAt']),
      lastContactType: json['lastContactType'] as String?,
      daysSinceVisit: (json['daysSinceVisit'] as num?)?.toInt(),
      lastVisitAt: _parseDate(json['lastVisitAt']),
      openTaskCount: (json['openTaskCount'] as num?)?.toInt() ?? 0,
      nextDueAt: _parseDate(json['nextDueAt']),
      tags: ((json['tags'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .map(FollowUpTagInfo.fromJson)
          .where((t) => t.label.isNotEmpty)
          .toList(),
      urgency: (json['urgency'] as num?)?.toInt(),
      level: json['level'] as String?,
      levelLabel: json['levelLabel'] as String?,
      reason: json['reason'] as String?,
    );
  }

  /// 是否会员视角 (后端给不给分数)
  bool get hasScore => urgency != null;

  /// 主标签 (显示在名字右侧第一个)
  FollowUpTagInfo? get primaryTag => tags.isEmpty ? null : tags.first;

  /// 第二行文案: 「21 天没联系 · 上次电话」 (主人 2026-09-20 拍 Q3: 数据放第二行)
  String? get contactLine {
    final d = daysSinceContact;
    if (d == null) return '还没联系过';
    if (d == 0) return '今天联系过';
    if (d == 1) return '昨天联系过';
    final label = '${d} 天没联系';
    final type = _contactTypeLabel(lastContactType);
    return type == null ? label : '$label · 上次$type';
  }

  /// 紧急度色条颜色 key (P0-P4); 非会员 = null (不显示色条)
  String? get levelKey => hasScore ? level : null;
}

String? _contactTypeLabel(String? type) {
  switch (type) {
    case 'phone':
      return '电话';
    case 'wechat':
      return '微信';
    case 'visit':
      return '到店';
    case 'holiday_greeting':
      return '节日问候';
    case 'other':
      return '联系';
    default:
      return null;
  }
}

DateTime? _parseDate(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

/// 客户 + 跟进信息 (列表行数据)
class CustomerWithFollowUp {
  final Customer customer;
  final FollowUpInfo? followUp;

  /// 会员标识 (主人 2026-09-21 拍): 后端 /api/customers 每条现算 (同手机号账号的会员状态)
  ///
  /// 为什么挂在这里而不是 freezed 的 Customer 上: `Customer` 是 freezed 生成的,
  ///   而本仓 build_runner 当前不可用 (`docs/backlog.md` ②: .dart_tool/build_resolvers/sdk.sum
  ///   缺失 → freezed/json_serializable 无法重新生成)。列表行加字段走手写模型 = 零代码生成。
  ///   `Customer` 收到多余 JSON key 会被 json_serializable 忽略, 安全。
  final bool isMember;

  const CustomerWithFollowUp({
    required this.customer,
    this.followUp,
    this.isMember = false,
  });
}

/// 列表顶部提醒条 / 分组计数 (仅会员; 后端 summarizeFollowUp)
class FollowUpSummary {
  final int dueToday;     // P0 今天必须联系
  final int overdue;      // 有逾期任务
  final int thisWeek;     // P1 本周
  final int hibernating;  // P4 休眠
  final int total;

  const FollowUpSummary({
    required this.dueToday,
    required this.overdue,
    required this.thisWeek,
    required this.hibernating,
    required this.total,
  });

  static const zero = FollowUpSummary(
    dueToday: 0,
    overdue: 0,
    thisWeek: 0,
    hibernating: 0,
    total: 0,
  );

  factory FollowUpSummary.fromJson(Map<String, dynamic> json) => FollowUpSummary(
        dueToday: (json['dueToday'] as num?)?.toInt() ?? 0,
        overdue: (json['overdue'] as num?)?.toInt() ?? 0,
        thisWeek: (json['thisWeek'] as num?)?.toInt() ?? 0,
        hibernating: (json['hibernating'] as num?)?.toInt() ?? 0,
        total: (json['total'] as num?)?.toInt() ?? 0,
      );

  bool get isEmpty => dueToday == 0 && overdue == 0 && thisWeek == 0;
}

/// 列表接口返回 (含排序元信息)
class CustomerListResult {
  final List<CustomerWithFollowUp> items;
  final int total;
  /// 实际生效的排序 (非会员请求紧急度 → 降级为 new)
  final String sort;
  /// 用户是否请求了紧急度但被会员墙挡住 → 前端显示 🔒 + 升级提示
  final bool urgencyLocked;
  /// 顶部提醒条计数 (仅会员有)
  final FollowUpSummary? summary;

  const CustomerListResult({
    required this.items,
    required this.total,
    required this.sort,
    required this.urgencyLocked,
    this.summary,
  });

  static const empty = CustomerListResult(
    items: [],
    total: 0,
    sort: 'new',
    urgencyLocked: false,
  );

  factory CustomerListResult.fromJson(Map<String, dynamic> json) {
    final raw = (json['items'] as List?) ?? [];
    return CustomerListResult(
      items: raw.whereType<Map<String, dynamic>>().map((m) {
        return CustomerWithFollowUp(
          customer: Customer.fromJson(m),
          followUp: m['followUp'] is Map<String, dynamic>
              ? FollowUpInfo.fromJson(m['followUp'] as Map<String, dynamic>)
              : null,
          isMember: m['isMember'] as bool? ?? false,
        );
      }).toList(),
      total: (json['total'] as num?)?.toInt() ?? raw.length,
      sort: (json['sort'] as String?) ?? 'new',
      urgencyLocked: json['urgencyLocked'] == true,
      summary: json['summary'] is Map<String, dynamic>
          ? FollowUpSummary.fromJson(json['summary'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// 客户跟进分析 (详情页「跟进分析」卡; 方案 §7.1)
///   后端 GET /api/customers/:id/follow-up-analysis
///   客观指标**免费**; AI 解读是会员 (走既有 POST /api/ai/follow-up → `aiTipAvailable`)
class FollowUpAnalysis {
  /// 近 30 天联系次数 (今天起往前 30 个日历天)
  final int contactLast30;
  /// 近 90 天联系次数
  final int contactLast90;
  final int contactTotal;
  /// 平均联系间隔 (中位数, 天); null = 联系少于 2 次
  final int? avgContactIntervalDays;
  final int? daysSinceLastContact;

  /// warmer (变热) / colder (变冷) / steady (稳定) / unknown (还看不出)
  final String trend;
  final String trendText;

  final int visitCount;
  final int? avgVisitIntervalDays;
  final DateTime? lastVisitAt;
  final int? daysSinceLastVisit;
  final int? medianRepurchaseIntervalDays;

  final int pendingTasks;
  final int overdueTasks;
  final int? oldestOverdueDays;

  /// 一句话总结 (免费层, 服务端纯规则拼的)
  final String headline;
  /// 有没有资格看 AI 解读 (会员)
  final bool aiTipAvailable;

  const FollowUpAnalysis({
    this.contactLast30 = 0,
    this.contactLast90 = 0,
    this.contactTotal = 0,
    this.avgContactIntervalDays,
    this.daysSinceLastContact,
    this.trend = 'unknown',
    this.trendText = '',
    this.visitCount = 0,
    this.avgVisitIntervalDays,
    this.lastVisitAt,
    this.daysSinceLastVisit,
    this.medianRepurchaseIntervalDays,
    this.pendingTasks = 0,
    this.overdueTasks = 0,
    this.oldestOverdueDays,
    this.headline = '',
    this.aiTipAvailable = false,
  });

  factory FollowUpAnalysis.fromJson(Map<String, dynamic> json) {
    return FollowUpAnalysis(
      contactLast30: (json['contactLast30'] as num?)?.toInt() ?? 0,
      contactLast90: (json['contactLast90'] as num?)?.toInt() ?? 0,
      contactTotal: (json['contactTotal'] as num?)?.toInt() ?? 0,
      avgContactIntervalDays: (json['avgContactIntervalDays'] as num?)?.toInt(),
      daysSinceLastContact: (json['daysSinceLastContact'] as num?)?.toInt(),
      trend: (json['trend'] as String?) ?? 'unknown',
      trendText: (json['trendText'] as String?) ?? '',
      visitCount: (json['visitCount'] as num?)?.toInt() ?? 0,
      avgVisitIntervalDays: (json['avgVisitIntervalDays'] as num?)?.toInt(),
      lastVisitAt: _parseDate(json['lastVisitAt']),
      daysSinceLastVisit: (json['daysSinceLastVisit'] as num?)?.toInt(),
      medianRepurchaseIntervalDays:
          (json['medianRepurchaseIntervalDays'] as num?)?.toInt(),
      pendingTasks: (json['pendingTasks'] as num?)?.toInt() ?? 0,
      overdueTasks: (json['overdueTasks'] as num?)?.toInt() ?? 0,
      oldestOverdueDays: (json['oldestOverdueDays'] as num?)?.toInt(),
      headline: (json['headline'] as String?) ?? '',
      aiTipAvailable: json['aiTipAvailable'] == true,
    );
  }

  /// 趋势是好是坏 (给颜色用): 变热=好, 变冷=警示
  bool get isColder => trend == 'colder';
  bool get isWarmer => trend == 'warmer';
}
