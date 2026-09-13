// ============================================
// 养生记录表单 (Plan F2.5)
// 强绑 customerId (来自 query param)
// 结构化字段: 部位 + 服务 + 评分 + 反馈 + 照片 + 下次建议
// 中老年大字 + 大按钮
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/dictionaries.dart';
import '../providers/service_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/big_button.dart';
import '../widgets/rating_slider.dart';
import '../widgets/wellness_photo_uploader.dart';

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
  // 字典
  Dictionaries? _dict;

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

  @override
  void initState() {
    super.initState();
    _loadDict();
    if (widget.recordId != null) {
      _loadExisting();
    } else {
      _effectiveCustomerId = widget.customerId;
    }
  }

  Future<void> _loadDict() async {
    final d = await ref.read(dictionaryServiceProvider).all();
    if (!mounted) return;
    setState(() => _dict = d);
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
      } else {
        await ref.read(wellnessRecordServiceProvider).create(data);
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
        toolbarHeight: 64,
      ),
      body: _dict == null
          ? const Center(child: CircularProgressIndicator())
          : WellnessPhotoUploaderScope(
              upload: (b64) => ref.read(photoServiceProvider).upload(b64),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildBodyPartSelector(),
                  const SizedBox(height: 20),
                  _buildServiceSelector(),
                  const SizedBox(height: 20),
                  _buildConditionSection('理疗前状态'),
                  const SizedBox(height: 20),
                  _buildConditionSection('理疗后效果', isPost: true),
                  const SizedBox(height: 20),
                  _buildTextField('操作过程', _processCtrl, hint: '可记录理疗手法、特殊处理等'),
                  const SizedBox(height: 20),
                  _buildTextField('客户反馈', _feedbackCtrl, hint: '客户说的原话'),
                  const SizedBox(height: 20),
                  _buildDatePicker(),
                  const SizedBox(height: 20),
                  WellnessPhotoUploader(
                    existingUrls: _photoUrls,
                    onChanged: (urls) => setState(() => _photoUrls = urls),
                  ),
                  const SizedBox(height: 32),
                  BigButton(
                    label: widget.recordId == null ? '保存' : '保存修改',
                    icon: Icons.check,
                    onPressed: _submit,
                    loading: _loading,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildBodyPartSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '身体部位 (可多选)',
          style: TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '已选 ${_bodyPartIds.length} 个',
          style: const TextStyle(
            fontSize: AppTheme.fontSm,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildServiceSelector() {
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
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _dict!.serviceItems.map((s) {
            final selected = _serviceItemId == s.id;
            return ChoiceChip(
              label: Text(
                s.name,
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  color: selected ? Colors.white : AppTheme.textPrimary,
                ),
              ),
              selected: selected,
              onSelected: (_) => setState(() => _serviceItemId = s.id),
              selectedColor: AppTheme.accent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildConditionSection(String title, {bool isPost = false}) {
    return Card(
      margin: EdgeInsets.zero,
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
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
            const SizedBox(height: 16),
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
        const SizedBox(height: 8),
        TextField(
          controller: ctrl,
          style: const TextStyle(fontSize: AppTheme.fontMd),
          maxLines: 3,
          minLines: 2,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding: const EdgeInsets.all(16),
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
        const SizedBox(height: 8),
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
          icon: const Icon(Icons.calendar_today, size: 24),
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