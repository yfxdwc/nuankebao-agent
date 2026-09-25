import 'package:freezed_annotation/freezed_annotation.dart';

import 'me.dart' show kAvatarPresetIds;

part 'customer.freezed.dart';
part 'customer.g.dart';

@freezed
class Customer with _$Customer {
  const factory Customer({
    required String id,
    required String name,
    required String phone,
    String? gender, // M / F / U
    int? birthYear,
    /// 生日月/日 (1-12 / 1-31); null = 不知道 (可只知年份/只知月日)
    /// 主人 2026-09-18 拍: 年月日 都可缺
    int? birthMonth,
    int? birthDay,
    /// 历法: 'solar' 阳历 / 'lunar' 农历 (默认太阳历)
    @Default('solar') String birthCalendar,
    /// 生日提醒强度 (天数): 7 / 3 / 0(当天); null = 不提醒
    /// 业务规则: 月+日 都有 = 开启提醒
    int? birthdayRemindDays,
    @Default([]) List<String> healthTags,
    String? diseaseHistory,
    /// 过敏史 (2026-09-18 新增; 跟既往病史分开)
    String? allergyHistory,
    /// 客户头像 (主人 2026-09-18 拍): null = 默认首字 / 'preset:x' / '/uploads/x.jpg'
    /// 未知值一律当 null (UI 退回首字, 不渲染白框)
    // ignore: invalid_annotation_target
    @JsonKey(fromJson: _parseAvatarValue) String? avatar,
    String? notes,
    /// 客户推荐人 (客户页图谱数据源), null = 无推荐人 (根/孤儿节点)
    String? referrerId,
    /// 种子客户标记 (显式勾选, 主人 2026-09-18). 老后端不返回该字段 → 默认 false
    @Default(false) bool isSeed,
    /// 客户类型 (混合判定, 后端算好): franchisee 加盟 / seed 种子 / normal 普通
    /// 优先级: 加盟 > 种子 > 普通 (加盟表派生 > is_seed > 默认)
    /// 老后端不返回该字段 → 默认 'normal'
    @Default('normal') String customerType,
    /// ★ 这条档案对应一个 app 账号吗 (ADR-0016 D8, 主人 2026-09-22 拍「UI 上要有区别」):
    ///   true = 她是已注册用户 (user.customer_id 指过来) / false = 凭空建档的客户
    ///   老后端不返回 → 默认 false (退化成旧视觉, 不崩)
    @Default(false) bool hasAccount,
    /// ★ 她的邀请码 (2026-09-24 管理 Tab 建议 #6): 有账号才有; 没有账号 = null。
    ///   管理 Tab「app 身份」卡直接显示 + 一键复制 (拉她进沙龙 / 核对身份用)。
    ///   老后端不返回该字段 → null (卡上不显示那行, 不崩)
    String? accountReferralCode,
    // ─── Phase A/C 客户标识体系 v1 (§1 维度 1/5/6, docs/customer-identity-system.md) ───
    /// 加盟细分: "none" 未加盟 / "direct" 加盟·直推 / "nondirect" 加盟·非直推。
    /// 单一真相源 = 后端 src/lib/customer/identity.ts (走 referrer 口径, 与图谱同源)。
    /// 老后端不返回 → 默认 "none"。头像环 (TypedUserAvatar) 据此区分色。
    @Default('none') String affiliation,
    /// 归属五态 (§3.4 五态):
    ///   "mine" 自己的客户 (静默, 不出 L2 归属 badge)
    ///   "subordinate" 下级的客户 (走 §3.4 (b1)/(b2) 判定)
    ///   "upline" 上级推送的客户 (Phase D 才有数据)
    ///   "other" 他人客户 (scope 漏检告警)
    ///   "none" 无归属
    /// 列表默认 mine 静默, 异常态显形 (设计 §4.2 L2 五态)。
    @Default('none') String ownership,
    /// 归属人姓名 (「下级的客户 · 张三」用; Phase D 后端返回, 无归属 = null)
    String? ownerName,
    /// 上级推送人姓名 (「上级推送 · 张三」用; 仅 ownership = "upline" 有值)
    String? sharedByName,
    /// 客户来源 (§1 维度 6 + §5 migration 0026, 主人 2026-09-25 D5 拍「选填」):
    ///   null / "friend" 亲友 / "referral" 转介绍 / "cold_visit" 陌生拜访 / "ground_promo" 地推
    ///   referral 时 referrerName 必填 (后端 zod refine 校验, §5 M3, 不加 DB CHECK)
    /// 老后端不返回 → 默认 null (= 未填写, 不报错)。
    String? acquireSource,
    /// 转介绍介绍人姓名 (≤ 50 字, 与后端 source_referrer_name 对齐):
    ///   仅 acquireSource = 'referral' 时有值; 其他情况 = null
    /// 后端 zod refine 保证 referral 时此字段非空 (否则 400)。
    String? sourceReferrerName,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Customer;

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);
}

/// 头像值兜底 (只认 preset: / /uploads/, 跟 user 头像同一套约定; 见 src/lib/avatar.ts)
/// 跟 MeUser 的解析一致 —— 但那边是 private, 这里复制一份 (模型层不互相依赖逻辑)
String? _parseAvatarValue(dynamic raw) {
  if (raw is! String) return null;
  final v = raw.trim();
  if (v.isEmpty) return null;
  if (v.startsWith('preset:')) {
    final id = v.substring('preset:'.length);
    return kAvatarPresetIds.contains(id) ? 'preset:$id' : null;
  }
  if (v.startsWith('/uploads/') && !v.contains('..') && v.length <= 200) {
    return v;
  }
  return null;
}
