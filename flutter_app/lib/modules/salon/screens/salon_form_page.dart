// ============================================
// 沙龙 创建 / 编辑 表单 (4 步向导)
// v0.1.5 Phase 7 | 中老年大字 + 大按钮
// 第 1 步 基础信息 / 第 2 步 时间地点 / 第 3 步 服务安排 / 第 4 步 会务日程 + 发布
// 会务人员仅创建时提交 (编辑不传 staff)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/salon.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/salon_providers.dart';

/// 预设主题标签 (可自定义追加)
const List<String> _presetTags = <String>[
  '沙龙',
  '讲座',
  '品鉴会',
  '答谢会',
  '团建',
  '培训',
  '体验课',
];

const List<_Option> _feeOptions = <_Option>[
  _Option('free', '免费'),
  _Option('aa', 'AA制'),
  _Option('organizer_pays', '主理人请客'),
  _Option('paid', '收费'),
];

/// 'unset' 表示「待定」, 提交时转成 null
const List<_Option> _mealOptions = <_Option>[
  _Option('unset', '待定'),
  _Option('none', '不含餐'),
  _Option('breakfast', '早餐'),
  _Option('lunch', '午餐'),
  _Option('dinner', '晚餐'),
  _Option('tea', '茶歇'),
];

const List<_Option> _attendeeVisOptions = <_Option>[
  _Option('all', '所有受邀者'),
  _Option('staff', '仅会务'),
  _Option('organizer', '仅主理人'),
];

const List<_Option> _staffContactVisOptions = <_Option>[
  _Option('all', '所有受邀者'),
  _Option('staff', '仅会务'),
];

class _Option {
  final String value;
  final String label;
  const _Option(this.value, this.label);
}

/// 会务人员动态行 (仅创建时提交)
class _StaffRow {
  final TextEditingController name = TextEditingController();
  final TextEditingController phone = TextEditingController();
  final TextEditingController staffRole = TextEditingController();

  void dispose() {
    name.dispose();
    phone.dispose();
    staffRole.dispose();
  }
}

/// 日程动态行
class _AgendaRow {
  final TextEditingController start = TextEditingController();
  final TextEditingController title = TextEditingController();
  final TextEditingController desc = TextEditingController();

  _AgendaRow({String? startText, String? titleText, String? descText}) {
    start.text = startText ?? '';
    title.text = titleText ?? '';
    desc.text = descText ?? '';
  }

  void dispose() {
    start.dispose();
    title.dispose();
    desc.dispose();
  }
}

class SalonFormPage extends ConsumerStatefulWidget {
  final String? salonId;
  const SalonFormPage({super.key, this.salonId});

  @override
  ConsumerState<SalonFormPage> createState() => _SalonFormPageState();
}

class _SalonFormPageState extends ConsumerState<SalonFormPage> {
  static final RegExp _phoneRe = RegExp(r'^1[3-9]\d{9}$');

  int _step = 0;
  bool _prefilled = false;
  bool _saving = false;

  // ---- 第 1 步 基础信息 ----
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _tagInputCtrl = TextEditingController();
  final Set<String> _tags = <String>{};
  final _descCtrl = TextEditingController();

  // ---- 第 2 步 时间地点 ----
  DateTime? _startAt;
  DateTime? _endAt;
  DateTime? _regDeadlineAt;
  final _locationCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _parkingCtrl = TextEditingController();
  final _transportPublicCtrl = TextEditingController();
  final _transportDrivingCtrl = TextEditingController();
  final _transportPickupCtrl = TextEditingController();

  // ---- 第 3 步 服务安排 ----
  final _capacityCtrl = TextEditingController();
  final _reservedCtrl = TextEditingController();
  String _feeType = 'free';
  final _feeAmountCtrl = TextEditingController();
  final _feeNoteCtrl = TextEditingController();
  String _mealType = 'unset';
  final _cuisineCtrl = TextEditingController();
  final _dietaryCtrl = TextEditingController();
  final _mealTimeCtrl = TextEditingController();
  final _payerCtrl = TextEditingController();
  final _hotelCtrl = TextEditingController();
  final _roomTypeCtrl = TextEditingController();
  final _lodgingPriceCtrl = TextEditingController();
  final _lodgingContactCtrl = TextEditingController();
  final _lodgingPhoneCtrl = TextEditingController();
  DateTime? _lodgingDeadlineAt;
  final _lodgingNoteCtrl = TextEditingController();
  final _dressCodeCtrl = TextEditingController();

  // ---- 第 4 步 会务与日程 + 发布 ----
  final List<_StaffRow> _staff = <_StaffRow>[_StaffRow()];
  final List<_AgendaRow> _agenda = <_AgendaRow>[_AgendaRow()];
  String _attendeeListVis = 'all';
  String _staffContactVis = 'all';

  bool get _isEdit => widget.salonId != null;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _tagInputCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _addressCtrl.dispose();
    _floorCtrl.dispose();
    _parkingCtrl.dispose();
    _transportPublicCtrl.dispose();
    _transportDrivingCtrl.dispose();
    _transportPickupCtrl.dispose();
    _capacityCtrl.dispose();
    _reservedCtrl.dispose();
    _feeAmountCtrl.dispose();
    _feeNoteCtrl.dispose();
    _cuisineCtrl.dispose();
    _dietaryCtrl.dispose();
    _mealTimeCtrl.dispose();
    _payerCtrl.dispose();
    _hotelCtrl.dispose();
    _roomTypeCtrl.dispose();
    _lodgingPriceCtrl.dispose();
    _lodgingContactCtrl.dispose();
    _lodgingPhoneCtrl.dispose();
    _lodgingNoteCtrl.dispose();
    _dressCodeCtrl.dispose();
    for (final row in _staff) {
      row.dispose();
    }
    for (final row in _agenda) {
      row.dispose();
    }
    super.dispose();
  }

  // ============================================
  // 编辑预填 (在 data 回调里同步执行, 不 setState)
  // ============================================
  void _prefill(Salon s) {
    _prefilled = true;
    _titleCtrl.text = s.title;
    _subtitleCtrl.text = s.subtitle ?? '';
    _descCtrl.text = s.description ?? '';
    _tags
      ..clear()
      ..addAll(s.themeTags.where((t) => t.trim().isNotEmpty));
    _startAt = s.startAt;
    _endAt = s.endAt;
    _regDeadlineAt = s.registrationDeadlineAt;
    _locationCtrl.text = s.locationName ?? '';
    _addressCtrl.text = s.address ?? '';
    _floorCtrl.text = s.floorRoom ?? '';
    _parkingCtrl.text = s.parkingInfo ?? '';
    _transportPublicCtrl.text = s.transportPublic ?? '';
    _transportDrivingCtrl.text = s.transportDriving ?? '';
    _transportPickupCtrl.text = s.transportPickup ?? '';
    _capacityCtrl.text = s.capacityTotal?.toString() ?? '';
    _reservedCtrl.text =
        (s.capacityReserved == 0) ? '' : s.capacityReserved.toString();
    _feeType =
        _feeOptions.any((o) => o.value == s.feeType) ? s.feeType : 'free';
    _feeAmountCtrl.text =
        s.feeAmountCents == null ? '' : _yuanText(s.feeAmountCents!);
    _feeNoteCtrl.text = s.feeNote ?? '';
    final meal = s.cateringMealType;
    _mealType = (meal == null || meal.isEmpty)
        ? 'unset'
        : (_mealOptions.any((o) => o.value == meal) ? meal : 'unset');
    _cuisineCtrl.text = s.cateringCuisine ?? '';
    _dietaryCtrl.text = s.cateringDietary ?? '';
    _mealTimeCtrl.text = s.cateringTime ?? '';
    _payerCtrl.text = s.cateringPayer ?? '';
    _hotelCtrl.text = s.lodgingHotelName ?? '';
    _roomTypeCtrl.text = s.lodgingRoomType ?? '';
    _lodgingPriceCtrl.text =
        s.lodgingPriceCents == null ? '' : _yuanText(s.lodgingPriceCents!);
    _lodgingContactCtrl.text = s.lodgingContactName ?? '';
    _lodgingPhoneCtrl.text = s.lodgingContactPhone ?? '';
    _lodgingDeadlineAt = s.lodgingDeadlineAt;
    _lodgingNoteCtrl.text = s.lodgingNote ?? '';
    _dressCodeCtrl.text = s.dressCode ?? '';
    for (final row in _agenda) {
      row.dispose();
    }
    _agenda.clear();
    for (final item in s.agenda) {
      _agenda.add(_AgendaRow(
        startText: item.start,
        titleText: item.title,
        descText: item.desc,
      ));
    }
    if (_agenda.isEmpty) _agenda.add(_AgendaRow());
    _attendeeListVis = _attendeeVisOptions
            .any((o) => o.value == s.visibilitySettings.attendeeList)
        ? s.visibilitySettings.attendeeList
        : 'all';
    _staffContactVis = _staffContactVisOptions
            .any((o) => o.value == s.visibilitySettings.staffContact)
        ? s.visibilitySettings.staffContact
        : 'all';
  }

  // ============================================
  // 构建
  // ============================================
  @override
  Widget build(BuildContext context) {
    if (_isEdit && !_prefilled) {
      final asyncSalon = ref.watch(salonDetailProvider(widget.salonId!));
      return Scaffold(
        appBar: AppBar(title: const Text('编辑沙龙'), toolbarHeight: 64),
        body: asyncSalon.when(
          loading: () => const LoadingState(),
          error: (e, _) => ErrorState(
            error: e,
            onRetry: () => ref.invalidate(salonDetailProvider(widget.salonId!)),
          ),
          data: (salon) {
            _prefill(salon);
            return _buildForm();
          },
        ),
      );
    }
    return _buildForm();
  }

  Widget _buildForm() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑沙龙' : '创建沙龙'),
        toolbarHeight: 64,
      ),
      body: Column(
        children: [
          _buildStepBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: _buildStepChildren(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  List<Widget> _buildStepChildren() {
    switch (_step) {
      case 0:
        return _buildStepBasic();
      case 1:
        return _buildStepTimePlace();
      case 2:
        return _buildStepService();
      default:
        return _buildStepStaffAgenda();
    }
  }

  // ============================================
  // 顶部分步条
  // ============================================
  Widget _buildStepBar() {
    const titles = <String>['基础信息', '时间地点', '服务安排', '会务日程'];
    return Container(
      color: AppTheme.bgCard,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        children: List<Widget>.generate(titles.length, (i) {
          final active = i == _step;
          final done = i < _step;
          return Expanded(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: (active || done)
                      ? AppTheme.primary
                      : const Color(0xFFE0E0E0),
                  child: done
                      ? const Icon(Icons.check, size: 20, color: Colors.white)
                      : Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: AppTheme.fontSm,
                            fontWeight: FontWeight.w600,
                            color: (active || done)
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                ),
                const SizedBox(height: 4),
                Text(
                  titles[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppTheme.fontXs,
                    fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    color: active ? AppTheme.primary : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ============================================
  // 底部按钮
  // ============================================
  Widget _buildBottomBar() {
    final isLast = _step == 3;
    return Container(
      color: AppTheme.bgCard,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: isLast
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => _submit('draft'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 56),
                          ),
                          child: const Text('存草稿'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed:
                              _saving ? null : () => _submit('published'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 56),
                          ),
                          child: Text(_saving ? '保存中...' : '直接发布'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _step = (_step - 1).clamp(0, 3)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 56),
                    ),
                    child: const Text('上一步'),
                  ),
                ],
              )
            : Row(
                children: [
                  if (_step > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () =>
                                setState(() => _step = (_step - 1).clamp(0, 3)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 56),
                        ),
                        child: const Text('上一步'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _goNext,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 56),
                      ),
                      child: const Text('下一步'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _goNext() {
    if (_step == 0 && _titleCtrl.text.trim().isEmpty) {
      _snack('请填写沙龙标题');
      return;
    }
    if (_step == 1 && _startAt == null) {
      _snack('请选择开始时间');
      return;
    }
    if (_step == 1 && _startAt != null && _startAt!.isBefore(DateTime.now())) {
      _snack('开始时间不能早于当前时间');
      return;
    }
    if (_step == 1 && _endAt != null && _startAt != null && _endAt!.isBefore(_startAt!)) {
      _snack('结束时间不能早于开始时间');
      return;
    }
    setState(() => _step = (_step + 1).clamp(0, 3));
  }

  // ============================================
  // 第 1 步 基础信息
  // ============================================
  List<Widget> _buildStepBasic() {
    return [
      _card('基本信息', [
        _field('沙龙标题', _titleCtrl, required: true, hint: '如: 秋季养生沙龙'),
        _field('副标题', _subtitleCtrl, hint: '可选, 一行说清主题'),
      ]),
      _buildTagSection(),
      _card('简介', [
        _field('沙龙简介', _descCtrl, hint: '介绍下这场沙龙的内容 / 亮点', maxLines: 5),
      ]),
    ];
  }

  Widget _buildTagSection() {
    final allTags = <String>{
      ..._presetTags,
      ..._tags.where((t) => !_presetTags.contains(t)),
    };
    return _card('主题标签', [
      const Text(
        '可多选, 最多 10 个',
        style:
            TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: allTags.map((tag) {
          final selected = _tags.contains(tag);
          return InputChip(
            label: Text(
              tag,
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                color: selected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
            selected: selected,
            onSelected: _saving ? null : (v) => _toggleTag(tag, v),
            selectedColor: AppTheme.primary,
            checkmarkColor: Colors.white,
            backgroundColor: AppTheme.bgWarm,
          );
        }).toList(),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _tagInputCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(hintText: '自定义标签'),
              onSubmitted: (_) => _addCustomTag(),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _saving ? null : _addCustomTag,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(88, 56),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('添加'),
            ),
          ),
        ],
      ),
    ]);
  }

  void _toggleTag(String tag, bool selected) {
    if (selected && _tags.length >= 10) {
      _snack('最多选 10 个标签');
      return;
    }
    setState(() {
      if (selected) {
        _tags.add(tag);
      } else {
        _tags.remove(tag);
      }
    });
  }

  void _addCustomTag() {
    final tag = _tagInputCtrl.text.trim();
    if (tag.isEmpty) return;
    if (tag.length > 20) {
      _snack('标签太长啦, 请控制在 20 字以内');
      return;
    }
    if (_tags.contains(tag)) {
      _snack('这个标签已经选过了');
      return;
    }
    if (_tags.length >= 10) {
      _snack('最多选 10 个标签');
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagInputCtrl.clear();
    });
  }

  // ============================================
  // 第 2 步 时间地点
  // ============================================
  List<Widget> _buildStepTimePlace() {
    return [
      _card('时间', [
        _dateTimeField('开始时间', _startAt,
            required: true, onChanged: (v) => setState(() => _startAt = v)),
        _dateTimeField('结束时间', _endAt,
            onChanged: (v) => setState(() => _endAt = v)),
        _dateTimeField('报名截止时间', _regDeadlineAt,
            onChanged: (v) => setState(() => _regDeadlineAt = v)),
      ]),
      _card('地点', [
        _field('场地名称', _locationCtrl, hint: '如: 暖客养生会所'),
        _field('详细地址', _addressCtrl, hint: '如: 杭州市西湖区文三路 100 号'),
        _field('楼层 / 包间', _floorCtrl, hint: '如: 3 楼 302 包间'),
        _field('停车信息', _parkingCtrl, hint: '如: 楼下地下车库, 免费 2 小时', maxLines: 2),
      ]),
      _card('怎么来', [
        _field('公共交通指引', _transportPublicCtrl,
            hint: '如: 地铁 2 号线 A 口步行 300 米', maxLines: 2),
        _field('自驾路线', _transportDrivingCtrl,
            hint: '如: 导航搜「XX 大厦」', maxLines: 2),
        _field('接站安排', _transportPickupCtrl,
            hint: '如: 高铁站安排接站, 联系张师傅', maxLines: 2),
      ]),
    ];
  }

  // ============================================
  // 第 3 步 服务安排
  // ============================================
  List<Widget> _buildStepService() {
    return [
      _card('名额', [
        _numberField('总名额', _capacityCtrl, hint: '不填 = 不限'),
        _numberField('保留名额', _reservedCtrl, hint: '不填 = 0'),
      ]),
      _card('费用', [
        _dropdownField('费用类型', _feeType, _feeOptions,
            onChanged: (v) => setState(() => _feeType = v ?? 'free')),
        if (_feeType == 'paid') _numberField('收费金额 (元)', _feeAmountCtrl),
        _field('费用说明', _feeNoteCtrl, hint: '如: 含午餐 + 材料费', maxLines: 2),
      ]),
      _card('用餐', [
        _dropdownField('餐别', _mealType, _mealOptions,
            onChanged: (v) => setState(() => _mealType = v ?? 'unset')),
        _field('菜系', _cuisineCtrl, hint: '如: 杭帮菜 / 粤菜'),
        _field('饮食禁忌备注', _dietaryCtrl, hint: '如: 有 2 位不吃辣', maxLines: 2),
        _field('用餐时间', _mealTimeCtrl, hint: '如: 12:00'),
        _field('费用承担方', _payerCtrl, hint: '如: 公司 / AA / 主理人'),
      ]),
      _card('住宿', [
        _field('酒店名称', _hotelCtrl),
        _field('房型', _roomTypeCtrl, hint: '如: 标准双床房'),
        _numberField('价格 (元/晚)', _lodgingPriceCtrl),
        _field('订房联系人', _lodgingContactCtrl),
        _field('订房电话', _lodgingPhoneCtrl, keyboard: TextInputType.phone),
        _dateTimeField('订房截止时间', _lodgingDeadlineAt,
            onChanged: (v) => setState(() => _lodgingDeadlineAt = v)),
        _field('住宿备注', _lodgingNoteCtrl, maxLines: 2),
      ]),
      _card('着装', [
        _field('着装要求', _dressCodeCtrl, hint: '如: 休闲装 / 正装'),
      ]),
    ];
  }

  // ============================================
  // 第 4 步 会务 + 日程 + 发布
  // ============================================
  List<Widget> _buildStepStaffAgenda() {
    return [
      _buildStaffSection(),
      _buildAgendaSection(),
      _card('可见性设置', [
        _dropdownField('受邀名单谁可见', _attendeeListVis, _attendeeVisOptions,
            onChanged: (v) => setState(() => _attendeeListVis = v ?? 'all')),
        _dropdownField('会务联系方式谁可见', _staffContactVis, _staffContactVisOptions,
            onChanged: (v) => setState(() => _staffContactVis = v ?? 'all')),
        const Text(
          '选好后, 受邀者之间看不到彼此的手机号',
          style: TextStyle(
              fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
        ),
      ]),
      _card('最后一步', [
        const Text(
          '点「存草稿」先不公开; 点「直接发布」受邀者就能看到了',
          style: TextStyle(
              fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
        ),
      ]),
    ];
  }

  Widget _buildStaffSection() {
    return _card('会务人员', [
      Text(
        _isEdit
            ? '编辑时这里新增的会务不会提交; 请到「沙龙管理 → 邀请名单」添加会务'
            : '填姓名 + 手机号 + 角色 (如「主持」); 整行留空会自动忽略',
        style: const TextStyle(
          fontSize: AppTheme.fontSm,
          color: AppTheme.textSecondary,
        ),
      ),
      const SizedBox(height: 12),
      for (int i = 0; i < _staff.length; i++) _buildStaffRow(i),
      OutlinedButton.icon(
        onPressed:
            _saving ? null : () => setState(() => _staff.add(_StaffRow())),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
        ),
        icon: const Icon(Icons.add, size: 24),
        label: const Text('添加会务人员'),
      ),
    ]);
  }

  Widget _buildStaffRow(int i) {
    final row = _staff[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgWarm,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '会务 ${i + 1}',
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed:
                    _saving ? null : () => setState(() => _staff.removeAt(i)),
                tooltip: '删除',
                icon: const Icon(
                  Icons.delete_outline,
                  size: 26,
                  color: AppTheme.danger,
                ),
              ),
            ],
          ),
          TextField(
            controller: row.name,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            decoration:
                const InputDecoration(labelText: '姓名', hintText: '如: 张老师'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.phone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            decoration: const InputDecoration(labelText: '手机号'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.staffRole,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            decoration: const InputDecoration(
                labelText: '角色', hintText: '如: 主持 / 讲师 / 摄影'),
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaSection() {
    return _card('日程安排', [
      const Text(
        '一条一行, 时间可写「14:00」这样的格式',
        style:
            TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
      ),
      const SizedBox(height: 12),
      for (int i = 0; i < _agenda.length; i++) _buildAgendaRow(i),
      OutlinedButton.icon(
        onPressed:
            _saving ? null : () => setState(() => _agenda.add(_AgendaRow())),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
        ),
        icon: const Icon(Icons.add, size: 24),
        label: const Text('添加日程'),
      ),
    ]);
  }

  Widget _buildAgendaRow(int i) {
    final row = _agenda[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgWarm,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '日程 ${i + 1}',
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed:
                    _saving ? null : () => setState(() => _agenda.removeAt(i)),
                tooltip: '删除',
                icon: const Icon(
                  Icons.delete_outline,
                  size: 26,
                  color: AppTheme.danger,
                ),
              ),
            ],
          ),
          TextField(
            controller: row.start,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            decoration:
                const InputDecoration(labelText: '时间', hintText: '如: 14:00'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.title,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            decoration:
                const InputDecoration(labelText: '标题', hintText: '如: 养生知识分享'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: row.desc,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            maxLines: 2,
            decoration: const InputDecoration(labelText: '说明 (可选)'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // 通用小组件
  // ============================================
  Widget _card(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _label(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: text,
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(
                  fontSize: AppTheme.fontMd,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.danger,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool required = false,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label, required: required),
          TextField(
            controller: ctrl,
            enabled: !_saving,
            keyboardType: keyboard,
            maxLines: maxLines,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController ctrl, {
    String? hint,
  }) {
    return _field(
      label,
      ctrl,
      hint: hint,
      keyboard: TextInputType.number,
    );
  }

  Widget _dropdownField(
    String label,
    String value,
    List<_Option> options, {
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            itemHeight: 56,
            icon: const Icon(Icons.arrow_drop_down,
                size: 32, color: AppTheme.primary),
            dropdownColor: AppTheme.bgCard,
            style: const TextStyle(
              fontSize: AppTheme.fontMd,
              color: AppTheme.textPrimary,
            ),
            items: options
                .map((o) => DropdownMenuItem<String>(
                      value: o.value,
                      child: Text(
                        o.label,
                        style: const TextStyle(
                          fontSize: AppTheme.fontMd,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ))
                .toList(),
            onChanged: _saving ? null : onChanged,
          ),
        ],
      ),
    );
  }

  Widget _dateTimeField(
    String label,
    DateTime? value, {
    required ValueChanged<DateTime?> onChanged,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label, required: required),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed:
                      _saving ? null : () => _pickDateTime(value, onChanged),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 56),
                  ),
                  icon: const Icon(Icons.event, size: 24),
                  label: Text(
                    value == null ? '点击选择' : _fmtDateTime(value),
                    style: const TextStyle(fontSize: AppTheme.fontMd),
                  ),
                ),
              ),
              if (value != null)
                IconButton(
                  onPressed: _saving ? null : () => onChanged(null),
                  tooltip: '清除',
                  icon: const Icon(Icons.close, size: 26),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickDateTime(
    DateTime? current,
    ValueChanged<DateTime?> onChanged,
  ) async {
    final now = DateTime.now();
    final base = current ?? now.add(const Duration(days: 7));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return;
    onChanged(
        DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  // ============================================
  // 提交
  // ============================================
  Future<void> _submit(String status) async {
    if (!_validateForSubmit()) return;
    setState(() => _saving = true);
    try {
      final svc = ref.read(salonServiceProvider);
      final Salon saved;
      if (_isEdit) {
        saved = await svc.update(widget.salonId!, _buildPayload(status));
      } else {
        saved = await svc.create(_buildPayload(status));
      }
      if (!mounted) return;
      invalidateSalon(ref, saved.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'draft' ? '已存草稿' : '已发布',
            style: const TextStyle(fontSize: AppTheme.fontMd),
          ),
        ),
      );
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      _snack('保存失败, 请检查网络');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _validateForSubmit() {
    if (_titleCtrl.text.trim().isEmpty) {
      _snack('请填写沙龙标题');
      setState(() => _step = 0);
      return false;
    }
    if (_startAt == null) {
      _snack('请选择开始时间');
      setState(() => _step = 1);
      return false;
    }
    if (_startAt!.isBefore(DateTime.now())) {
      _snack('开始时间不能早于当前时间');
      setState(() => _step = 1);
      return false;
    }
    if (_endAt != null && _endAt!.isBefore(_startAt!)) {
      _snack('结束时间不能早于开始时间');
      setState(() => _step = 1);
      return false;
    }
    if (!_isEdit) {
      for (final row in _staff) {
        final name = row.name.text.trim();
        final phone = row.phone.text.trim();
        if (name.isEmpty && phone.isEmpty) continue;
        if (name.isEmpty) {
          _snack('请填写会务人员的姓名');
          setState(() => _step = 3);
          return false;
        }
        if (!_phoneRe.hasMatch(phone)) {
          _snack('会务手机号格式不对, 请检查');
          setState(() => _step = 3);
          return false;
        }
      }
    }
    final lodgingPhone = _lodgingPhoneCtrl.text.trim();
    if (lodgingPhone.isNotEmpty && !_phoneRe.hasMatch(lodgingPhone)) {
      _snack('订房电话格式不对, 请检查');
      setState(() => _step = 2);
      return false;
    }
    if (_capacityCtrl.text.trim().isNotEmpty) {
      final cap = _intOrNull(_capacityCtrl);
      if (cap == null || cap < 1) {
        _snack('总名额请填 1 以上的数字');
        setState(() => _step = 2);
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> _buildPayload(String status) {
    final payload = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'subtitle': _textOrNull(_subtitleCtrl),
      'description': _textOrNull(_descCtrl),
      'themeTags': _tags.toList(),
      'status': status,
      if (_startAt != null) 'startAt': _startAt!.toUtc().toIso8601String(),
      'endAt': _endAt?.toUtc().toIso8601String(),
      'registrationDeadlineAt': _regDeadlineAt?.toUtc().toIso8601String(),
      'locationName': _textOrNull(_locationCtrl),
      'address': _textOrNull(_addressCtrl),
      'floorRoom': _textOrNull(_floorCtrl),
      'parkingInfo': _textOrNull(_parkingCtrl),
      'transportPublic': _textOrNull(_transportPublicCtrl),
      'transportDriving': _textOrNull(_transportDrivingCtrl),
      'transportPickup': _textOrNull(_transportPickupCtrl),
      'capacityTotal': _intOrNull(_capacityCtrl),
      'capacityReserved': _intOrNull(_reservedCtrl) ?? 0,
      'feeType': _feeType,
      'feeAmountCents':
          _feeType == 'paid' ? _centsOrNull(_feeAmountCtrl) : null,
      'feeNote': _textOrNull(_feeNoteCtrl),
      'cateringMealType': _mealType == 'unset' ? null : _mealType,
      'cateringCuisine': _textOrNull(_cuisineCtrl),
      'cateringDietary': _textOrNull(_dietaryCtrl),
      'cateringTime': _textOrNull(_mealTimeCtrl),
      'cateringPayer': _textOrNull(_payerCtrl),
      'lodgingHotelName': _textOrNull(_hotelCtrl),
      'lodgingRoomType': _textOrNull(_roomTypeCtrl),
      'lodgingPriceCents': _centsOrNull(_lodgingPriceCtrl),
      'lodgingContactName': _textOrNull(_lodgingContactCtrl),
      'lodgingContactPhone': _textOrNull(_lodgingPhoneCtrl),
      'lodgingDeadlineAt': _lodgingDeadlineAt?.toUtc().toIso8601String(),
      'lodgingNote': _textOrNull(_lodgingNoteCtrl),
      'dressCode': _textOrNull(_dressCodeCtrl),
      'agenda': _agendaPayload(),
      'visibilitySettings': {
        'attendeeList': _attendeeListVis,
        'staffContact': _staffContactVis,
      },
    };
    if (!_isEdit) {
      payload['staff'] = _staffPayload();
    }
    return payload;
  }

  List<Map<String, dynamic>> _staffPayload() {
    final items = <Map<String, dynamic>>[];
    for (final row in _staff) {
      final name = row.name.text.trim();
      final phone = row.phone.text.trim();
      if (name.isEmpty && phone.isEmpty) continue;
      items.add({
        'name': name,
        'phone': phone,
        if (row.staffRole.text.trim().isNotEmpty)
          'staffRole': row.staffRole.text.trim(),
      });
    }
    return items;
  }

  List<Map<String, dynamic>> _agendaPayload() {
    final items = <Map<String, dynamic>>[];
    for (final row in _agenda) {
      final title = row.title.text.trim();
      if (title.isEmpty) continue;
      items.add({
        if (row.start.text.trim().isNotEmpty) 'start': row.start.text.trim(),
        'title': title,
        if (row.desc.text.trim().isNotEmpty) 'desc': row.desc.text.trim(),
      });
    }
    return items;
  }

  // ============================================
  // 小工具
  // ============================================
  String? _textOrNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  int? _intOrNull(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  int? _centsOrNull(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    final yuan = double.tryParse(t);
    if (yuan == null || yuan < 0) return null;
    return (yuan * 100).round();
  }

  String _yuanText(int cents) {
    if (cents % 100 == 0) return '${cents ~/ 100}';
    return (cents / 100).toStringAsFixed(2);
  }

  String _fmtDateTime(DateTime dt) {
    final now = DateTime.now();
    final year = dt.year == now.year ? '' : '${dt.year}年';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$year${dt.month}月${dt.day}日 $hh:$mm';
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: AppTheme.fontMd)),
      ),
    );
  }
}
