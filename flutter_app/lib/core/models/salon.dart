// ============================================
// 沙龙 model (手写版, 不依赖 freezed)
// 配套: v0.1.5 Phase 7 沙龙模块 (主人 2026-09-18 拍: 完整方案)
// ============================================
// 三种角色: 主理人 (organizer) / 会务 (staff) / 受邀者 (attendee)
// 核心机制: 受邀者 RSVP + 自报「预计带约人数」; 主理人可分配带约任务
// 边界: 受邀者允许非 app 用户 (姓名 + 手机号); 手机号仅主理人/会务/本人可见
// ============================================

/// 沙龙状态
enum SalonStatus {
  draft,
  published,
  registrationClosed,
  ongoing,
  finished,
  cancelled;

  static SalonStatus fromApi(String? raw) {
    switch (raw) {
      case 'draft':
        return SalonStatus.draft;
      case 'published':
        return SalonStatus.published;
      case 'registration_closed':
        return SalonStatus.registrationClosed;
      case 'ongoing':
        return SalonStatus.ongoing;
      case 'finished':
        return SalonStatus.finished;
      case 'cancelled':
        return SalonStatus.cancelled;
      default:
        return SalonStatus.draft;
    }
  }

  String get apiValue {
    switch (this) {
      case SalonStatus.draft:
        return 'draft';
      case SalonStatus.published:
        return 'published';
      case SalonStatus.registrationClosed:
        return 'registration_closed';
      case SalonStatus.ongoing:
        return 'ongoing';
      case SalonStatus.finished:
        return 'finished';
      case SalonStatus.cancelled:
        return 'cancelled';
    }
  }

  String get label {
    switch (this) {
      case SalonStatus.draft:
        return '草稿';
      case SalonStatus.published:
        return '报名中';
      case SalonStatus.registrationClosed:
        return '报名已截止';
      case SalonStatus.ongoing:
        return '进行中';
      case SalonStatus.finished:
        return '已结束';
      case SalonStatus.cancelled:
        return '已取消';
    }
  }

  /// 是否还能编辑/邀请 (草稿/报名中/截止后也可改名单)
  bool get isEditable =>
      this == SalonStatus.draft ||
      this == SalonStatus.published ||
      this == SalonStatus.registrationClosed ||
      this == SalonStatus.ongoing;
}

/// 受邀者 RSVP 状态
enum SalonInvitationStatus {
  pending,
  accepted,
  tentative,
  declined,
  waitlist,
  attended,
  absent,
  cancelled;

  static SalonInvitationStatus fromApi(String? raw) {
    switch (raw) {
      case 'accepted':
        return SalonInvitationStatus.accepted;
      case 'tentative':
        return SalonInvitationStatus.tentative;
      case 'declined':
        return SalonInvitationStatus.declined;
      case 'waitlist':
        return SalonInvitationStatus.waitlist;
      case 'attended':
        return SalonInvitationStatus.attended;
      case 'absent':
        return SalonInvitationStatus.absent;
      case 'cancelled':
        return SalonInvitationStatus.cancelled;
      default:
        return SalonInvitationStatus.pending;
    }
  }

  String get label {
    switch (this) {
      case SalonInvitationStatus.pending:
        return '待回复';
      case SalonInvitationStatus.accepted:
        return '已接受';
      case SalonInvitationStatus.tentative:
        return '待定';
      case SalonInvitationStatus.declined:
        return '已婉拒';
      case SalonInvitationStatus.waitlist:
        return '候补';
      case SalonInvitationStatus.attended:
        return '已到场';
      case SalonInvitationStatus.absent:
        return '未到场';
      case SalonInvitationStatus.cancelled:
        return '已撤销';
    }
  }
}

/// 二级客人状态
enum SalonGuestStatus {
  pending,
  accepted,
  declined,
  attended,
  absent,
  cancelled;

  static SalonGuestStatus fromApi(String? raw) {
    switch (raw) {
      case 'accepted':
        return SalonGuestStatus.accepted;
      case 'declined':
        return SalonGuestStatus.declined;
      case 'attended':
        return SalonGuestStatus.attended;
      case 'absent':
        return SalonGuestStatus.absent;
      case 'cancelled':
        return SalonGuestStatus.cancelled;
      default:
        return SalonGuestStatus.pending;
    }
  }

  String get label {
    switch (this) {
      case SalonGuestStatus.pending:
        return '待确认';
      case SalonGuestStatus.accepted:
        return '会来';
      case SalonGuestStatus.declined:
        return '不来了';
      case SalonGuestStatus.attended:
        return '已到场';
      case SalonGuestStatus.absent:
        return '未到场';
      case SalonGuestStatus.cancelled:
        return '已取消';
    }
  }
}

/// 日程条目
class SalonAgendaItem {
  final String? start;
  final String? end;
  final String title;
  final String? desc;

  SalonAgendaItem({this.start, this.end, required this.title, this.desc});

  factory SalonAgendaItem.fromJson(Map<String, dynamic> json) => SalonAgendaItem(
        start: json['start'] as String?,
        end: json['end'] as String?,
        title: (json['title'] as String?) ?? '',
        desc: json['desc'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (start != null && start!.isNotEmpty) 'start': start,
        if (end != null && end!.isNotEmpty) 'end': end,
        'title': title,
        if (desc != null && desc!.isNotEmpty) 'desc': desc,
      };
}

/// 报名表单动态字段定义
class SalonFormField {
  final String key;
  final String label;
  final String type; // text / number / select / multiselect / textarea / date / boolean
  final bool required;
  final List<String> options;
  final String? placeholder;

  SalonFormField({
    required this.key,
    required this.label,
    this.type = 'text',
    this.required = false,
    this.options = const [],
    this.placeholder,
  });

  factory SalonFormField.fromJson(Map<String, dynamic> json) => SalonFormField(
        key: (json['key'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
        type: (json['type'] as String?) ?? 'text',
        required: json['required'] as bool? ?? false,
        options: ((json['options'] as List?) ?? [])
            .map((e) => e.toString())
            .toList(),
        placeholder: json['placeholder'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type,
        if (required) 'required': true,
        if (options.isNotEmpty) 'options': options,
        if (placeholder != null && placeholder!.isNotEmpty) 'placeholder': placeholder,
      };
}

/// 可见性设置
class SalonVisibilitySettings {
  /// 受邀者名单谁可见: all / staff / organizer
  final String attendeeList;

  /// 会务联系方式谁可见: all / staff
  final String staffContact;

  const SalonVisibilitySettings({
    this.attendeeList = 'all',
    this.staffContact = 'all',
  });

  factory SalonVisibilitySettings.fromJson(Map<String, dynamic> json) =>
      SalonVisibilitySettings(
        attendeeList: (json['attendeeList'] as String?) ?? 'all',
        staffContact: (json['staffContact'] as String?) ?? 'all',
      );

  Map<String, dynamic> toJson() => {
        'attendeeList': attendeeList,
        'staffContact': staffContact,
      };
}

/// 统计
class SalonCounts {
  final int invitedTotal;
  final int accepted;
  final int declined;
  final int tentative;
  final int pending;
  final int waitlist;
  final int attended;
  final int absent;
  final int staffCount;
  /// 受邀者自报预计带约总人数
  final int expectedGuests;
  /// 已登记二级客人数
  final int guestRegistered;
  final int guestAttended;
  final int? capacityTotal;
  final int? capacityRemaining;

  const SalonCounts({
    this.invitedTotal = 0,
    this.accepted = 0,
    this.declined = 0,
    this.tentative = 0,
    this.pending = 0,
    this.waitlist = 0,
    this.attended = 0,
    this.absent = 0,
    this.staffCount = 0,
    this.expectedGuests = 0,
    this.guestRegistered = 0,
    this.guestAttended = 0,
    this.capacityTotal,
    this.capacityRemaining,
  });

  factory SalonCounts.fromJson(Map<String, dynamic> json) => SalonCounts(
        invitedTotal: (json['invitedTotal'] as num?)?.toInt() ?? 0,
        accepted: (json['accepted'] as num?)?.toInt() ?? 0,
        declined: (json['declined'] as num?)?.toInt() ?? 0,
        tentative: (json['tentative'] as num?)?.toInt() ?? 0,
        pending: (json['pending'] as num?)?.toInt() ?? 0,
        waitlist: (json['waitlist'] as num?)?.toInt() ?? 0,
        attended: (json['attended'] as num?)?.toInt() ?? 0,
        absent: (json['absent'] as num?)?.toInt() ?? 0,
        staffCount: (json['staffCount'] as num?)?.toInt() ?? 0,
        expectedGuests: (json['expectedGuests'] as num?)?.toInt() ?? 0,
        guestRegistered: (json['guestRegistered'] as num?)?.toInt() ?? 0,
        guestAttended: (json['guestAttended'] as num?)?.toInt() ?? 0,
        capacityTotal: (json['capacityTotal'] as num?)?.toInt(),
        capacityRemaining: (json['capacityRemaining'] as num?)?.toInt(),
      );

  /// 预计总到场 = 已接受 + 已到场 + 自报带约人数
  int get expectedTotalAttendance => accepted + attended + expectedGuests;
}

/// 「我」在这个沙龙里的身份/状态
class SalonViewerContext {
  final bool isOrganizer;
  final bool isStaff;
  final String? myInvitationId;
  final SalonInvitationStatus? myStatus;
  final String? myRole; // organizer / staff / attendee
  final int? myExpectedGuestCount;
  final int? myQuotaValue;
  final DateTime? myQuotaDeadlineAt;

  const SalonViewerContext({
    this.isOrganizer = false,
    this.isStaff = false,
    this.myInvitationId,
    this.myStatus,
    this.myRole,
    this.myExpectedGuestCount,
    this.myQuotaValue,
    this.myQuotaDeadlineAt,
  });

  factory SalonViewerContext.fromJson(Map<String, dynamic> json) =>
      SalonViewerContext(
        isOrganizer: json['isOrganizer'] as bool? ?? false,
        isStaff: json['isStaff'] as bool? ?? false,
        myInvitationId: json['myInvitationId']?.toString(),
        myStatus: json['myStatus'] != null
            ? SalonInvitationStatus.fromApi(json['myStatus'] as String?)
            : null,
        myRole: json['myRole'] as String?,
        myExpectedGuestCount: (json['myExpectedGuestCount'] as num?)?.toInt(),
        myQuotaValue: (json['myQuotaValue'] as num?)?.toInt(),
        myQuotaDeadlineAt: json['myQuotaDeadlineAt'] != null
            ? DateTime.tryParse(json['myQuotaDeadlineAt'].toString())
            : null,
      );

  /// 管理权限 = 主理人 或 会务
  bool get canManage => isOrganizer || isStaff;

  String get roleLabel {
    if (isOrganizer) return '主理人';
    if (isStaff) return '会务';
    return '受邀者';
  }
}

/// 沙龙 (列表 / 详情共用)
class Salon {
  final String id;
  final String title;
  final String? subtitle;
  final String? description;
  final String? coverUrl;
  final List<String> themeTags;
  final String organizerUserId;
  final String? organizerName;
  final String? organizerAvatar;
  final SalonStatus status;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime? registrationDeadlineAt;
  final String timezone;

  final String? locationName;
  final String? address;
  final String? floorRoom;
  final String? lat;
  final String? lng;
  final String? parkingInfo;

  final String? transportPublic;
  final String? transportDriving;
  final String? transportPickup;

  final String? cateringMealType;
  final String? cateringCuisine;
  final String? cateringDietary;
  final String? cateringTime;
  final String? cateringPayer;

  final String? lodgingHotelName;
  final String? lodgingRoomType;
  final int? lodgingPriceCents;
  final String? lodgingContactName;
  final String? lodgingContactPhone;
  final DateTime? lodgingDeadlineAt;
  final String? lodgingNote;

  final String? dressCode;
  final String feeType;
  final int? feeAmountCents;
  final String? feeNote;

  final int? capacityTotal;
  final int capacityReserved;

  final List<SalonAgendaItem> agenda;
  final List<SalonFormField> registrationFormSchema;
  final SalonVisibilitySettings visibilitySettings;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  final SalonViewerContext viewer;
  final SalonCounts counts;

  Salon({
    required this.id,
    required this.title,
    this.subtitle,
    this.description,
    this.coverUrl,
    this.themeTags = const [],
    required this.organizerUserId,
    this.organizerName,
    this.organizerAvatar,
    this.status = SalonStatus.draft,
    this.startAt,
    this.endAt,
    this.registrationDeadlineAt,
    this.timezone = 'Asia/Shanghai',
    this.locationName,
    this.address,
    this.floorRoom,
    this.lat,
    this.lng,
    this.parkingInfo,
    this.transportPublic,
    this.transportDriving,
    this.transportPickup,
    this.cateringMealType,
    this.cateringCuisine,
    this.cateringDietary,
    this.cateringTime,
    this.cateringPayer,
    this.lodgingHotelName,
    this.lodgingRoomType,
    this.lodgingPriceCents,
    this.lodgingContactName,
    this.lodgingContactPhone,
    this.lodgingDeadlineAt,
    this.lodgingNote,
    this.dressCode,
    this.feeType = 'free',
    this.feeAmountCents,
    this.feeNote,
    this.capacityTotal,
    this.capacityReserved = 0,
    this.agenda = const [],
    this.registrationFormSchema = const [],
    this.visibilitySettings = const SalonVisibilitySettings(),
    this.createdAt,
    this.updatedAt,
    this.viewer = const SalonViewerContext(),
    this.counts = const SalonCounts(),
  });

  factory Salon.fromJson(Map<String, dynamic> json) {
    return Salon(
      id: json['id']?.toString() ?? '',
      title: (json['title'] as String?) ?? '',
      subtitle: json['subtitle'] as String?,
      description: json['description'] as String?,
      coverUrl: json['coverUrl'] as String?,
      themeTags: ((json['themeTags'] as List?) ?? [])
          .map((e) => e.toString())
          .toList(),
      organizerUserId: json['organizerUserId']?.toString() ?? '',
      organizerName: json['organizerName'] as String?,
      organizerAvatar: json['organizerAvatar'] as String?,
      status: SalonStatus.fromApi(json['status'] as String?),
      startAt: json['startAt'] != null
          ? DateTime.tryParse(json['startAt'].toString())?.toLocal()
          : null,
      endAt: json['endAt'] != null
          ? DateTime.tryParse(json['endAt'].toString())?.toLocal()
          : null,
      registrationDeadlineAt: json['registrationDeadlineAt'] != null
          ? DateTime.tryParse(json['registrationDeadlineAt'].toString())?.toLocal()
          : null,
      timezone: (json['timezone'] as String?) ?? 'Asia/Shanghai',
      locationName: json['locationName'] as String?,
      address: json['address'] as String?,
      floorRoom: json['floorRoom'] as String?,
      lat: json['lat']?.toString(),
      lng: json['lng']?.toString(),
      parkingInfo: json['parkingInfo'] as String?,
      transportPublic: json['transportPublic'] as String?,
      transportDriving: json['transportDriving'] as String?,
      transportPickup: json['transportPickup'] as String?,
      cateringMealType: json['cateringMealType'] as String?,
      cateringCuisine: json['cateringCuisine'] as String?,
      cateringDietary: json['cateringDietary'] as String?,
      cateringTime: json['cateringTime'] as String?,
      cateringPayer: json['cateringPayer'] as String?,
      lodgingHotelName: json['lodgingHotelName'] as String?,
      lodgingRoomType: json['lodgingRoomType'] as String?,
      lodgingPriceCents: (json['lodgingPriceCents'] as num?)?.toInt(),
      lodgingContactName: json['lodgingContactName'] as String?,
      lodgingContactPhone: json['lodgingContactPhone'] as String?,
      lodgingDeadlineAt: json['lodgingDeadlineAt'] != null
          ? DateTime.tryParse(json['lodgingDeadlineAt'].toString())?.toLocal()
          : null,
      lodgingNote: json['lodgingNote'] as String?,
      dressCode: json['dressCode'] as String?,
      feeType: (json['feeType'] as String?) ?? 'free',
      feeAmountCents: (json['feeAmountCents'] as num?)?.toInt(),
      feeNote: json['feeNote'] as String?,
      capacityTotal: (json['capacityTotal'] as num?)?.toInt(),
      capacityReserved: (json['capacityReserved'] as num?)?.toInt() ?? 0,
      agenda: ((json['agenda'] as List?) ?? [])
          .map((e) => SalonAgendaItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      registrationFormSchema: ((json['registrationFormSchema'] as List?) ?? [])
          .map((e) => SalonFormField.fromJson(e as Map<String, dynamic>))
          .toList(),
      visibilitySettings: json['visibilitySettings'] != null
          ? SalonVisibilitySettings.fromJson(
              json['visibilitySettings'] as Map<String, dynamic>)
          : const SalonVisibilitySettings(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())?.toLocal()
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())?.toLocal()
          : null,
      viewer: json['viewer'] != null
          ? SalonViewerContext.fromJson(json['viewer'] as Map<String, dynamic>)
          : SalonViewerContext(),
      counts: json['counts'] != null
          ? SalonCounts.fromJson(json['counts'] as Map<String, dynamic>)
          : SalonCounts(),
    );
  }

  /// 费用文案
  String get feeLabel {
    switch (feeType) {
      case 'aa':
        return 'AA 制';
      case 'organizer_pays':
        return '主理人请客';
      case 'paid':
        return feeAmountCents != null
            ? '收费 ¥${(feeAmountCents! / 100).toStringAsFixed(0)}'
            : '收费';
      default:
        return '免费';
    }
  }

  /// 餐饮文案
  String get cateringLabel {
    switch (cateringMealType) {
      case 'breakfast':
        return '含早餐';
      case 'lunch':
        return '含午餐';
      case 'dinner':
        return '含晚餐';
      case 'tea':
        return '含茶歇';
      case 'none':
        return '不含餐';
      default:
        return '待定';
    }
  }

  /// 地址一行
  String get addressLine {
    final parts = <String>[
      if (locationName != null && locationName!.isNotEmpty) locationName!,
      if (floorRoom != null && floorRoom!.isNotEmpty) floorRoom!,
      if (address != null && address!.isNotEmpty) address!,
    ];
    return parts.join(' · ');
  }
}

/// 邀请 (受邀者 / 会务)
class SalonInvitation {
  final String id;
  final String salonId;
  final String? inviteeUserId;
  final String inviteeName;
  final String? inviteePhone;
  final String roleInSalon; // organizer / staff / attendee
  final String? staffRole;
  final String? invitedByUserId;
  final SalonInvitationStatus status;
  final int expectedGuestCount;
  final int? actualGuestCount;
  final DateTime? respondedAt;
  final String? notes;
  final Map<String, dynamic>? registrationData;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SalonInvitation({
    required this.id,
    required this.salonId,
    this.inviteeUserId,
    required this.inviteeName,
    this.inviteePhone,
    this.roleInSalon = 'attendee',
    this.staffRole,
    this.invitedByUserId,
    this.status = SalonInvitationStatus.pending,
    this.expectedGuestCount = 0,
    this.actualGuestCount,
    this.respondedAt,
    this.notes,
    this.registrationData,
    this.createdAt,
    this.updatedAt,
  });

  factory SalonInvitation.fromJson(Map<String, dynamic> json) => SalonInvitation(
        id: json['id']?.toString() ?? '',
        salonId: json['salonId']?.toString() ?? '',
        inviteeUserId: json['inviteeUserId']?.toString(),
        inviteeName: (json['inviteeName'] as String?) ?? '',
        inviteePhone: json['inviteePhone'] as String?,
        roleInSalon: (json['roleInSalon'] as String?) ?? 'attendee',
        staffRole: json['staffRole'] as String?,
        invitedByUserId: json['invitedByUserId']?.toString(),
        status: SalonInvitationStatus.fromApi(json['status'] as String?),
        expectedGuestCount: (json['expectedGuestCount'] as num?)?.toInt() ?? 0,
        actualGuestCount: (json['actualGuestCount'] as num?)?.toInt(),
        respondedAt: json['respondedAt'] != null
            ? DateTime.tryParse(json['respondedAt'].toString())?.toLocal()
            : null,
        notes: json['notes'] as String?,
        registrationData: json['registrationData'] as Map<String, dynamic>?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString())?.toLocal()
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'].toString())?.toLocal()
            : null,
      );

  bool get isStaff => roleInSalon == 'staff';
  bool get isAppUser => inviteeUserId != null;
}

/// 二级客人 (非 app 用户)
class SalonGuest {
  final String id;
  final String salonId;
  final String broughtByUserId;
  final String? broughtByName;
  final String name;
  final String? phone;
  final String? relation;
  final SalonGuestStatus status;
  final bool actualAttended;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SalonGuest({
    required this.id,
    required this.salonId,
    required this.broughtByUserId,
    this.broughtByName,
    required this.name,
    this.phone,
    this.relation,
    this.status = SalonGuestStatus.pending,
    this.actualAttended = false,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  factory SalonGuest.fromJson(Map<String, dynamic> json) => SalonGuest(
        id: json['id']?.toString() ?? '',
        salonId: json['salonId']?.toString() ?? '',
        broughtByUserId: json['broughtByUserId']?.toString() ?? '',
        broughtByName: json['broughtByName'] as String?,
        name: (json['name'] as String?) ?? '',
        phone: json['phone'] as String?,
        relation: json['relation'] as String?,
        status: SalonGuestStatus.fromApi(json['status'] as String?),
        actualAttended: json['actualAttended'] as bool? ?? false,
        notes: json['notes'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString())?.toLocal()
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'].toString())?.toLocal()
            : null,
      );

  String get relationLabel {
    switch (relation) {
      case 'client':
        return '客户';
      case 'friend':
        return '朋友';
      case 'family':
        return '家人';
      case 'colleague':
        return '同事';
      case 'other':
        return '其他';
      default:
        return '未填';
    }
  }
}

/// 带约任务
class SalonQuota {
  final String id;
  final String salonId;
  final String assignedToUserId;
  final String? assignedToName;
  final int quotaValue;
  final DateTime? deadlineAt;
  final String? note;
  final bool isActive;
  final String createdByUserId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int expectedGuestCount;
  final int guestCount;
  final int progress;

  SalonQuota({
    required this.id,
    required this.salonId,
    required this.assignedToUserId,
    this.assignedToName,
    required this.quotaValue,
    this.deadlineAt,
    this.note,
    this.isActive = true,
    required this.createdByUserId,
    this.createdAt,
    this.updatedAt,
    this.expectedGuestCount = 0,
    this.guestCount = 0,
    this.progress = 0,
  });

  factory SalonQuota.fromJson(Map<String, dynamic> json) => SalonQuota(
        id: json['id']?.toString() ?? '',
        salonId: json['salonId']?.toString() ?? '',
        assignedToUserId: json['assignedToUserId']?.toString() ?? '',
        assignedToName: json['assignedToName'] as String?,
        quotaValue: (json['quotaValue'] as num?)?.toInt() ?? 0,
        deadlineAt: json['deadlineAt'] != null
            ? DateTime.tryParse(json['deadlineAt'].toString())?.toLocal()
            : null,
        note: json['note'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        createdByUserId: json['createdByUserId']?.toString() ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString())?.toLocal()
            : null,
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'].toString())?.toLocal()
            : null,
        expectedGuestCount: (json['expectedGuestCount'] as num?)?.toInt() ?? 0,
        guestCount: (json['guestCount'] as num?)?.toInt() ?? 0,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
      );

  /// 完成率 0~1
  double get ratio => quotaValue <= 0 ? 0 : (progress / quotaValue).clamp(0, 1);
  bool get isFulfilled => progress >= quotaValue;
}

/// 动态
class SalonActivity {
  final String id;
  final String salonId;
  final String authorUserId;
  final String? authorName;
  final String? authorAvatar;
  final String type; // system / announcement / question / comment
  final String content;
  final Map<String, dynamic>? metadata;
  final String visibility; // all / staff / organizer
  final DateTime? createdAt;

  SalonActivity({
    required this.id,
    required this.salonId,
    required this.authorUserId,
    this.authorName,
    this.authorAvatar,
    this.type = 'comment',
    required this.content,
    this.metadata,
    this.visibility = 'all',
    this.createdAt,
  });

  factory SalonActivity.fromJson(Map<String, dynamic> json) => SalonActivity(
        id: json['id']?.toString() ?? '',
        salonId: json['salonId']?.toString() ?? '',
        authorUserId: json['authorUserId']?.toString() ?? '',
        authorName: json['authorName'] as String?,
        authorAvatar: json['authorAvatar'] as String?,
        type: (json['type'] as String?) ?? 'comment',
        content: (json['content'] as String?) ?? '',
        metadata: json['metadata'] as Map<String, dynamic>?,
        visibility: (json['visibility'] as String?) ?? 'all',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString())?.toLocal()
            : null,
      );
}

/// 沙龙资料
class SalonAttachment {
  final String id;
  final String salonId;
  final String name;
  final String fileUrl;
  final String fileType; // image / file
  final String visibility;
  final String? uploadedByUserId;
  final DateTime? createdAt;

  SalonAttachment({
    required this.id,
    required this.salonId,
    required this.name,
    required this.fileUrl,
    this.fileType = 'image',
    this.visibility = 'all',
    this.uploadedByUserId,
    this.createdAt,
  });

  factory SalonAttachment.fromJson(Map<String, dynamic> json) => SalonAttachment(
        id: json['id']?.toString() ?? '',
        salonId: json['salonId']?.toString() ?? '',
        name: (json['name'] as String?) ?? '',
        fileUrl: (json['fileUrl'] as String?) ?? '',
        fileType: (json['fileType'] as String?) ?? 'image',
        visibility: (json['visibility'] as String?) ?? 'all',
        uploadedByUserId: json['uploadedByUserId']?.toString(),
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString())?.toLocal()
            : null,
      );
}

/// 聚合统计 (主理人视角 = counts + 带约总额)
class SalonAggregates extends SalonCounts {
  final int quotaAssignees;
  final int quotaTotal;
  final int quotaExpectedTotal;
  final int quotaGuestTotal;

  SalonAggregates({
    super.invitedTotal,
    super.accepted,
    super.declined,
    super.tentative,
    super.pending,
    super.waitlist,
    super.attended,
    super.absent,
    super.staffCount,
    super.expectedGuests,
    super.guestRegistered,
    super.guestAttended,
    super.capacityTotal,
    super.capacityRemaining,
    this.quotaAssignees = 0,
    this.quotaTotal = 0,
    this.quotaExpectedTotal = 0,
    this.quotaGuestTotal = 0,
  });

  factory SalonAggregates.fromJson(Map<String, dynamic> json) {
    final base = SalonCounts.fromJson(json);
    return SalonAggregates(
      invitedTotal: base.invitedTotal,
      accepted: base.accepted,
      declined: base.declined,
      tentative: base.tentative,
      pending: base.pending,
      waitlist: base.waitlist,
      attended: base.attended,
      absent: base.absent,
      staffCount: base.staffCount,
      expectedGuests: base.expectedGuests,
      guestRegistered: base.guestRegistered,
      guestAttended: base.guestAttended,
      capacityTotal: base.capacityTotal,
      capacityRemaining: base.capacityRemaining,
      quotaAssignees: (json['quotaAssignees'] as num?)?.toInt() ?? 0,
      quotaTotal: (json['quotaTotal'] as num?)?.toInt() ?? 0,
      quotaExpectedTotal: (json['quotaExpectedTotal'] as num?)?.toInt() ?? 0,
      quotaGuestTotal: (json['quotaGuestTotal'] as num?)?.toInt() ?? 0,
    );
  }
}
