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
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/empty_state.dart';
import '../providers/salon_providers.dart';

import '../../../core/theme/tokens.g.dart';
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

/// 常用会务角色 (快速预设); 不在列表里仍可手动输入自定义角色
const List<String> kCommonStaffRoles = <String>[
  '主持',
  '讲师',
  '摄影',
  '后勤',
  '礼仪',
  '茶艺师',
  '销售助理',
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

  // ---- 快速邀请 (创建模式) ----
  // 加载一次, 候选条目默认全部勾选, 用户可取消单条
  QuickInviteSuggestions? _quickInvite;
  bool _quickInviteLoading = false;
  String? _quickInviteError;
  // 用条目 id (customer.id 或 franchisee.id) 作为 key; 创建后端只认 phone+name
  final Set<String> _quickInviteSelected = <String>{};

  bool get _isEdit => widget.salonId != null;

  @override
  void initState() {
    super.initState();
    if (!_isEdit) {
      // 仅创建模式拉快速邀请候选; 编辑模式已存在的受邀者走 manage 页管理
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadQuickInvite());
    }
  }

  Future<void> _loadQuickInvite() async {
    if (_isEdit || !mounted) return;
    setState(() {
      _quickInviteLoading = true;
      _quickInviteError = null;
    });
    try {
      final svc = ref.read(salonServiceProvider);
      final data = await svc.quickInviteSuggestions();
      // 默认全选; 客户表 0 条且上层 0 条 → 空集
      final selected = <String>{
        for (final e in data.customers) e.id,
        for (final e in data.ancestors) e.id,
      };
      if (!mounted) return;
      setState(() {
        _quickInvite = data;
        _quickInviteSelected
          ..clear()
          ..addAll(selected);
        _quickInviteLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quickInviteLoading = false;
        _quickInviteError = '加载快速邀请建议失败: $e';
      });
    }
  }

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
      // 加载 / 失败态需要外 Scaffold + AppBar; data 态直接返回 _buildForm(),
      // 避免嵌进外 Scaffold 出现「两个 AppBar + 两个返回键」的重复。
      return asyncSalon.when(
        loading: () => Scaffold(
          appBar: AppBar(title: const Text('编辑沙龙'), toolbarHeight: AppSize.appBarHeight),
          body: const LoadingState(),
        ),
        error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('编辑沙龙'), toolbarHeight: AppSize.appBarHeight),
          body: ErrorState(
            error: e,
            onRetry: () => ref.invalidate(salonDetailProvider(widget.salonId!)),
          ),
        ),
        data: (salon) {
          _prefill(salon);
          // _prefill 改了 _prefilled 但不 setState (避免多余重建);
          // postFrame 触发重建让 build 走 return _buildForm() 路径,
          // data 帧本身直接返回 _buildForm() (无外 Scaffold) → 单 AppBar
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
          return _buildForm();
        },
      );
    }
    return _buildForm();
  }

  Widget _buildForm() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑沙龙' : '创建沙龙'),
        toolbarHeight: AppSize.appBarHeight,
      ),
      body: Column(
        children: [
          _buildStepBar(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpace.s16, 16, 16, 24),
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
      padding: const EdgeInsets.fromLTRB(AppSpace.s12, 12, 12, 12),
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
                      : AppColors.border,
                  child: done
                      ? const Icon(Icons.check, size: AppSize.iconMd, color: Colors.white)
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
                const SizedBox(height: AppSpace.s4),
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
      padding: const EdgeInsets.fromLTRB(AppSpace.s16, 12, 16, 12),
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
                      const SizedBox(width: AppSpace.s12),
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
                  const SizedBox(height: AppSpace.s8),
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
                    const SizedBox(width: AppSpace.s12),
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
      const SizedBox(height: AppSpace.s8),
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
      const SizedBox(height: AppSpace.s12),
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
          const SizedBox(width: AppSpace.s8),
          SizedBox(
            height: AppSpace.s56,
            child: ElevatedButton(
              onPressed: _saving ? null : _addCustomTag,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(88, 56),
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.s16),
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
      if (!_isEdit) _buildInviteSection(),
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

  Widget _buildInviteSection() {
    return _card('邀请设置', [
      const Text(
        '勾选要邀请的人, 默认全选; 没装 app 的人也能邀请 (手机号收到短信后扫码进)',
        style: TextStyle(
            fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
      ),
      const SizedBox(height: AppSpace.s12),
      if (_quickInviteLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpace.s16),
          child: Center(child: SizedBox(
            width: AppSpace.s32, height: AppSpace.s32,
            child: CircularProgressIndicator(strokeWidth: 3),
          )),
        )
      else if (_quickInviteError != null) ...[
        Text(_quickInviteError!,
            style: const TextStyle(
                fontSize: AppTheme.fontSm, color: AppTheme.danger)),
        const SizedBox(height: AppSpace.s8),
        OutlinedButton.icon(
          onPressed: _loadQuickInvite,
          icon: const Icon(Icons.refresh, size: AppSize.iconSm),
          label: const Text('重试'),
        ),
      ] else if (_quickInvite == null || _quickInvite!.isEmpty) ...[
        const Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpace.s12),
          child: Text(
            '暂无可邀请的人——客户表里还没成员, 且未加入任何加盟树',
            style: TextStyle(
                fontSize: AppTheme.fontSm, color: AppTheme.textSecondary),
          ),
        ),
      ] else ...[
        if (_quickInvite!.customers.isNotEmpty) ...[
          _buildInviteSubCard(
            title: '我的客户',
            entries: _quickInvite!.customers,
          ),
          const SizedBox(height: AppSpace.s12),
        ],
        if (_quickInvite!.ancestors.isNotEmpty)
          _buildInviteSubCard(
            title: '加盟图谱上层 (≤3 层)',
            entries: _quickInvite!.ancestors,
          ),
      ],
    ]);
  }

  Widget _buildInviteSubCard({
    required String title,
    required List<QuickInviteEntry> entries,
  }) {
    final selectedCount = entries
        .where((e) => _quickInviteSelected.contains(e.id))
        .length;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.s12, 8, 12, 4),
      decoration: BoxDecoration(
        color: AppTheme.bgWarm,
        borderRadius: BorderRadius.circular(AppRadius.r12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '已选 $selectedCount / ${entries.length}',
                style: const TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.s4),
          for (final e in entries) _buildInviteRow(e),
        ],
      ),
    );
  }

  Widget _buildInviteRow(QuickInviteEntry e) {
    final selected = _quickInviteSelected.contains(e.id);
    return InkWell(
      onTap: _saving ? null : () {
        setState(() {
          if (selected) {
            _quickInviteSelected.remove(e.id);
          } else {
            _quickInviteSelected.add(e.id);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.s6),
        child: Row(
          children: [
            Checkbox(
              value: selected,
              onChanged: _saving ? null : (v) {
                setState(() {
                  if (v == true) {
                    _quickInviteSelected.add(e.id);
                  } else {
                    _quickInviteSelected.remove(e.id);
                  }
                });
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.name,
                          style: const TextStyle(
                            fontSize: AppTheme.fontMd,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (e.isMember)
                        Container(
                          margin: const EdgeInsets.only(left: AppSpace.s6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.s6, vertical: AppSpace.s2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight,
                            borderRadius: BorderRadius.circular(AppRadius.r6),
                          ),
                          child: const Text(
                            'app 会员',
                            style: TextStyle(
                              fontSize: AppTheme.fontXs,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.s2),
                  Text(
                    '${e.phone} · ${e.badge}',
                    style: const TextStyle(
                      fontSize: AppTheme.fontSm,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
      const SizedBox(height: AppSpace.s12),
      for (int i = 0; i < _staff.length; i++) _buildStaffRow(i),
      OutlinedButton.icon(
        onPressed:
            _saving ? null : () => setState(() => _staff.add(_StaffRow())),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
        ),
        icon: const Icon(Icons.add, size: AppSize.iconLg),
        label: const Text('添加会务人员'),
      ),
    ]);
  }

  Widget _buildStaffRow(int i) {
    final row = _staff[i];
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      padding: const EdgeInsets.fromLTRB(AppSpace.s12, 4, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgWarm,
        borderRadius: BorderRadius.circular(AppRadius.r12),
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
                  size: AppSize.iconLg,
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
          const SizedBox(height: AppSpace.s8),
          TextField(
            controller: row.phone,
            keyboardType: TextInputType.phone,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            decoration: const InputDecoration(labelText: '手机号'),
          ),
          const SizedBox(height: AppSpace.s8),
          // 常用角色快速预设 (点击填充到下方输入框, 仍可继续手动改)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kCommonStaffRoles.map((r) {
              return ActionChip(
                label: Text(
                  r,
                  style: const TextStyle(fontSize: AppTheme.fontSm),
                ),
                onPressed: _saving
                    ? null
                    : () {
                        row.staffRole.text = r;
                        setState(() {});
                      },
                backgroundColor: AppTheme.bgWarm,
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpace.s8),
          TextField(
            controller: row.staffRole,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            decoration: const InputDecoration(
              labelText: '角色',
              hintText: '点击上方预设或手动输入, 如: 副主持',
            ),
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
      const SizedBox(height: AppSpace.s12),
      for (int i = 0; i < _agenda.length; i++) _buildAgendaRow(i),
      OutlinedButton.icon(
        onPressed:
            _saving ? null : () => setState(() => _agenda.add(_AgendaRow())),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(double.infinity, 56),
        ),
        icon: const Icon(Icons.add, size: AppSize.iconLg),
        label: const Text('添加日程'),
      ),
    ]);
  }

  Widget _buildAgendaRow(int i) {
    final row = _agenda[i];
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      padding: const EdgeInsets.fromLTRB(AppSpace.s12, 4, 12, 12),
      decoration: BoxDecoration(
        color: AppTheme.bgWarm,
        borderRadius: BorderRadius.circular(AppRadius.r12),
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
                  size: AppSize.iconLg,
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
          const SizedBox(height: AppSpace.s8),
          _label('标题', required: true),
          TextField(
            controller: row.title,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            decoration:
                const InputDecoration(hintText: '如: 养生知识分享'),
          ),
          const SizedBox(height: AppSpace.s8),
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
      margin: const EdgeInsets.only(bottom: AppSpace.s16),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
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
            const SizedBox(height: AppSpace.s12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _label(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.s8),
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
      padding: const EdgeInsets.only(bottom: AppSpace.s16),
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
      padding: const EdgeInsets.only(bottom: AppSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          DropdownButtonFormField<String>(
            value: value,
            isExpanded: true,
            itemHeight: 56,
            icon: const Icon(Icons.arrow_drop_down,
                size: AppSize.iconXl, color: AppTheme.primary),
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
      padding: const EdgeInsets.only(bottom: AppSpace.s16),
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
                  icon: const Icon(Icons.event, size: AppSize.iconLg),
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
                  icon: const Icon(Icons.close, size: AppSize.iconLg),
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
        ref.read(usageServiceProvider).track('salon_create');
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
    // 会议日程: 填了任意字段的行必须有标题; 全空行视为无数据跳过
    for (int i = 0; i < _agenda.length; i++) {
      final a = _agenda[i];
      final hasAny = a.start.text.trim().isNotEmpty ||
          a.title.text.trim().isNotEmpty ||
          a.desc.text.trim().isNotEmpty;
      if (hasAny && a.title.text.trim().isEmpty) {
        _snack('请填写第 ${i + 1} 条日程的标题');
        setState(() => _step = 3);
        return false;
      }
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
      payload['invitees'] = _inviteesPayload();
    }
    return payload;
  }

  /// 把快速邀请里勾选的条目转成 API 要求的 invitees 列表
  /// 后端 InviteeInputSchema = { name, phone, expectedGuestCount? }
  List<Map<String, dynamic>> _inviteesPayload() {
    final data = _quickInvite;
    if (data == null) return const [];
    final all = <QuickInviteEntry>[...data.customers, ...data.ancestors];
    return all
        .where((e) => _quickInviteSelected.contains(e.id))
        .map((e) => {
              'name': e.name,
              'phone': e.phone,
            })
        .toList(growable: false);
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
