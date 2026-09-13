// ============================================
// 新增加盟商表单 (Plan F3.5)
// 字段: 姓名 / 手机号 / 推荐人 (可选) / 位置 (left/right) / 备注
// 支持两种模式:
//   - 独立模式: 全字段填
//   - 空位模式 (?parentId=X&sideHint=left): 推荐人 + 位置预填只读
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/franchisee.dart';
import '../providers/service_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/big_button.dart';
import '../widgets/empty_state.dart';

class AddFranchiseePage extends ConsumerStatefulWidget {
  /// 预填的推荐人 ID (从"加到空位"进入)
  final String? parentId;

  /// 预填的 side hint
  final String? sideHint;

  const AddFranchiseePage({
    super.key,
    this.parentId,
    this.sideHint,
  });

  @override
  ConsumerState<AddFranchiseePage> createState() => _AddFranchiseePageState();
}

class _AddFranchiseePageState extends ConsumerState<AddFranchiseePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _selectedParentId;
  String? _selectedSide;
  bool _loading = false;

  bool get _isSlotMode => widget.parentId != null;

  @override
  void initState() {
    super.initState();
    _selectedParentId = widget.parentId;
    _selectedSide = widget.sideHint ?? 'left';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedParentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请选择推荐人',
          style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
      return;
    }
    if (_selectedSide == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '请选择位置 (左/右线)',
            style: TextStyle(fontSize: AppTheme.fontMd),
          ),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(franchiseeServiceProvider).create(
            CreateFranchiseeInput(
              name: _nameCtrl.text.trim(),
              phone: _phoneCtrl.text.trim(),
              referrerId: _selectedParentId,
              sideHint: _selectedSide,
              notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
            ),
          );
      ref.invalidate(myFranchiseeTreeProvider);
      ref.invalidate(franchiseesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已添加加盟商',
          style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('添加失败: $e',
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
        title: Text(_isSlotMode ? '添加下线' : '新增加盟商'),
        toolbarHeight: 64,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 推荐人选择
            _buildParentSelector(),
            const SizedBox(height: 16),

            // 位置选择
            _buildSideSelector(),
            const SizedBox(height: 16),

            // 姓名
            TextFormField(
              controller: _nameCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(labelText: '姓名 *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
            ),
            const SizedBox(height: 16),

            // 手机号
            TextFormField(
              controller: _phoneCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: '手机号 *'),
              validator: (v) {
                if (v == null || !RegExp(r'^1[3-9]\d{9}$').hasMatch(v)) {
                  return '请输入正确的手机号';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 备注
            TextFormField(
              controller: _notesCtrl,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '备注 (可选)',
                hintText: '如: 介绍人 / 备注',
              ),
            ),
            const SizedBox(height: 32),

            BigButton(
              label: _isSlotMode ? '添加为下线' : '添加',
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

  Widget _buildParentSelector() {
    if (_isSlotMode) {
      // 空位模式: 推荐人只读显示
      final asyncParent = ref.watch(_franchiseeProvider(_selectedParentId!));
      return asyncParent.maybeWhen(
        data: (parent) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.franchisee.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.franchisee, width: 2),
            ),
            child: Row(
              children: [
                const Icon(Icons.arrow_downward, color: AppTheme.franchisee, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '推荐人',
                        style: TextStyle(
                          fontSize: AppTheme.fontSm,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      Text(
                        parent.name,
                        style: const TextStyle(
                          fontSize: AppTheme.fontMd,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.franchisee,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        orElse: () => const LoadingState(),
      );
    }

    // 独立模式: 可选推荐人
    final asyncFranchisees = ref.watch(franchiseesProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '推荐人 *',
          style: TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        asyncFranchisees.when(
          loading: () => const LoadingState(),
          error: (e, _) => Text('加载失败: $e'),
          data: (raw) {
            final list = raw.cast<Franchisee>();
            return DropdownButtonFormField<String>(
              value: _selectedParentId,
              isExpanded: true,
              decoration: const InputDecoration(
                hintText: '选择推荐人',
              ),
              items: list.map((f) => DropdownMenuItem(
                value: f.id,
                child: Text(f.name, style: const TextStyle(fontSize: AppTheme.fontMd)),
              )).toList(),
              onChanged: (v) => setState(() => _selectedParentId = v),
              validator: (v) => v == null ? '请选择推荐人' : null,
            );
          },
        ),
      ],
    );
  }

  Widget _buildSideSelector() {
    if (_isSlotMode) {
      // 空位模式: 位置只读
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.franchisee.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.franchisee, width: 2),
        ),
        child: Row(
          children: [
            Icon(
              _selectedSide == 'left' ? Icons.arrow_back : Icons.arrow_forward,
              color: AppTheme.franchisee,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              '位置: ${_selectedSide == 'left' ? '左线' : '右线'}',
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
                color: AppTheme.franchisee,
              ),
            ),
          ],
        ),
      );
    }

    // 独立模式: 大按钮组
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '位置 (左/右线) *',
          style: TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _sideButton('左线', 'left', Icons.arrow_back)),
            const SizedBox(width: 8),
            Expanded(child: _sideButton('右线', 'right', Icons.arrow_forward)),
          ],
        ),
      ],
    );
  }

  Widget _sideButton(String label, String value, IconData icon) {
    final selected = _selectedSide == value;
    return OutlinedButton.icon(
      onPressed: () => setState(() => _selectedSide = value),
      icon: Icon(icon, size: 24),
      label: Text(label, style: const TextStyle(fontSize: AppTheme.fontMd)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 64),
        backgroundColor: selected ? AppTheme.primary : Colors.white,
        foregroundColor: selected ? Colors.white : AppTheme.primary,
        side: BorderSide(
          color: selected ? AppTheme.primary : AppTheme.primary.withOpacity(0.4),
          width: 2,
        ),
      ),
    );
  }
}

final _franchiseeProvider = FutureProvider.family<Franchisee, String>(
  (ref, id) async => ref.watch(franchiseeServiceProvider).getById(id),
);