import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/customer.dart';
import '../../providers/service_providers.dart';
import '../customers/customer_detail_screen.dart';

import 'package:nuankebao/core/theme/tokens.g.dart';
class CustomerFormScreen extends ConsumerStatefulWidget {
  final String? customerId; // null = 新增
  const CustomerFormScreen({super.key, this.customerId});

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthYearController = TextEditingController();
  final _diseaseHistoryController = TextEditingController();
  final _notesController = TextEditingController();
  String _gender = 'F';
  List<String> _healthTags = [];
  bool _loading = false;
  bool _initialized = false;

  static const _healthTagOptions = [
    '肩颈', '腰部', '膝盖', '睡眠差', '体寒', '湿气重',
    '月经不调', '消化不良', '免疫力低', '压力大',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _birthYearController.dispose();
    _diseaseHistoryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadIfEdit() async {
    if (_initialized || widget.customerId == null) {
      _initialized = true;
      return;
    }
    final customer = await ref.read(customerDetailProvider(widget.customerId!).future);
    if (mounted) {
      _nameController.text = customer.name;
      _phoneController.text = customer.phone;
      _birthYearController.text = customer.birthYear?.toString() ?? '';
      _diseaseHistoryController.text = customer.diseaseHistory ?? '';
      _notesController.text = customer.notes ?? '';
      _gender = customer.gender ?? 'F';
      _healthTags = List.of(customer.healthTags);
      setState(() => _initialized = true);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final data = {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'gender': _gender,
      if (_birthYearController.text.isNotEmpty)
        'birthYear': int.tryParse(_birthYearController.text),
      'healthTags': _healthTags,
      if (_diseaseHistoryController.text.isNotEmpty)
        'diseaseHistory': _diseaseHistoryController.text.trim(),
      if (_notesController.text.isNotEmpty)
        'notes': _notesController.text.trim(),
    };

    try {
      final service = ref.read(customerServiceProvider);
      final customer = widget.customerId == null
          ? await service.create(data)
          : await service.update(widget.customerId!, data);
      if (mounted) {
        context.go('/customers/${customer.id}');
      }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.customerId == null ? '新增客户' : '编辑客户'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: '姓名 *'),
                validator: (v) => v!.trim().isEmpty ? '请输入姓名' : null,
              ),
              const SizedBox(height: AppSpace.s12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 11,
                decoration: const InputDecoration(labelText: '手机号 *', counterText: ''),
                validator: (v) => !RegExp(r'^1[3-9]\d{9}$').hasMatch(v!) ? '手机号格式错误' : null,
              ),
              const SizedBox(height: AppSpace.s12),
              DropdownButtonFormField<String>(
                value: _gender,
                decoration: const InputDecoration(labelText: '性别'),
                items: const [
                  DropdownMenuItem(value: 'F', child: Text('女')),
                  DropdownMenuItem(value: 'M', child: Text('男')),
                  DropdownMenuItem(value: 'U', child: Text('未知')),
                ],
                onChanged: (v) => setState(() => _gender = v!),
              ),
              const SizedBox(height: AppSpace.s12),
              TextFormField(
                controller: _birthYearController,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: const InputDecoration(labelText: '出生年', counterText: ''),
              ),
              const SizedBox(height: AppSpace.s16),
              const Text('健康标签 (多选)', style: TextStyle(fontSize: AppType.xs, fontWeight: FontWeight.w500)),
              const SizedBox(height: AppSpace.s8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _healthTagOptions.map((tag) {
                  final selected = _healthTags.contains(tag);
                  return FilterChip(
                    label: Text(tag),
                    selected: selected,
                    onSelected: (v) => setState(() {
                      if (v) {
                        _healthTags.add(tag);
                      } else {
                        _healthTags.remove(tag);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpace.s16),
              TextFormField(
                controller: _diseaseHistoryController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '既往病史 / 过敏史'),
              ),
              const SizedBox(height: AppSpace.s12),
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '备注'),
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
      ),
    );
  }
}
