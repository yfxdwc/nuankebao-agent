// ============================================
// 暖客宝 客户表单页 (新增 / 编辑) (B1 客户域换装, 2026-09-24)
//
// 本文件从 customers_page.dart 拆出 (2026-09-24).
// 拆分原则 (B1 任务书 §2):
//   - 表单页 = 新建/编辑客户 (推荐码识别 / 基础信息 / 生日 / 健康标签 / 备注)
//   - 校验逻辑 / 提交逻辑一个字节都不许改 —— 仅 UI 调整
//
// 设计依据 (docs/ui-principles.md):
//   - 原则 2: 层级靠对比不靠放大
//   - 原则 §3.1: 触摸热区 ≥ 48 (OutlinedButton.minimumSize)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/service_providers.dart';
import '../../../core/services/api.dart' show ReferralLookup;
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.g.dart';
import 'customer_pickers.dart' show YearPickerDialog, NumberPickerDialog;

// ============================================
// CustomerFormPage (新增 / 编辑)
// ============================================

class CustomerFormPage extends ConsumerStatefulWidget {
  final String? customerId;
  const CustomerFormPage({super.key, this.customerId});

  @override
  ConsumerState<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends ConsumerState<CustomerFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  /// 推荐码识别 (只新建时显示; ADR-0015 Q10/Q12):
  ///   推荐码 = 身份识别码 → 填已注册朋友的码 = 把**她**加为客户 (不新建重复档案)
  final _refCodeController = TextEditingController();
  ReferralLookup? _lookup;
  bool _lookupLoading = false;

  /// 「识别到可加的人」→ 保存走 claim, 不走 create
  bool get _claimMode => widget.customerId == null && _lookup?.canClaim == true;
  final _notesController = TextEditingController();
  final _diseaseController = TextEditingController(); // 既往病史
  final _allergyController = TextEditingController(); // 过敏史 (2026-09-18 新增)
  final _customTagController = TextEditingController(); // 自定义健康标签
  String? _gender = 'F';
  DateTime? _birthYear;
  /// 生日 月/日 (主人 2026-09-18 拍): 都可缺 — 不知道就 null
  int? _birthMonth;
  int? _birthDay;
  /// 历法: solar 阳历 / lunar 农历
  String _birthCalendar = 'solar';
  /// 生日提醒强度 (7/3/0 天); null = 不提醒
  /// 规则: 月 + 日 都填 = 自动开启 (默认 3 天前); 任一个清空 = 关掉
  int? _birthdayRemindDays = 3;
  final List<String> _healthTags = [];

  /// 健康标签默认候选项 (中老年养生高频; 主人 2026-09-18 拍「显示一些默认候选项」)
  static const List<String> _defaultHealthTags = [
    '肩颈僵硬', '腰椎不适', '膝关节痛', '睡眠差',
    '体寒怕冷', '湿气重', '气血不足', '脾胃虚弱',
    '手脚冰凉', '头晕乏力', '更年期', '便秘',
  ];

  /// 自定义标签上限: 6 个汉字 (主人 2026-09-18 拍)
  static const int _maxTagLength = 6;

  /// 客户来源 (Phase C §1 维度 6 + §5 migration 0026, 主人 2026-09-25 D5 拍「选填」):
  ///   null / 'friend' 亲友 / 'referral' 转介绍 / 'cold_visit' 陌生拜访 / 'ground_promo' 地推
  ///   referral 时 _sourceReferrerName 必填 (后端 zod refine 校验, §5 M3, 不加 DB CHECK)
  String? _acquireSource;
  /// 转介绍介绍人姓名 (≤ 50 字, 与后端 source_referrer_name 对齐):
  ///   仅 acquireSource = 'referral' 时有值; 其他情况 = null
  final _sourceReferrerController = TextEditingController();

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.customerId != null) {
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    final c = await ref.read(customerServiceProvider).getById(widget.customerId!);
    if (!mounted) return;
    setState(() {
      _nameController.text = c.name;
      _phoneController.text = c.phone;
      _notesController.text = c.notes ?? '';
      _diseaseController.text = c.diseaseHistory ?? '';
      _allergyController.text = c.allergyHistory ?? '';
      _gender = c.gender;
      _birthYear = c.birthYear != null ? DateTime(c.birthYear!, 1, 1) : null;
      _birthMonth = c.birthMonth;
      _birthDay = c.birthDay;
      _birthCalendar = c.birthCalendar;
      _birthdayRemindDays = c.birthdayRemindDays;
      _healthTags.clear();
      _healthTags.addAll(c.healthTags);
      // Phase C D6: 来源字段; 老后端不返回 → 默认 null = 未填写
      _acquireSource = c.acquireSource;
      _sourceReferrerController.text = c.sourceReferrerName ?? '';
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _refCodeController.dispose();
    _notesController.dispose();
    _diseaseController.dispose();
    _allergyController.dispose();
    _customTagController.dispose();
    _sourceReferrerController.dispose();
    super.dispose();
  }

  // ===== 生日: 年/月/日 各自可选填 (不知道就留空) =====

  /// 生日选择按钮 (值 == null 显示「不清楚」)
  Widget _birthPickerButton({
    required String label,
    required String? value,
    required VoidCallback onPick,
  }) {
    return OutlinedButton(
      onPressed: onPick,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ${value ?? '不清楚'}',
              style: TextStyle(
                fontSize: AppTheme.fontSm,
                fontWeight: value == null ? FontWeight.w400 : FontWeight.w600,
                color: value == null
                    ? AppTheme.textSecondary
                    : AppTheme.textPrimary,
              )),
        ],
      ),
    );
  }

  Future<void> _pickBirthYear() async {
    final year = await showDialog<int>(
      context: context,
      builder: (_) => YearPickerDialog(initial: _birthYear?.year ?? 1965),
    );
    if (year == null) return;
    setState(() => _birthYear = DateTime(year, 1, 1));
  }

  /// 月 / 日 选择 (含「不清楚」= 清空)
  Future<void> _pickBirthPart({required bool isMonth}) async {
    final current = isMonth ? _birthMonth : _birthDay;
    final max = isMonth ? 12 : 31;
    final picked = await showDialog<int?>(
      context: context,
      builder: (_) => NumberPickerDialog(
        title: isMonth ? '选择出生月份' : '选择出生日期',
        max: max,
        initial: current,
        suffix: isMonth ? '月' : '日',
      ),
    );
    if (picked == null && current == null) return;
    setState(() {
      if (isMonth) {
        _birthMonth = picked;
      } else {
        _birthDay = picked;
      }
      // 月+日 都有 → 默认开启提醒 (3 天前); 任一清空 → 关掉
      if (_birthMonth == null || _birthDay == null) {
        _birthdayRemindDays = null;
      } else if (_birthdayRemindDays == null) {
        _birthdayRemindDays = 3;
      }
    });
  }

  /// 自定义健康标签 (≤6 汉字, 去重, 空/超长给提示)
  void _addCustomTag() {
    final v = _customTagController.text.trim();
    if (v.isEmpty) return;
    if (v.runes.length > _maxTagLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('标签最多 6 个字')),
      );
      return;
    }
    if (_healthTags.contains(v)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这个标签已经有了')),
      );
      _customTagController.clear();
      return;
    }
    setState(() {
      _healthTags.add(v);
      _customTagController.clear();
    });
  }

  /// 按推荐码识别已注册用户 (ADR-0015 Q10)
  /// 后端: 登录 + 限流 10/分 + 审计; 只返回姓名/打码手机号/会员/归属状态
  Future<void> _lookupCode() async {
    final code = _refCodeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入推荐码')),
      );
      return;
    }
    setState(() => _lookupLoading = true);
    try {
      final r = await ref.read(billingServiceProvider).lookupReferralCode(code);
      if (!mounted) return;
      setState(() {
        _lookup = r;
        // 识别到可加的人 → 预填真实姓名 (手机号拿不到明文, 用打码显示)
        if (r.canClaim) _nameController.text = r.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('识别失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _lookupLoading = false);
    }
  }

  /// 识别结果提示框 (可加 = 暖色提示; 不可加 = 警示色)
  Widget _lookupHint(ReferralLookup r) {
    if (!r.found) {
      return _hintBox('没找到这个推荐码, 请核对后重试', warn: true);
    }
    if (r.canClaim) {
      final member = r.isMember ? ' · 会员' : '';
      return _hintBox(
        '已识别: ${r.name}${r.phoneMasked.isEmpty ? '' : ' (${r.phoneMasked})'}$member\n'
        '保存后把她加为你的客户 (不新建重复档案, 之后可继续编辑资料)',
      );
    }
    return _hintBox('已识别: ${r.name} — ${r.claimLabel}', warn: true);
  }

  Widget _hintBox(String text, {bool warn = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s10),
      decoration: BoxDecoration(
        color: warn ? AppTheme.bgWarm : AppTheme.primaryLight,
        borderRadius: BorderRadius.circular(AppRadius.r10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTheme.fontXs,
          height: 1.5,
          color: warn ? AppTheme.textSecondary : AppTheme.primaryDark,
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      // 新建 + 填了推荐码但还没点「识别」→ 先识别 (直接保存也兜得住)
      if (widget.customerId == null &&
          _refCodeController.text.trim().isNotEmpty &&
          _lookup == null) {
        await _lookupCode();
        if (_lookup == null) return; // 识别失败已提示
      }
      final lookup = _lookup;
      if (lookup != null) {
        if (!lookup.found) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('推荐码不存在, 请核对后重试')),
          );
          return;
        }
        if (!lookup.canClaim) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(lookup.claimLabel)),
          );
          return;
        }
        // 识别到 → 归属声明 (ADR-0015 Q15 先到先得; 409 会被后端拦下)
        await ref.read(customerServiceProvider).claim(lookup.customerId!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已把 ${lookup.name} 加为我的客户')),
        );
        ref.invalidate(customersProvider);
        ref.invalidate(customerTypeCountsProvider);
        context.pop();
        return;
      }
      final data = <String, dynamic>{
        'name': _nameController.text,
        'phone': _phoneController.text,
        if (_gender != null) 'gender': _gender,
        if (_birthYear != null) 'birthYear': _birthYear!.year,
        // 生日细化 + 提醒 (显式发 null = 清空; 后端按月/日 自动开关提醒)
        'birthMonth': _birthMonth,
        'birthDay': _birthDay,
        'birthCalendar': _birthCalendar,
        'birthdayRemindDays': _birthdayRemindDays,
        'healthTags': _healthTags,
        'diseaseHistory': _diseaseController.text,
        'allergyHistory': _allergyController.text,
        if (_notesController.text.isNotEmpty) 'notes': _notesController.text,
        // ★ Phase C §1 维度 6 + D5 (主人 2026-09-25 拍「选填」):
        //   _acquireSource = null → 不传 acquireSource 字段 (后端默认 null = 未填写);
        //   否则发 4 个枚举之一; 'referral' 时同时必填介绍人 (前端兇底 + 后端 zod refine 兇底)。
        if (_acquireSource != null) ...{
          'acquireSource': _acquireSource,
          if (_acquireSource == 'referral')
            'sourceReferrerName': _sourceReferrerController.text.trim(),
        },
      };
      if (widget.customerId != null) {
        await ref.read(customerServiceProvider).update(widget.customerId!, data);
        ref.read(usageServiceProvider).track('customer_edit');
      } else {
        await ref.read(customerServiceProvider).create(data);
        ref.read(usageServiceProvider).track('customer_create', props: {'source': 'form'});
      }
      if (!mounted) return;
      ref.invalidate(customersProvider);
      ref.invalidate(myFranchiseeTreeProvider);
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customerId == null ? '添加客户' : '编辑客户'),
        toolbarHeight: AppSize.appBarHeight,
      ),
      // ★ 保存**吸底** (2026-09-25 主人): 表单不用滑到底才能保存
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.s16, AppSpace.s8, AppSpace.s16, AppSpace.s12),
          child: FilledButton.icon(
            // 测试契约 key: 吸底保存键 (测试断言"滚动时不动")
            key: const ValueKey('customerFormSaveButton'),
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: AppSize.iconMd,
                    height: AppSize.iconMd,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: AppSize.iconLg),
            label: Text(widget.customerId == null ? '保存' : '保存修改'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, AppSize.buttonLgHeight),
            ),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.cardPadding),
          children: [
            // 推荐码识别 (只新建时; ADR-0015 Q10): 填已注册朋友的码 → 把她加为客户
            if (widget.customerId == null) ...[
              TextFormField(
                controller: _refCodeController,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) {
                  // 码改了 → 之前的识别结果作废 (避免拿旧结果去 claim)
                  if (_lookup != null &&
                      v.trim().toUpperCase() != _lookup!.code) {
                    setState(() => _lookup = null);
                  }
                },
                decoration: InputDecoration(
                  labelText: '推荐码 (可选)',
                  hintText: '6 位字母数字',
                  helperText: '朋友的推荐码: 填了可把已注册的她加为客户',
                  suffixIcon: _lookupLoading
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpace.s12),
                          child: SizedBox(
                            width: AppSpace.s18,
                            height: AppSpace.s18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : TextButton(
                          onPressed: _loading ? null : _lookupCode,
                          child: const Text('识别',
                              style: TextStyle(fontSize: AppTheme.fontSm)),
                        ),
                ),
              ),
              if (_lookup != null) ...[
                const SizedBox(height: AppSpace.s8),
                _lookupHint(_lookup!),
              ],
              const SizedBox(height: AppSpace.s12),
            ],
            // ★ 姓名 / 性别 / 手机号 **一行** (2026-09-25 主人: 「排版要更紧凑,
            //   姓名、性别、电话完全可以并排到同一行」)
            //   性别从"三个大按钮占一行"改成紧凑下拉 —— 这栏本来就只有一个值。
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: TextFormField(
                    controller: _nameController,
                    style: const TextStyle(fontSize: AppTheme.fontMd),
                    readOnly: _claimMode, // 已注册用户用她的真实姓名 (claim 不改档案)
                    decoration: InputDecoration(
                      labelText: '姓名 *',
                      helperText: _claimMode ? '用对方账号的真实姓名 (不能改)' : null,
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _gender ?? 'U',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '性别'),
                    items: const [
                      DropdownMenuItem(
                          value: 'F',
                          child: Text('女',
                              style: TextStyle(fontSize: AppTheme.fontMd))),
                      DropdownMenuItem(
                          value: 'M',
                          child: Text('男',
                              style: TextStyle(fontSize: AppTheme.fontMd))),
                      DropdownMenuItem(
                          value: 'U',
                          child: Text('未知',
                              style: TextStyle(fontSize: AppTheme.fontMd))),
                    ],
                    onChanged: (v) => setState(() => _gender = v ?? 'U'),
                  ),
                ),
                // 已注册用户: 手机号在对方账号里, 不需要录 (档案已存在)
                if (!_claimMode) ...[
                  const SizedBox(width: AppSpace.s8),
                  Expanded(
                    flex: 4,
                    child: TextFormField(
                      controller: _phoneController,
                      style: const TextStyle(fontSize: AppTheme.fontMd),
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: '手机号 *'),
                      validator: (v) {
                        if (v == null ||
                            !RegExp(r'^1[3-9]\d{9}$').hasMatch(v)) {
                          return '请输入正确的手机号';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            // ===== 客户来源 (Phase C §1 维度 6 + §4.2 L4, D5 + D6 插入位置)
            //   设计拍: 姓名/性别/手机 与 生日 之间; 选填; 选「转介绍」时介绍人必填。
            //   4 个枚举 + 「未填写」(下拉以 value '' 表示, 不发字段)。
            //   后端 zod refine 校验 referral 时介绍人必填 (§5 M3, 不加 DB CHECK)。
            //   遵约束: 不新增 Card, 走现有 InputDecoration 控件; 不涨行高。
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _acquireSource ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '客户来源',
                      helperText: '选填；选「转介绍」时介绍人必填',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: '',
                        child: Text('未填写',
                            style: TextStyle(fontSize: AppTheme.fontMd)),
                      ),
                      DropdownMenuItem(
                        value: 'friend',
                        child: Text('亲友',
                            style: TextStyle(fontSize: AppTheme.fontMd)),
                      ),
                      DropdownMenuItem(
                        value: 'referral',
                        child: Text('转介绍',
                            style: TextStyle(fontSize: AppTheme.fontMd)),
                      ),
                      DropdownMenuItem(
                        value: 'cold_visit',
                        child: Text('陌生拜访',
                            style: TextStyle(fontSize: AppTheme.fontMd)),
                      ),
                      DropdownMenuItem(
                        value: 'ground_promo',
                        child: Text('地推',
                            style: TextStyle(fontSize: AppTheme.fontMd)),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      // '' = 未填写 (null), 避免发字段; 其他为 4 个枚举
                      _acquireSource = (v == null || v.isEmpty) ? null : v;
                      // 切走「转介绍」→ 清空介绍人 (避免误带旧名字)
                      if (_acquireSource != 'referral') {
                        _sourceReferrerController.clear();
                      }
                    }),
                  ),
                ),
              ],
            ),
            // 转介绍 → 介绍人必填 (前端兇底 + 后端 zod refine 兑底)
            if (_acquireSource == 'referral') ...[
              const SizedBox(height: AppSpace.s8),
              TextFormField(
                controller: _sourceReferrerController,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                maxLength: 50,
                decoration: const InputDecoration(
                  labelText: '介绍人 *',
                  hintText: '例: 张姐 / 李姐',
                  counterText: '',
                ),
                validator: (v) {
                  if (_acquireSource != 'referral') return null;
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return '转介绍请填介绍人';
                  return null;
                },
              ),
            ],
            const SizedBox(height: AppSpace.s12),
            // ===== 生日 (主人 2026-09-18: 年月日可选填 + 农历/阳历 + 生日提醒) =====
            // 2026-09-25: 历法收进标题行 (省一整行)
            Row(
              children: [
                const Text('生日', style: TextStyle(fontSize: AppTheme.fontMd)),
                const Spacer(),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'solar',
                        label: Text('阳历', style: TextStyle(fontSize: AppType.xs))),
                    ButtonSegment(
                        value: 'lunar',
                        label: Text('农历', style: TextStyle(fontSize: AppType.xs))),
                  ],
                  selected: {_birthCalendar},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      minimumSize:
                          WidgetStatePropertyAll(Size(0, AppSize.controlLg))),
                  onSelectionChanged: (v) =>
                      setState(() => _birthCalendar = v.first),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s4),
            const Text(
              '知道多少填多少, 不知道的留空 (例: 只记得属相/年份 → 只填年; 过农历生日 → 切「农历」)',
              style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppSpace.s8),
            Row(
              children: [
                Expanded(
                  child: _birthPickerButton(
                    label: '年',
                    value: _birthYear == null ? null : '${_birthYear!.year}',
                    onPick: _pickBirthYear,
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: _birthPickerButton(
                    label: '月',
                    value: _birthMonth == null ? null : '$_birthMonth',
                    onPick: () => _pickBirthPart(isMonth: true),
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: _birthPickerButton(
                    label: '日',
                    value: _birthDay == null ? null : '$_birthDay',
                    onPick: () => _pickBirthPart(isMonth: false),
                  ),
                ),
              ],
            ),
            // 月+日 都填了 = 开启生日提醒 (提醒强度可选)
            if (_birthMonth != null && _birthDay != null) ...[
              const SizedBox(height: AppSpace.s12),
              Container(
                padding: const EdgeInsets.all(AppSpace.s12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(AppRadius.r10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.notifications_active_outlined,
                            size: AppSize.iconMd, color: AppTheme.accent),
                        SizedBox(width: AppSpace.s6),
                        Text('生日提醒 (已开启)',
                            style: TextStyle(
                                fontSize: AppTheme.fontSm,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: AppSpace.s8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final d in const [7, 3, 0])
                          ChoiceChip(
                            label: Text(
                              d == 0 ? '生日当天' : '提前 $d 天',
                              style: const TextStyle(fontSize: AppTheme.fontSm),
                            ),
                            selected: _birthdayRemindDays == d,
                            onSelected: (_) =>
                                setState(() => _birthdayRemindDays = d),
                          ),
                        ChoiceChip(
                          label: const Text('不提醒',
                              style: TextStyle(fontSize: AppTheme.fontSm)),
                          selected: _birthdayRemindDays == null,
                          onSelected: (_) =>
                              setState(() => _birthdayRemindDays = null),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpace.s12),
            // ===== 健康标签 (默认候选 + 自定义, 单个 ≤6 汉字; 主人 2026-09-18) =====
            const Text('健康标签', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: AppSpace.s4),
            const Text(
              '点一下选中/取消; 也可以自己加 (最多 6 个字)',
              style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppSpace.s8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 已选中的标签 (排前面, 一眼看全)
                ..._healthTags.map((t) => InputChip(
                      label: Text(t, style: const TextStyle(fontSize: AppTheme.fontSm)),
                      selected: true,
                      selectedColor: AppTheme.primaryLight,
                      onDeleted: () => setState(() => _healthTags.remove(t)),
                    )),
                // 默认候选 (未选中的)
                ..._defaultHealthTags
                    .where((t) => !_healthTags.contains(t))
                    .map((t) => FilterChip(
                          label: Text(t,
                              style: const TextStyle(fontSize: AppTheme.fontSm)),
                          selected: false,
                          onSelected: (_) =>
                              setState(() => _healthTags.add(t)),
                        )),
              ],
            ),
            const SizedBox(height: AppSpace.s8),
            // 自定义标签输入 (≤6 汉字)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customTagController,
                    style: const TextStyle(fontSize: AppTheme.fontMd),
                    maxLength: _maxTagLength,
                    decoration: const InputDecoration(
                      hintText: '自定义 (最多 6 个字)',
                      counterText: '',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _addCustomTag(),
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
                // 定宽: 主题里 OutlinedButton minimumSize = infinity, 在 Row 里会被量成无限宽
                SizedBox(
                  width: AppSpace.s88,
                  height: AppSpace.s48,
                  child: OutlinedButton.icon(
                    onPressed: _addCustomTag,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: EdgeInsets.zero,
                    ),
                    icon: const Icon(Icons.add, size: AppSize.iconMd),
                    label: const Text('添加', style: TextStyle(fontSize: AppTheme.fontSm)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            // ===== 既往病史 / 过敏史 (主人 2026-09-18: 过敏史新增) =====
            TextField(
              controller: _diseaseController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '既往病史',
                hintText: '例: 高血压(服药中) / 腰椎间盘突出',
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            TextField(
              controller: _allergyController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '过敏史',
                hintText: '例: 青霉素过敏 / 对薰衣草精油过敏 / 皮肤敏感',
              ),
            ),
            const SizedBox(height: AppSpace.s12),
            TextFormField(
              controller: _notesController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              // 2026-09-25: 3 行 → 2 行 (排版紧凑; 要写长文进详情页的备注卡看)
              maxLines: 2,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            const SizedBox(height: AppSpace.s24),
          ],
        ),
      ),
    );
  }



}