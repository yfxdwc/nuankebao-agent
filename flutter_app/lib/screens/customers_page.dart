// ============================================
// 暖客宝 客户页 (Plan F2 极简版)
// 单文件 3 widget: 列表 + 详情 + 表单
// 中老年易用: 字号 18pt+ / 按钮 64pt+ / FAB 80pt / 行高 80pt
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/models/customer.dart';
import '../core/models/wellness_record.dart';
import '../core/providers/service_providers.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/big_button.dart';
import '../core/widgets/big_fab.dart';
import '../core/widgets/customer_graph_view.dart';
import '../core/widgets/customer_row.dart';
import '../core/widgets/empty_state.dart';
import '../core/widgets/franchise_chip.dart';
import 'add_record_sheet.dart';

// 复用 search query 类型
class _CustomerQuery {
  final String? search;
  const _CustomerQuery({this.search});

  @override
  bool operator ==(Object other) =>
      other is _CustomerQuery && other.search == search;

  @override
  int get hashCode => search?.hashCode ?? 0;
}

/// 客户页视图模式: 列表 / 图谱
enum _CustomerViewMode { list, graph }

// ============================================
// CustomersListPage (主页: 客户列表 / 图谱)
// ============================================

enum _CustomerFilter { all, franchisee, normal, pending }

class CustomersListPage extends ConsumerStatefulWidget {
  const CustomersListPage({super.key});

  @override
  ConsumerState<CustomersListPage> createState() => _CustomersListPageState();
}

class _CustomersListPageState extends ConsumerState<CustomersListPage> {
  final _searchController = TextEditingController();
  String _search = '';
  _CustomerFilter _filter = _CustomerFilter.all;
  _CustomerViewMode _viewMode = _CustomerViewMode.list;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asyncCustomers = ref.watch(customersProvider(_search.isEmpty ? null : _search));
    final asyncGraph = ref.watch(myCustomerGraphProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('客户'),
        toolbarHeight: 64,
        actions: [
          // 列表/图谱 切换 (Material 3 SegmentedButton)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SegmentedButton<_CustomerViewMode>(
              segments: const [
                ButtonSegment(
                  value: _CustomerViewMode.list,
                  icon: Icon(Icons.view_list, size: 20),
                  label: Text('列表', style: TextStyle(fontSize: 14)),
                ),
                ButtonSegment(
                  value: _CustomerViewMode.graph,
                  icon: Icon(Icons.account_tree_outlined, size: 20),
                  label: Text('图谱', style: TextStyle(fontSize: 14)),
                ),
              ],
              selected: {_viewMode},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _viewMode = s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索框 (图谱视图下隐藏, 图谱不需要文本搜索)
          if (_viewMode == _CustomerViewMode.list) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: AppTheme.fontMd),
                decoration: const InputDecoration(
                  hintText: '搜索 姓名 或 手机号',
                  prefixIcon: Icon(Icons.search, size: 28),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            // 过滤 chip (48pt 高)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildChip(_CustomerFilter.all, '全部'),
                  const SizedBox(width: 8),
                  _buildChip(_CustomerFilter.franchisee, '🟣 加盟'),
                  const SizedBox(width: 8),
                  _buildChip(_CustomerFilter.normal, '🟢 普通'),
                  const SizedBox(width: 8),
                  _buildChip(_CustomerFilter.pending, '• 待办'),
                ],
              ),
            ),
          ],

          // 主体: 列表 / 图谱
          Expanded(
            child: _viewMode == _CustomerViewMode.list
                ? _buildListView(asyncCustomers)
                : _buildGraphView(asyncGraph),
          ),
        ],
      ),
      floatingActionButton: BigFab(
        onPressed: () => context.push('/customers/new'),
        tooltip: '添加客户',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildListView(AsyncValue<List<dynamic>> asyncCustomers) {
    return asyncCustomers.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(customersProvider)),
      data: (rawCustomers) {
        final customers = rawCustomers.cast<Customer>();
        final filtered = _applyFilter(customers);
        if (filtered.isEmpty) {
          return EmptyState(
            icon: Icons.people_outline,
            title: _search.isNotEmpty ? '没找到客户' : '还没有客户',
            hint: _search.isNotEmpty ? '换个名字试试' : '点击右下角 + 添加第一位客户',
            onAction: () => context.push('/customers/new'),
            actionLabel: '+ 添加客户',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(customersProvider),
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, i) {
              final c = filtered[i];
              return CustomerRow(
                customer: c,
                isFranchisee: false,
                pendingCount: 0,
                onTap: () => context.push('/customers/${c.id}'),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildGraphView(AsyncValue<CustomerGraph> asyncGraph) {
    return asyncGraph.when(
      loading: () => const LoadingState(),
      error: (e, _) => ErrorState(
        error: e,
        onRetry: () => ref.invalidate(myCustomerGraphProvider),
      ),
      data: (graph) {
        if (graph.nodes.isEmpty) {
          return EmptyState(
            icon: Icons.account_tree_outlined,
            title: '还没有客户, 无法生成图谱',
            hint: '添加客户后, 在编辑客户时设置「推荐人」即可生成推荐关系图',
            onAction: () => context.push('/customers/new'),
            actionLabel: '+ 添加客户',
          );
        }
        return Column(
          children: [
            // 顶部小提示条 (长按节点高亮, 双指缩放)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.primaryLight.withOpacity(0.3),
              child: Row(
                children: [
                  const Icon(Icons.touch_app_outlined, size: 20, color: AppTheme.primaryDark),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '长按节点高亮推荐链 · 点击节点进详情 · 双指缩放',
                      style: TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.primaryDark),
                    ),
                  ),
                  Text(
                    '${graph.count} 位客户',
                    style: const TextStyle(
                      fontSize: AppTheme.fontSm,
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // 图谱本体
            Expanded(
              child: Container(
                color: AppTheme.bgWarm,
                child: CustomerGraphView(graph: graph),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildChip(_CustomerFilter f, String label) {
    final selected = _filter == f;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: AppTheme.fontSm,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _filter = f),
      selectedColor: AppTheme.primary,
      backgroundColor: Colors.white,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.textPrimary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    );
  }

  List<Customer> _applyFilter(List<Customer> all) {
    // TODO: 真实过滤需后端配合 isFranchisee / pendingCount
    return all;
  }
}

// ============================================
// CustomerDetailPage (详情 + 时间线)
// ============================================

class CustomerDetailPage extends ConsumerWidget {
  final String customerId;
  const CustomerDetailPage({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCustomer = ref.watch(customerDetailProvider(customerId));
    final asyncRecords = ref.watch(customerWellnessRecordsProvider(customerId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('客户详情'),
        toolbarHeight: 64,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, size: 28),
            tooltip: '编辑',
            onPressed: () => context.push('/customers/$customerId/edit'),
          ),
        ],
      ),
      body: asyncCustomer.when(
        loading: () => const LoadingState(),
        error: (e, _) => ErrorState(error: e),
        data: (customer) => _buildBody(context, ref, customer, asyncRecords),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    Customer customer,
    AsyncValue<List<dynamic>> asyncRecords,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      children: [
        // 大头像 + 基本信息卡
        _buildHeader(customer),
        const SizedBox(height: 16),

        // 主操作按钮: + 添加记录 (大按钮 64pt)
        BigButton(
          label: '+ 添加记录',
          icon: Icons.add_circle_outline,
          onPressed: () => showAddRecordSheet(context, customerId: customerId),
        ),
        const SizedBox(height: 16),

        // 健康标签
        if (customer.healthTags.isNotEmpty) _buildHealthTags(customer),
        if (customer.healthTags.isNotEmpty) const SizedBox(height: 16),

        // 时间线: 全部记录 (养生 + 后续会加联系 + 跟进)
        _buildSectionTitle('全部记录'),
        asyncRecords.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: LoadingState(),
          ),
          error: (e, _) => Text('加载失败: $e'),
          data: (records) {
            if (records.isEmpty) {
              return _buildEmptyHint('还没有记录', '点击上方"添加记录"开始');
            }
            return Column(
              children: records.map((r) => _buildRecordTile(context, r)).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeader(Customer c) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            CircleAvatar(
              radius: AppTheme.avatarLg / 2,
              backgroundColor: AppTheme.primaryLight,
              child: Text(
                c.name.isNotEmpty ? c.name[0] : '?',
                style: const TextStyle(
                  fontSize: 36,
                  color: AppTheme.primaryDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              c.name,
              style: const TextStyle(
                fontSize: AppTheme.fontXl,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _maskPhone(c.phone),
              style: const TextStyle(
                fontSize: AppTheme.fontMd,
                color: AppTheme.textSecondary,
              ),
            ),
            if (c.gender != null || c.birthYear != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (c.gender != null)
                    Chip(label: Text(c.gender == 'F' ? '女' : c.gender == 'M' ? '男' : '未知')),
                  if (c.birthYear != null)
                    Chip(label: Text('${c.birthYear}年')),
                ],
              ),
            ],
            if (c.diseaseHistory != null && c.diseaseHistory!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '既往病史: ${c.diseaseHistory}',
                  style: const TextStyle(
                    fontSize: AppTheme.fontSm,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHealthTags(Customer c) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '健康标签',
              style: TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: c.healthTags.map((t) => HealthTagChip(label: t)).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: AppTheme.fontMd,
          fontWeight: FontWeight.w600,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildEmptyHint(String title, String hint) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.history, size: 56, color: AppTheme.textSecondary),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: 4),
            Text(hint, style: const TextStyle(fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordTile(BuildContext context, dynamic r) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.2),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.favorite, color: AppTheme.accent, size: 28),
        ),
        title: Text(
          '养生记录',
          style: const TextStyle(
            fontSize: AppTheme.fontMd,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${dateFmt.format(DateTime.parse(r.serviceDate))}${r.customerFeedback != null ? ' · ${r.customerFeedback}' : ''}',
            style: const TextStyle(fontSize: AppTheme.fontSm),
          ),
        ),
        trailing: const Icon(Icons.chevron_right, size: 28),
        onTap: () => context.push('/wellness-records/${r.id}'),
      ),
    );
  }

  String _maskPhone(String phone) {
    if (phone.length == 11) {
      return '${phone.substring(0, 3)}****${phone.substring(7)}';
    }
    return phone;
  }
}

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
  final _notesController = TextEditingController();
  String? _gender = 'F';
  DateTime? _birthYear;
  final List<String> _healthTags = [];
  /// 客户推荐人 (客户页图谱关系边). null = 无推荐人
  String? _referrerId;
  String? _referrerName;

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
      _gender = c.gender;
      _birthYear = c.birthYear != null ? DateTime(c.birthYear!, 1, 1) : null;
      _healthTags.clear();
      _healthTags.addAll(c.healthTags);
      _referrerId = c.referrerId;
      _referrerName = null; // 按需点击选择器时懒加载名字
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final data = <String, dynamic>{
        'name': _nameController.text,
        'phone': _phoneController.text,
        if (_gender != null) 'gender': _gender,
        if (_birthYear != null) 'birthYear': _birthYear!.year,
        'healthTags': _healthTags,
        if (_notesController.text.isNotEmpty) 'notes': _notesController.text,
        // referrerId: 显式发 null 清空, undefined 不变
        'referrerId': _referrerId,
      };
      if (widget.customerId != null) {
        await ref.read(customerServiceProvider).update(widget.customerId!, data);
      } else {
        await ref.read(customerServiceProvider).create(data);
      }
      if (!mounted) return;
      ref.invalidate(customersProvider);
      ref.invalidate(myCustomerGraphProvider);
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
        toolbarHeight: 64,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              decoration: const InputDecoration(labelText: '姓名 *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
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
            // 性别 (大按钮组)
            const Text('性别', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: 8),
            Row(
              children: [
                _genderButton('女', 'F'),
                const SizedBox(width: 8),
                _genderButton('男', 'M'),
                const SizedBox(width: 8),
                _genderButton('未知', 'U'),
              ],
            ),
            const SizedBox(height: 16),
            // 出生年 (大按钮)
            OutlinedButton.icon(
              onPressed: () async {
                final year = await showDialog<int>(
                  context: context,
                  builder: (_) => _YearPickerDialog(initial: _birthYear?.year),
                );
                if (year != null) setState(() => _birthYear = DateTime(year, 1, 1));
              },
              icon: const Icon(Icons.cake_outlined, size: 24),
              label: Text(
                _birthYear == null ? '选择出生年份' : '${_birthYear!.year}年',
                style: const TextStyle(fontSize: AppTheme.fontMd),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
              ),
            ),
            const SizedBox(height: 16),
            // 健康标签
            const Text('健康标签', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _healthTags.map((t) => InputChip(
                label: Text(t),
                onDeleted: () => setState(() => _healthTags.remove(t)),
              )).toList(),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final tag = await showDialog<String>(
                    context: context,
                    builder: (_) => const _TagInputDialog(),
                  );
                  if (tag != null && !_healthTags.contains(tag)) {
                    setState(() => _healthTags.add(tag));
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('添加标签', style: TextStyle(fontSize: AppTheme.fontMd)),
              ),
            ),
            const SizedBox(height: 16),
            // 推荐人 (客户页图谱关系边)
            const Text('推荐人', style: TextStyle(fontSize: AppTheme.fontMd)),
            const SizedBox(height: 4),
            const Text(
              '谁介绍这位客户来的? 设置后可以在客户页「图谱」看到推荐链',
              style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickReferrer,
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 24),
                    label: Text(
                      _referrerName ?? (_referrerId == null ? '选择推荐人 (可选)' : '已选 #$_referrerId'),
                      style: const TextStyle(fontSize: AppTheme.fontMd),
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 56),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
                if (_referrerId != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 24),
                    tooltip: '清除推荐人',
                    onPressed: () => setState(() {
                      _referrerId = null;
                      _referrerName = null;
                    }),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              style: const TextStyle(fontSize: AppTheme.fontMd),
              maxLines: 3,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            const SizedBox(height: 32),
            BigButton(
              label: widget.customerId == null ? '保存' : '保存修改',
              icon: Icons.check,
              onPressed: _submit,
              loading: _loading,
            ),
          ],
        ),
      ),
    );
  }

  Widget _genderButton(String label, String value) {
    final selected = _gender == value;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => setState(() => _gender = value),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 56),
          backgroundColor: selected ? AppTheme.primary : Colors.white,
          foregroundColor: selected ? Colors.white : AppTheme.primary,
          side: BorderSide(
            color: selected ? AppTheme.primary : AppTheme.primary.withOpacity(0.4),
            width: 2,
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: AppTheme.fontMd)),
      ),
    );
  }

  Future<void> _pickReferrer() async {
    final result = await showDialog<_ReferrerResult>(
      context: context,
      builder: (_) => _ReferrerPickerDialog(excludeId: widget.customerId),
    );
    if (result != null && mounted) {
      setState(() {
        _referrerId = result.id;
        _referrerName = result.name;
      });
    }
  }
}

/// 推荐人选择结果
class _ReferrerResult {
  final String id;
  final String name;
  const _ReferrerResult(this.id, this.name);
}

// ============================================
// 子对话框 (年份选择 / 标签输入)
// ============================================

class _YearPickerDialog extends StatefulWidget {
  final int? initial;
  const _YearPickerDialog({this.initial});

  @override
  State<_YearPickerDialog> createState() => _YearPickerDialogState();
}

class _YearPickerDialogState extends State<_YearPickerDialog> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial ?? 1980;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择出生年份'),
      content: SizedBox(
        height: 200,
        child: ListView.builder(
          itemCount: 100,
          itemBuilder: (context, i) {
            final y = 1940 + i;
            return ListTile(
              title: Text('$y年', style: const TextStyle(fontSize: AppTheme.fontMd)),
              selected: y == _year,
              onTap: () {
                setState(() => _year = y);
                Navigator.of(context).pop(y);
              },
            );
          },
        ),
      ),
    );
  }
}

class _TagInputDialog extends StatefulWidget {
  const _TagInputDialog();

  @override
  State<_TagInputDialog> createState() => _TagInputDialogState();
}

class _TagInputDialogState extends State<_TagInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加健康标签'),
      content: TextField(
        controller: _controller,
        style: const TextStyle(fontSize: AppTheme.fontMd),
        autofocus: true,
        decoration: const InputDecoration(hintText: '如: 肩颈 / 睡眠差 / 体寒'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
        ElevatedButton(
          onPressed: () {
            final v = _controller.text.trim();
            if (v.isNotEmpty) Navigator.of(context).pop(v);
          },
          child: const Text('添加', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      ],
    );
  }
}

// ============================================
// 推荐人选择对话框 (客户页图谱关系录入)
// ============================================

class _ReferrerPickerDialog extends ConsumerStatefulWidget {
  /// 排除的 customer id (不能推荐自己)
  final String? excludeId;
  const _ReferrerPickerDialog({this.excludeId});

  @override
  ConsumerState<_ReferrerPickerDialog> createState() => _ReferrerPickerDialogState();
}

class _ReferrerPickerDialogState extends ConsumerState<_ReferrerPickerDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final asyncCustomers = ref.watch(customersProvider(_search.isEmpty ? null : _search));

    return AlertDialog(
      title: const Text('选择推荐人', style: TextStyle(fontSize: AppTheme.fontLg)),
      contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 480,
        child: Column(
          children: [
            // 搜索框
            TextField(
              style: const TextStyle(fontSize: AppTheme.fontMd),
              autofocus: false,
              decoration: const InputDecoration(
                hintText: '搜索 姓名 或 手机号',
                prefixIcon: Icon(Icons.search, size: 24),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),
            // 客户列表
            Expanded(
              child: asyncCustomers.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败: $e')),
                data: (rawList) {
                  final list = rawList.cast<Customer>().where((c) => c.id != widget.excludeId).toList();
                  if (list.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('没有可选客户\n请先添加客户', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final c = list[i];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.primaryLight,
                          radius: 24,
                          child: Text(
                            c.name.isNotEmpty ? c.name[0] : '?',
                            style: const TextStyle(fontSize: 18, color: AppTheme.primaryDark, fontWeight: FontWeight.w600),
                          ),
                        ),
                        title: Text(c.name, style: const TextStyle(fontSize: AppTheme.fontMd, fontWeight: FontWeight.w600)),
                        subtitle: Text(c.phone, style: const TextStyle(fontSize: AppTheme.fontXs)),
                        onTap: () => Navigator.of(context).pop(_ReferrerResult(c.id, c.name)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('取消', style: TextStyle(fontSize: AppTheme.fontMd)),
        ),
      ],
    );
  }
}