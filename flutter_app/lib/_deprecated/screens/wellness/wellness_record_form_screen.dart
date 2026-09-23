import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/dictionaries.dart';
import '../../widgets/photo_picker.dart';
import '../../providers/service_providers.dart';
import '../wellness/wellness_records_list_screen.dart';
import '../wellness/wellness_record_detail_screen.dart';

import 'package:nuankebao/core/theme/tokens.g.dart';
class WellnessRecordFormScreen extends ConsumerStatefulWidget {
  final String? recordId; // null = 新增
  final String? customerId; // 新增时预选客户

  const WellnessRecordFormScreen({super.key, this.recordId, this.customerId});

  @override
  ConsumerState<WellnessRecordFormScreen> createState() => _WellnessRecordFormScreenState();
}

class _WellnessRecordFormScreenState extends ConsumerState<WellnessRecordFormScreen> {
  final _customerIdController = TextEditingController();
  final _serviceDateController = TextEditingController();
  String? _serviceItemId;
  Set<String> _bodyPartIds = {};
  int? _painLevelPre, _sleepQualityPre, _painLevelPost, _sleepQualityPost;
  final _processNoteController = TextEditingController();
  final _feedbackController = TextEditingController();
  final _nextAdviceDateController = TextEditingController();
  List<String> _photos = [];
  bool _loading = false;
  bool _initialized = false;
  Dictionaries? _dict;

  @override
  void initState() {
    super.initState();
    _serviceDateController.text = DateTime.now().toIso8601String().substring(0, 10);
    if (widget.customerId != null) {
      _customerIdController.text = widget.customerId!;
    }
  }

  @override
  void dispose() {
    _customerIdController.dispose();
    _serviceDateController.dispose();
    _processNoteController.dispose();
    _feedbackController.dispose();
    _nextAdviceDateController.dispose();
    super.dispose();
  }

  Future<void> _loadIfEdit() async {
    if (_initialized) return;
    final dict = await ref.read(dictionariesProvider.future);
    _dict = dict;
    if (widget.recordId != null) {
      final record = await ref.read(wellnessRecordDetailProvider(widget.recordId!).future);
      if (mounted) {
        _customerIdController.text = record.customerId;
        _serviceDateController.text = record.serviceDate;
        _serviceItemId = record.serviceItemId;
        _bodyPartIds = record.bodyPartIds.toSet();
        _painLevelPre = record.preCondition['pain_level'] as int?;
        _sleepQualityPre = record.preCondition['sleep_quality'] as int?;
        _painLevelPost = record.postCondition['pain_level'] as int?;
        _sleepQualityPost = record.postCondition['sleep_quality'] as int?;
        _processNoteController.text = record.processNote ?? '';
        _feedbackController.text = record.customerFeedback ?? '';
        _nextAdviceDateController.text = record.nextAdviceDate ?? '';
        _photos = List.of(record.photos);
        setState(() => _initialized = true);
      }
    } else {
      setState(() => _initialized = true);
    }
  }

  Future<void> _save() async {
    if (_customerIdController.text.isEmpty || _serviceItemId == null || _bodyPartIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写客户 / 项目 / 部位')),
      );
      return;
    }
    setState(() => _loading = true);

    try {
      // 1. 先上传所有 base64 图片
      final photoService = ref.read(photoServiceProvider);
      final uploadedUrls = <String>[];
      for (final photo in _photos) {
        if (photo.startsWith('data:')) {
          // base64, 需要上传
          final url = await photoService.upload(photo);
          uploadedUrls.add(url);
        } else {
          // 已经是 URL
          uploadedUrls.add(photo);
        }
      }

      // 2. 保存记录 (用上传后的 URL)
      final data = {
        'customerId': _customerIdController.text,
        'serviceDate': _serviceDateController.text,
        'serviceItemId': _serviceItemId,
        'bodyPartIds': _bodyPartIds.toList(),
        'preCondition': {
          if (_painLevelPre != null) 'pain_level': _painLevelPre,
          if (_sleepQualityPre != null) 'sleep_quality': _sleepQualityPre,
        },
        'postCondition': {
          if (_painLevelPost != null) 'pain_level': _painLevelPost,
          if (_sleepQualityPost != null) 'sleep_quality': _sleepQualityPost,
        },
        if (_processNoteController.text.isNotEmpty)
          'processNote': _processNoteController.text,
        if (_feedbackController.text.isNotEmpty)
          'customerFeedback': _feedbackController.text,
        if (_nextAdviceDateController.text.isNotEmpty)
          'nextAdviceDate': _nextAdviceDateController.text,
        'photos': uploadedUrls,
      };

      final service = ref.read(wellnessRecordServiceProvider);
      final record = widget.recordId == null
          ? await service.create(data)
          : await service.update(widget.recordId!, data);
      if (mounted) context.go('/wellness-records/${record.id}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _loadIfEdit();
    if (_dict == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.recordId == null ? '新增养生记录' : '编辑养生记录')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 基本
            TextField(
              controller: _customerIdController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '客户 ID *'),
            ),
            const SizedBox(height: AppSpace.s12),
            TextField(
              controller: _serviceDateController,
              decoration: const InputDecoration(labelText: '服务日期 * (YYYY-MM-DD)'),
            ),
            const SizedBox(height: AppSpace.s12),
            DropdownButtonFormField<String>(
              value: _serviceItemId,
              decoration: const InputDecoration(labelText: '服务项目 *'),
              items: _dict!.serviceItems
                  .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                  .toList(),
              onChanged: (v) => setState(() => _serviceItemId = v),
            ),
            const SizedBox(height: AppSpace.s16),

            // 身体部位 (多选)
            const Text('身体部位 (多选) *', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: AppSpace.s8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _dict!.bodyParts.map((b) {
                final selected = _bodyPartIds.contains(b.id);
                return FilterChip(
                  label: Text(b.name),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _bodyPartIds.add(b.id);
                    } else {
                      _bodyPartIds.remove(b.id);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpace.s16),

            // 状态评分
            const Text('理疗前', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: AppSpace.s8),
            Row(
              children: [
                Expanded(child: _NumberField(
                  label: '疼痛度 (0-10)',
                  value: _painLevelPre,
                  onChanged: (v) => setState(() => _painLevelPre = v),
                )),
                const SizedBox(width: AppSpace.s12),
                Expanded(child: _NumberField(
                  label: '睡眠质量 (0-10)',
                  value: _sleepQualityPre,
                  onChanged: (v) => setState(() => _sleepQualityPre = v),
                )),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            const Text('理疗后', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: AppSpace.s8),
            Row(
              children: [
                Expanded(child: _NumberField(
                  label: '疼痛度 (0-10)',
                  value: _painLevelPost,
                  onChanged: (v) => setState(() => _painLevelPost = v),
                )),
                const SizedBox(width: AppSpace.s12),
                Expanded(child: _NumberField(
                  label: '睡眠质量 (0-10)',
                  value: _sleepQualityPost,
                  onChanged: (v) => setState(() => _sleepQualityPost = v),
                )),
              ],
            ),
            const SizedBox(height: AppSpace.s16),

            // 过程 + 反馈
            TextField(
              controller: _processNoteController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '理疗过程'),
            ),
            const SizedBox(height: AppSpace.s12),
            TextField(
              controller: _feedbackController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '客户反馈'),
            ),
            const SizedBox(height: AppSpace.s12),
            TextField(
              controller: _nextAdviceDateController,
              decoration: const InputDecoration(labelText: '下次建议日期 (YYYY-MM-DD)'),
            ),
            const SizedBox(height: AppSpace.s16),
            PhotoPicker(
              photoUrls: _photos,
              onChanged: (newPhotos) => setState(() => _photos = newPhotos),
            ),
            const SizedBox(height: AppSpace.s24),
            ElevatedButton(
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(width: AppSpace.s20, height: AppSpace.s20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  const _NumberField({required this.label, required this.value, required this.onChanged});

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = widget.value?.toString() ?? '';
  }

  @override
  void didUpdateWidget(_NumberField old) {
    super.didUpdateWidget(old);
    if (widget.value != old.value) {
      _controller.text = widget.value?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: widget.label),
      onChanged: (v) {
        final n = int.tryParse(v);
        widget.onChanged(n);
      },
    );
  }
}
