// ============================================
// 加盟商编辑页 (修复 GoException: no routes for /franchisees/:id/edit)
//
// 只允许改: 姓名 / 手机号 / 备注 / 启用状态
//   —— 后端 `UpdateFranchiseeSchema` 也只收这几个 (src/app/api/franchisees/[id]/route.ts)
//   —— 推荐人 (referrerId) / 位置 (placementSide) 建树后不可改:
//      二叉树 placement_path 是物化路径, 改了会破坏整棵树的左右结构
//      (要换位置 = 软删后重新加)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/franchisee.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/big_button.dart';
import '../../../core/widgets/empty_state.dart';
import '../lib/franchisee_detail_provider.dart';

import '../../../core/theme/tokens.g.dart';
class EditFranchiseePage extends ConsumerStatefulWidget {
  final String franchiseeId;
  const EditFranchiseePage({super.key, required this.franchiseeId});

  @override
  ConsumerState<EditFranchiseePage> createState() => _EditFranchiseePageState();
}

class _EditFranchiseePageState extends ConsumerState<EditFranchiseePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _isActive = true;
  bool _booting = true;
  bool _saving = false;
  String? _loadError;
  Franchisee? _original;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _booting = true;
      _loadError = null;
    });
    try {
      final f = await ref
          .read(franchiseeServiceProvider)
          .getById(widget.franchiseeId);
      if (!mounted) return;
      setState(() {
        _original = f;
        _nameCtrl.text = f.name;
        _phoneCtrl.text = f.phone;
        _notesCtrl.text = f.notes ?? '';
        _isActive = f.isActive;
        _booting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _booting = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(franchiseeServiceProvider).update(widget.franchiseeId, {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        // 空备注也发出去 (显式清空)
        'notes': _notesCtrl.text.trim(),
        'isActive': _isActive,
      });
      // 图谱 / 列表 / 详情都可能缓存了旧值
      ref.invalidate(myFranchiseeTreeProvider);
      ref.invalidate(franchiseesProvider);
      // 详情页的 provider (否则 pop 回去还显示旧名字)
      ref.invalidate(franchiseeDetailProvider(widget.franchiseeId));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已保存', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败: $e', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑加盟商'),
        toolbarHeight: 64,
      ),
      body: _booting
          ? const LoadingState()
          : (_loadError != null
              ? ErrorState(
                  error: _loadError!,
                  onRetry: _load,
                )
              : _buildForm()),
    );
  }

  Widget _buildForm() {
    final f = _original;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpace.s16, 16, 16, 32),
        children: [
          TextFormField(
            controller: _nameCtrl,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            decoration: const InputDecoration(labelText: '姓名 *'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
          ),
          const SizedBox(height: AppSpace.s16),
          TextFormField(
            controller: _phoneCtrl,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: '手机号 *'),
            validator: (v) {
              if (v == null || !RegExp(r'^1[3-9]\d{9}$').hasMatch(v.trim())) {
                return '请输入正确的手机号';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpace.s16),
          TextFormField(
            controller: _notesCtrl,
            style: const TextStyle(fontSize: AppTheme.fontMd),
            maxLines: 3,
            maxLength: 500,
            // app 没装 flutter_localizations → maxLength 计数器是英文; 藏掉
            decoration: const InputDecoration(
              labelText: '备注',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpace.s8),
          // 启用 / 停用
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              value: _isActive,
              onChanged: (v) => setState(() => _isActive = v),
              title: const Text('启用', style: TextStyle(fontSize: AppTheme.fontMd)),
              subtitle: Text(
                _isActive ? '正常显示 / 参与图谱' : '停用 (列表与图谱仍可见, 标记为不活跃)',
                style: const TextStyle(fontSize: AppTheme.fontXs),
              ),
            ),
          ),

          // 只读信息: 推荐人 / 位置 (建树后不可改)
          if (f != null) ...[
            const SizedBox(height: AppSpace.s16),
            Card(
              margin: EdgeInsets.zero,
              color: AppTheme.primaryLight.withOpacity(0.25),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.s16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline,
                            size: AppSize.iconSm, color: AppTheme.primaryDark),
                        const SizedBox(width: AppSpace.s6),
                        const Text(
                          '推荐人 / 位置 不可修改',
                          style: TextStyle(
                            fontSize: AppTheme.fontSm,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primaryDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.s4),
                    const Text(
                      '二叉树位置定了就固定 (换位置 = 先软删再加)',
                      style: TextStyle(
                        fontSize: AppTheme.fontXs,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const Divider(height: AppSpace.s20),
                    _roRow('层级',
                        f.placementDepth == 0 ? '顶级 (root)' : '第 ${f.placementDepth} 层'),
                    _roRow('位置',
                        f.placementSide == null ? '顶级' : (f.placementSide == 'left' ? 'A线' : 'B线')),
                    _roRow('权限路径', f.placementPath.isEmpty ? '(顶级)' : f.placementPath),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: AppSpace.s32),
          BigButton(
            label: '保存修改',
            icon: Icons.check,
            onPressed: _submit,
            loading: _saving,
          ),
        ],
      ),
    );
  }

  Widget _roRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.s4),
      child: Row(
        children: [
          SizedBox(
            width: AppSpace.s84,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: AppTheme.fontSm,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: AppTheme.fontSm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
