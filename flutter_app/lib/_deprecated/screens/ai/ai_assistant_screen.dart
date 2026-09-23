import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/customer.dart';
import '../../providers/service_providers.dart';
import '../../theme/app_theme.dart';
import '../customers/customers_list_screen.dart';

import 'package:nuankebao/core/theme/tokens.g.dart';
class AiAssistantScreen extends ConsumerStatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  ConsumerState<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends ConsumerState<AiAssistantScreen> {
  String? _selectedCustomerId;
  bool _profileLoading = false;
  bool _followUpLoading = false;
  String? _profile;
  String? _followUp;
  bool _profileMock = false;
  bool _followUpMock = false;
  int? _daysSinceLastVisit;
  int? _avgInterval;

  Future<void> _loadProfile() async {
    if (_selectedCustomerId == null) return;
    setState(() => _profileLoading = true);
    try {
      final ai = ref.read(aiServiceProvider);
      final result = await ai.customerProfile(_selectedCustomerId!);
      setState(() {
        _profile = result.summary;
        _profileMock = result.mock;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _profileLoading = false);
    }
  }

  Future<void> _loadFollowUp() async {
    if (_selectedCustomerId == null) return;
    setState(() => _followUpLoading = true);
    try {
      final ai = ref.read(aiServiceProvider);
      final result = await ai.suggestFollowUp(_selectedCustomerId!);
      setState(() {
        _followUp = result.suggestion;
        _followUpMock = result.mock;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _followUpLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncCustomers = ref.watch(customersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AI 助手')),
      body: asyncCustomers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (customers) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpace.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择客户', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpace.s8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: customers.take(20).map((c) {
                    final selected = _selectedCustomerId == c.id;
                    return ChoiceChip(
                      label: Text(c.name),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        _selectedCustomerId = v ? c.id : null;
                        _profile = null;
                        _followUp = null;
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpace.s24),

                if (_selectedCustomerId == null)
                  const Padding(
                    padding: EdgeInsets.all(AppSpace.s24),
                    child: Text('请先选择客户', style: TextStyle(color: Colors.black54)),
                  )
                else ...[
                  // 客户画像
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.s16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.auto_awesome, color: AppTheme.primary),
                                  SizedBox(width: AppSpace.s8),
                                  Text('客户画像', style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppType.sm)),
                                ],
                              ),
                              ElevatedButton(
                                onPressed: _profileLoading ? null : _loadProfile,
                                child: Text(_profile == null ? '生成' : '重新生成'),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.s12),
                          if (_profileLoading)
                            const Center(child: CircularProgressIndicator())
                          else if (_profile != null) ...[
                            if (_profileMock)
                              const Padding(
                                padding: EdgeInsets.only(bottom: AppSpace.s8),
                                child: Chip(
                                  label: Text('Mock 模式', style: TextStyle(fontSize: AppType.tiny)),
                                  backgroundColor: AppColors.warningSurface,
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.all(AppSpace.s12),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppRadius.r8),
                              ),
                              child: Text(_profile!),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.s16),

                  // 跟进话术
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpace.s16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.chat, color: AppTheme.primary),
                                  SizedBox(width: AppSpace.s8),
                                  Text('跟进话术', style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppType.sm)),
                                ],
                              ),
                              ElevatedButton(
                                onPressed: _followUpLoading ? null : _loadFollowUp,
                                child: Text(_followUp == null ? '生成' : '重新生成'),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpace.s12),
                          if (_followUpLoading)
                            const Center(child: CircularProgressIndicator())
                          else if (_followUp != null) ...[
                            if (_followUpMock)
                              const Padding(
                                padding: EdgeInsets.only(bottom: AppSpace.s8),
                                child: Chip(
                                  label: Text('Mock 模式', style: TextStyle(fontSize: AppType.tiny)),
                                  backgroundColor: AppColors.warningSurface,
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.all(AppSpace.s12),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryLight.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(AppRadius.r8),
                              ),
                              child: Text(_followUp!),
                            ),
                            const SizedBox(height: AppSpace.s8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: _followUp!));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('已复制到剪贴板')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy, size: AppSpace.s16),
                              label: const Text('复制话术'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
