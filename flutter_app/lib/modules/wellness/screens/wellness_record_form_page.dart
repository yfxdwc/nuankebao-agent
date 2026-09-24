// ============================================
// 养生记录表单 (Plan F2.5)
// 强绑 customerId (来自 query param)
// 结构化字段: 部位 + 服务 + 评分 + 反馈 + 照片 + 下次建议
// 中老年大字 + 大按钮
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/dictionaries.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/widgets/app_empty.dart';
import '../../../core/widgets/app_section.dart';

import '../widgets/rating_slider.dart';
import '../widgets/wellness_photo_uploader.dart';

import '../../../core/theme/tokens.g.dart';
/// 新增记录时默认选中的服务项目 (主人 2026-09-18 拍: 「碧波庭-脉动负压提拉按摩」置顶 + 下拉 + 默认选中)
/// 字典里找不到 → 不预选 (不硬编码假项目), 用户自己选
const String _defaultServiceItemName = '碧波庭-脉动负压提拉按摩';

class WellnessRecordFormPage extends ConsumerStatefulWidget {
  final String? recordId;
  final String? customerId; // 来自 query param (?customerId=X)

  const WellnessRecordFormPage({
    super.key,
    this.recordId,
    this.customerId,
  }) : assert(recordId != null || customerId != null,
            'recordId 或 customerId 必须有一个');

  @override
  ConsumerState<WellnessRecordFormPage> createState() => _WellnessRecordFormPageState();
}

class _WellnessRecordFormPageState extends ConsumerState<WellnessRecordFormPage> {
  // 字典 —— null = 加载中; 非 null (含空字典) = 加载完成
  Dictionaries? _dict;

  // 字典加载失败 (B4, 2026-09-24 修「无限转圈」: 抛异常时进入错误态, 不是死循环)
  Object? _dictError;

  // 选中字段
  final Set<String> _bodyPartIds = {};
  String? _serviceItemId;
  int _prePainLevel = 5;
  int _preSleep = 3;
  int _preMood = 3;
  int _postPainLevel = 3;
  int _postSleep = 3;
  int _postMood = 3;
  final _processCtrl = TextEditingController();
  final _feedbackCtrl = TextEditingController();
  DateTime? _nextAdviceDate;
  List<String> _photoUrls = [];

  bool _loading = false;
  String? _effectiveCustomerId;

  /// 新建时是否已按「上一次记录」预填 (P3 提速, 主人 2026-09-23 拍)
  ///
  /// 为什么这是记录提速的最大单点 (预估 ~50s → ~5s):
  ///   连续到店的客户, **上次结束的状态物理上就是这次开始的状态**。
  ///   原先却写死 `_prePainLevel = 5`, 逼销售重新拖 6 次滑块。
  ///   现在直接拿上次的 post* 当前 pre*, 并且 post* 默认 = pre* (="无变化"),
  ///   真的没变化时**一跳直达保存**。
  bool _prefilledFromLast = false;

  /// 预填来源的那次记录日期 (UI 提示用: "按 9月12日那次填好")
  String? _prefilledFromDate;

  @override
  void initState() {
    super.initState();
    _loadDict();
    if (widget.recordId != null) {
      _loadExisting();
    } else {
      _effectiveCustomerId = widget.customerId;
      // 新建 → 尝试沿用上次 (拿不到就静默回落原来的写死默认值)
      _loadLastRecord();
    }
  }

  Future<void> _loadDict() async {
    try {
      final d = await ref.read(dictionaryServiceProvider).all();
      if (!mounted) return;
      setState(() {
        _dict = d;
        _dictError = null;
        // 新增: 默认选中「碧波庭-脉动负压提拉按摩」
        // 编辑: _loadExisting() 已填好原值 (谁后到谁生效, 两边都不覆盖非空值)
        _serviceItemId ??= _defaultServiceItemIdOf(d);
      });
    } catch (e) {
      if (!mounted) return;
      // 修「无限转圈」: body 用 _dict == null 渲染 LoadingState, 抛异常时
      // _dict 永远是 null → 永远 LoadingState → 永远转圈。必须切到错误态。
      setState(() => _dictError = e);
    }
  }

  /// 找默认服务项目 id: 先精确匹配全名, 再宽松匹配「碧波庭」, 都没有 → null
  String? _defaultServiceItemIdOf(Dictionaries d) {
    for (final s in d.serviceItems) {
      if (s.name.trim() == _defaultServiceItemName) return s.id;
    }
    for (final s in d.serviceItems) {
      if (s.name.contains('碧波庭')) return s.id;
    }
    return null;
  }

  /// 新建时沿用「该客户上一次记录」(P3 提速)
  ///
  /// 口径 (为什么取 post 当这次的 pre):
  ///   上次「做完之后」的身体状态 = 这次「开始之前」的状态。中间没有服务,
  ///   所以这是**物理等价的**, 不是拍脑袋。
  ///
  /// 拿不到上次记录 (首次到店) → 什么都不做, 保留原默认值。
  Future<void> _loadLastRecord() async {
    final cid = _effectiveCustomerId;
    if (cid == null) return;
    try {
      final list = await ref
          .read(wellnessRecordServiceProvider)
          .list(customerId: cid, limit: 1);
      if (!mounted || list.isEmpty) return;
      final last = list.first;
      setState(() {
        // 部位 / 服务: 大概率一样 (同一疗程) —— 但不覆盖用户已手动改过的值
        _bodyPartIds.addAll(last.bodyPartIds);
        _serviceItemId = last.serviceItemId;

        // 本次的「前」= 上次的「后」
        final pPain = (last.postCondition['pain_level'] as num?)?.toInt();
        final pSleep = (last.postCondition['sleep_quality'] as num?)?.toInt();
        final pMood = (last.postCondition['mood'] as num?)?.toInt();
        if (pPain != null) _prePainLevel = pPain;
        if (pSleep != null) _preSleep = pSleep;
        if (pMood != null) _preMood = pMood;

        // 本次的「后」默认 = 「前」→ 改善量为 0 (= "没变化", 中性而非虚报效果)
        _postPainLevel = _prePainLevel;
        _postSleep = _preSleep;
        _postMood = _preMood;

        _prefilledFromLast = true;
        _prefilledFromDate = last.serviceDate;
      });
    } catch (_) {
      // 预填失败不算错 —— 退化成"从默认值开始填", 绝不能让表单打不开
    }
  }

  /// 「清空重填」—— 不想沿用上次时用 (回到出厂默认)
  void _resetToDefaults() {
    setState(() {
      _bodyPartIds.clear();
      _serviceItemId = _dict == null ? null : _defaultServiceItemIdOf(_dict!);
      _prePainLevel = 5;
      _preSleep = 3;
      _preMood = 3;
      _postPainLevel = 3;
      _postSleep = 3;
      _postMood = 3;
      _prefilledFromLast = false;
      _prefilledFromDate = null;
    });
  }

  Future<void> _loadExisting() async {
    final r = await ref.read(wellnessRecordServiceProvider).getById(widget.recordId!);
    if (!mounted) return;
    setState(() {
      _effectiveCustomerId = r.customerId;
      _bodyPartIds.addAll(r.bodyPartIds);
      _serviceItemId = r.serviceItemId;
      _processCtrl.text = r.processNote ?? '';
      _feedbackCtrl.text = r.customerFeedback ?? '';
      _nextAdviceDate = r.nextAdviceDate != null ? DateTime.tryParse(r.nextAdviceDate!) : null;
      _photoUrls.addAll(r.photos);
      // preCondition / postCondition: {pain_level, sleep_quality, mood}
      _prePainLevel = (r.preCondition['pain_level'] as num?)?.toInt() ?? 5;
      _preSleep = (r.preCondition['sleep_quality'] as num?)?.toInt() ?? 3;
      _preMood = (r.preCondition['mood'] as num?)?.toInt() ?? 3;
      _postPainLevel = (r.postCondition['pain_level'] as num?)?.toInt() ?? 3;
      _postSleep = (r.postCondition['sleep_quality'] as num?)?.toInt() ?? 3;
      _postMood = (r.postCondition['mood'] as num?)?.toInt() ?? 3;
    });
  }

  @override
  void dispose() {
    _processCtrl.dispose();
    _feedbackCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_serviceItemId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请选择服务项目',
          style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
      return;
    }
    setState(() => _loading = true);

    final data = <String, dynamic>{
      'customerId': _effectiveCustomerId,
      'serviceDate': DateTime.now().toIso8601String().split('T').first,
      'serviceItemId': _serviceItemId,
      'bodyPartIds': _bodyPartIds.toList(),
      'preCondition': {
        'pain_level': _prePainLevel,
        'sleep_quality': _preSleep,
        'mood': _preMood,
      },
      'postCondition': {
        'pain_level': _postPainLevel,
        'sleep_quality': _postSleep,
        'mood': _postMood,
      },
      if (_processCtrl.text.isNotEmpty) 'processNote': _processCtrl.text,
      if (_feedbackCtrl.text.isNotEmpty) 'customerFeedback': _feedbackCtrl.text,
      if (_nextAdviceDate != null)
        'nextAdviceDate': _nextAdviceDate!.toIso8601String().split('T').first,
      'photos': _photoUrls,
    };

    try {
      if (widget.recordId != null) {
        await ref.read(wellnessRecordServiceProvider).update(widget.recordId!, data);
        ref.read(usageServiceProvider).track('record_edit');
      } else {
        await ref.read(wellnessRecordServiceProvider).create(data);
        ref.read(usageServiceProvider).track('record_create');
      }
      if (!mounted) return;
      ref.invalidate(customerWellnessRecordsProvider(_effectiveCustomerId!));
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e',
          style: const TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recordId == null ? '添加养生记录' : '编辑养生记录'),
        toolbarHeight: AppSize.appBarHeight,
      ),
      body: _dict == null
          ? (_dictError != null
              // 字典加载失败 → 错误态, 给重试按钮 (原则 8: 必须告诉下一步做什么)
              //   ⚠ 不能用 ErrorState.error 直接显示 —— 那是网络错, 这里可能是后端字典接口挂了,
              //   区分文案让用户知道是「字典没加载」, 不是笼统的「网络问题」。
              ? AppEmptyState(
                  icon: Icons.menu_book_outlined,
                  title: '字典没加载出来',
                  hint: '下拉选不了部位 / 服务, 先重试一下',
                  action: FilledButton.icon(
                    onPressed: _loadDict,
                    icon: const Icon(Icons.refresh, size: AppSize.iconMd),
                    label: const Text('重试'),
                  ),
                )
              : const LoadingState())
          : WellnessPhotoUploaderScope(
              upload: (b64) => ref.read(photoServiceProvider).upload(b64),
              child: ListView(
                padding: const EdgeInsets.all(AppSpace.s16),
                children: [
                  // P3 提速: 沿用上次时给一条明确提示
                  //   —— 不提示的话销售不知道已经填好了, 反而会把每个字段重看一遍
                  if (_prefilledFromLast && _prefilledFromDate != null)
                    _PrefillBanner(
                      date: _prefilledFromDate!,
                      onReset: _resetToDefaults,
                    ),
                  if (_prefilledFromLast && _prefilledFromDate != null)
                    const SizedBox(height: AppSpace.s16),
                  _buildServiceSelector(),
                  const SizedBox(height: AppSpace.s20),
                  _buildBodyPartSelector(),
                  const SizedBox(height: AppSpace.s20),
                  _buildConditionSection('理疗前状态'),
                  const SizedBox(height: AppSpace.s20),
                  _buildConditionSection('理疗后效果', isPost: true),
                  const SizedBox(height: AppSpace.s20),
                  _buildTextField('操作过程', _processCtrl, hint: '可记录理疗手法、特殊处理等'),
                  const SizedBox(height: AppSpace.s20),
                  _buildTextField('客户反馈', _feedbackCtrl, hint: '客户说的原话'),
                  const SizedBox(height: AppSpace.s20),
                  _buildDatePicker(),
                  const SizedBox(height: AppSpace.s20),
                  WellnessPhotoUploader(
                    existingUrls: _photoUrls,
                    onChanged: (urls) => setState(() => _photoUrls = urls),
                    onPhotoUploaded: () =>
                        ref.read(usageServiceProvider).track('record_photo_taken'),
                  ),
                  const SizedBox(height: AppSpace.s32),
                  FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox(
                            width: AppSize.iconLg,
                            height: AppSize.iconLg,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: AppSize.iconLg),
                    label: Text(widget.recordId == null ? '保存' : '保存修改'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, AppSize.buttonLgHeight),
                    ),
                  ),
                  const SizedBox(height: AppSpace.s24),
                ],
              ),
            ),
    );
  }

  Widget _buildBodyPartSelector() {    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '身体部位 (可多选)',
          style: TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpace.s4),
        Text(
          '已选 ${_bodyPartIds.length} 个',
          style: const TextStyle(
            fontSize: AppTheme.fontSm,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpace.s12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _dict!.bodyParts.map((bp) {
            final selected = _bodyPartIds.contains(bp.id);
            return FilterChip(
              label: Text(
                bp.name,
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: selected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
              selected: selected,
              onSelected: (v) => setState(() {
                if (v) {
                  _bodyPartIds.add(bp.id);
                } else {
                  _bodyPartIds.remove(bp.id);
                }
              }),
              selectedColor: AppTheme.primary,
              checkmarkColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s8),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildServiceSelector() {
    final items = _dict!.serviceItems;
    // 防御: 编辑历史记录时, 若其服务项目已被字典删除, Dropdown 会断言崩 → 降级为未选
    final value =
        items.any((s) => s.id == _serviceItemId) ? _serviceItemId : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '服务项目 (单选) *',
          style: TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpace.s8),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          itemHeight: 56,
          decoration: const InputDecoration(hintText: '请选择服务项目'),
          icon: const Icon(Icons.arrow_drop_down,
              size: AppSize.iconXl, color: AppTheme.primary),
          dropdownColor: AppTheme.bgCard,
          style: const TextStyle(
            fontSize: AppTheme.fontMd,
            color: AppTheme.textPrimary,
          ),
          items: items
              .map((s) => DropdownMenuItem<String>(
                    value: s.id,
                    child: Text(
                      s.name,
                      style: const TextStyle(
                        fontSize: AppTheme.fontMd,
                        color: AppTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _serviceItemId = v),
        ),
      ],
    );
  }

  Widget _buildConditionSection(String title, {bool isPost = false}) {
    // B2: 旧 B2NoChrome(margin: zero) → AppSection (无边框/无阴影) + 内层 padding
    // 标题用户已写 Text → 内层用 Section-style Container
    return Padding(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppSectionHeader(title: title),
          const SizedBox(height: AppSpace.s8),
          Container(
            padding: const EdgeInsets.all(AppSpace.s16),
            decoration: BoxDecoration(
              color: context.tokens.surfaceSunken,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PainSlider(
                  label: '疼痛程度',
                  value: isPost ? _postPainLevel : _prePainLevel,
                  onChanged: (v) => setState(() {
                    if (isPost) {
                      _postPainLevel = v;
                    } else {
                      _prePainLevel = v;
                    }
                  }),
                ),
                const SizedBox(height: AppSpace.s16),
                FiveRatingSlider(
                  label: '睡眠质量',
                  value: isPost ? _postSleep : _preSleep,
                  onChanged: (v) => setState(() {
                    if (isPost) {
                      _postSleep = v;
                    } else {
                      _preSleep = v;
                    }
                  }),
                ),
                const SizedBox(height: AppSpace.s16),
                FiveRatingSlider(
                  label: '情绪',
                  value: isPost ? _postMood : _preMood,
                  onChanged: (v) => setState(() {
                    if (isPost) {
                      _postMood = v;
                    } else {
                      _preMood = v;
                    }
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController ctrl, {String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpace.s8),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: AppTheme.fontMd),
          maxLines: 3,
          minLines: 2,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.all(AppSpace.s16),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '下次建议日期',
          style: TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpace.s8),
        OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _nextAdviceDate ?? DateTime.now().add(const Duration(days: 7)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
            );
            if (picked != null) setState(() => _nextAdviceDate = picked);
          },
          icon: const Icon(Icons.calendar_today, size: AppSize.iconLg),
          label: Text(
            _nextAdviceDate == null
                ? '选择日期 (可选)'
                : '${_nextAdviceDate!.year}-${_nextAdviceDate!.month.toString().padLeft(2, '0')}-${_nextAdviceDate!.day.toString().padLeft(2, '0')}',
            style: const TextStyle(fontSize: AppTheme.fontMd),
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 64),
          ),
        ),
      ],
    );
  }
}
/// 「已按上次填好」提示条 (P3 记录提速)
///
/// 为什么必须有这条: 自动预填是"静默"的 —— 不提示的话销售不知道已经填好了,
///   反而会把每个字段再检查一遍, 提速效果归零。提示 + 「清空重填」两者缺一不可。
class _PrefillBanner extends StatelessWidget {
  const _PrefillBanner({required this.date, required this.onReset});

  final String date;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.s12, AppSpace.s10, AppSpace.s8, AppSpace.s10),
      decoration: BoxDecoration(
        color: t.primarySurface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: t.primaryLight),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: AppSize.iconMd, color: t.primaryDark),
          const SizedBox(width: AppSpace.s8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '已按 $date 那次填好',
                  style: TextStyle(
                    fontSize: AppType.sm,
                    fontWeight: AppWeight.semibold,
                    color: t.primaryDark,
                  ),
                ),
                const SizedBox(height: AppSpace.s2),
                Text(
                  '没变化可直接保存; 有变化只改对应项',
                  style: TextStyle(fontSize: AppType.xs, color: t.textSecondary),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onReset,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AppSize.controlSm),
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('清空重填'),
          ),
        ],
      ),
    );
  }
}
