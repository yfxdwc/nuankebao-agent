// ============================================
// 客户详情页 — AI 智能卡片 (主人 2026-09-18 拍: 详情页要"养生记录 + AI 画像 +
// AI 跟进建议 + 复购预测 + 效果分析 或更多")
//
// 设计原则:
//   1. **省钱**: 复购预测是纯 DB 计算 → 自动加载; 其余 3 个烧 MiniMax 额度 → 点了才生成
//      (按钮文案写清「点一下生成」, 生成后缓存, 可重新生成)
//   2. **中老年友好**: 字号 16+ / 大按钮 / 结果用大白话 + 一眼能看到的关键数字
//   3. **失败可恢复**: 生成失败给明确文案 + 重试按钮 (不静默吞错)
// ============================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../core/models/ai_insight.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/telemetry/usage_events.dart' show AiCard;
import '../../../core/telemetry/usage_providers.dart';
import '../../../core/theme/app_theme.dart';
import 'customer_activity_cards.dart' show showAddFollowUpSheet;

import '../../../core/theme/tokens.g.dart';
// ============================================
// 用量埋点 helper (主人 2026-09-22: 用真实数据回答「AI 卡片到底有没有人点」)
// ============================================

void _trackAiClick(WidgetRef ref, String card, {bool regenerate = false}) {
  ref.read(usageServiceProvider).track(
        regenerate ? 'ai_regenerate' : 'ai_generate_click',
        props: {'card': card},
      );
}

void _trackAiResult(
  WidgetRef ref,
  String card, {
  required bool ok,
  required int ms,
}) {
  ref.read(usageServiceProvider).track(
        'ai_generate_result',
        props: {'card': card},
        success: ok,
        durationMs: ms,
        errorCode: ok ? null : 'generate_failed',
      );
}

// ============================================
// 复购预测 (自动加载, 不烧 AI)
// ============================================

class RepurchaseCard extends ConsumerStatefulWidget {
  final String customerId;
  const RepurchaseCard({super.key, required this.customerId});

  @override
  ConsumerState<RepurchaseCard> createState() => _RepurchaseCardState();
}

class _RepurchaseCardState extends ConsumerState<RepurchaseCard> {
  RepurchasePrediction? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool manual = false}) async {
    if (manual) _trackAiClick(ref, AiCard.repurchase);
    final sw = Stopwatch()..start();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ref
          .read(aiServiceProvider)
          .repurchasePrediction(widget.customerId);
      if (mounted) setState(() => _data = d);
      if (manual) {
        _trackAiResult(ref, AiCard.repurchase,
            ok: true, ms: sw.elapsedMilliseconds);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      if (manual) {
        _trackAiResult(ref, AiCard.repurchase,
            ok: false, ms: sw.elapsedMilliseconds);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AiCardShell(
      icon: Icons.autorenew,
      iconColor: AppTheme.primary,
      title: '复购预测',
      subtitle: '根据历史到店间隔算下次该什么时候约',
      trailing: IconButton(
        icon: const Icon(Icons.refresh, size: 22),
        tooltip: '重新计算',
        onPressed: _loading ? null : () => _load(manual: true),
      ),
      child: _loading
          ? const _AiLoading('正在算复购周期...')
          : _error != null
              ? _AiError(message: _error!, onRetry: () => _load(manual: true))
              : _data == null
                  ? const _AiHint('暂无数据')
                  : _buildResult(_data!),
    );
  }

  Widget _buildResult(RepurchasePrediction d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric('距上次到店',
                d.daysSinceLastVisit == null ? '—' : '${d.daysSinceLastVisit} 天'),
            _metric('平均复购周期',
                d.avgIntervalDays == null ? '—' : '${d.avgIntervalDays} 天'),
            _metric('预计下次', d.predictedNextVisit ?? '—',
                highlight: d.isDue),
          ],
        ),
        const SizedBox(height: AppSpace.s10),
        Row(
          children: [
            _confidenceChip(d.confidence),
            const SizedBox(width: AppSpace.s8),
            if (d.daysUntilPredicted != null)
              Text(
                d.daysUntilPredicted! < 0
                    ? '已过 ${-d.daysUntilPredicted!} 天'
                    : '还有 ${d.daysUntilPredicted} 天',
                style: TextStyle(
                  fontSize: AppTheme.fontSm,
                  fontWeight: FontWeight.w600,
                  color: d.isDue ? AppTheme.danger : AppTheme.textSecondary,
                ),
              ),
          ],
        ),
        if (d.reason.isNotEmpty) ...[
          const SizedBox(height: AppSpace.s10),
          _AiBody(text: d.reason),
        ],
        if (d.isDue) ...[
          const SizedBox(height: AppSpace.s12),
          BigActionButton(
            icon: Icons.add_task,
            label: '建一条跟进任务',
            onTap: () => showAddFollowUpSheet(context, ref,
                customerId: widget.customerId),
          ),
        ],
      ],
    );
  }

  Widget _metric(String label, String value, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s8),
      decoration: BoxDecoration(
        color: highlight
            ? AppTheme.danger.withOpacity(0.08)
            : AppTheme.primaryLight.withOpacity(0.35),
        borderRadius: BorderRadius.circular(AppRadius.r10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: AppTheme.fontXs, color: AppTheme.textSecondary)),
          const SizedBox(height: AppSpace.s2),
          Text(value,
              style: TextStyle(
                fontSize: AppTheme.fontMd,
                fontWeight: FontWeight.w700,
                color: highlight ? AppTheme.danger : AppTheme.primaryDark,
              )),
        ],
      ),
    );
  }

  Widget _confidenceChip(String c) {
    final (label, color) = switch (c) {
      'high' => ('数据充分', AppTheme.primary),
      'medium' => ('数据一般', AppTheme.accent),
      _ => ('数据较少', AppTheme.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.r8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: AppTheme.fontXs, color: color, fontWeight: FontWeight.w600)),
    );
  }
}

// ============================================
// AI 客户画像 (点一下生成)
// ============================================

class AiProfileCard extends ConsumerStatefulWidget {
  final String customerId;
  const AiProfileCard({super.key, required this.customerId});

  @override
  ConsumerState<AiProfileCard> createState() => _AiProfileCardState();
}

class _AiProfileCardState extends ConsumerState<AiProfileCard> {
  CustomerProfileInsight? _data;
  bool _loading = false;
  String? _error;

  Future<void> _generate({bool regenerate = false}) async {
    _trackAiClick(ref, AiCard.profile, regenerate: regenerate);
    final sw = Stopwatch()..start();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ref.read(aiServiceProvider).profileInsight(widget.customerId);
      if (mounted) setState(() => _data = d);
      _trackAiResult(ref, AiCard.profile,
          ok: true, ms: sw.elapsedMilliseconds);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      _trackAiResult(ref, AiCard.profile,
          ok: false, ms: sw.elapsedMilliseconds);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AiCardShell(
      icon: Icons.auto_awesome,
      iconColor: AppTheme.franchisee,
      title: 'AI 客户画像',
      subtitle: '把健康标签 + 历史记录读一遍, 总结这位客户是谁',
      trailing: _data == null
          ? null
          : IconButton(
              icon: const Icon(Icons.refresh, size: 22),
              tooltip: '重新生成',
              onPressed: _loading ? null : () => _generate(regenerate: true),
            ),
      child: _loading
          ? const _AiLoading('AI 正在总结客户画像...')
          : _error != null
              ? _AiError(message: _error!, onRetry: () => _generate())
              : _data == null
                  ? _GenerateButton(
                      label: '生成客户画像',
                      icon: Icons.auto_awesome,
                      onTap: () => _generate(),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AiBody(text: _data!.aiSummary),
                        if (_data!.recentSummaries.isNotEmpty) ...[
                          const SizedBox(height: AppSpace.s12),
                          const Text('参考的近期记录',
                              style: TextStyle(
                                  fontSize: AppTheme.fontXs,
                                  color: AppTheme.textSecondary)),
                          const SizedBox(height: AppSpace.s4),
                          ..._data!.recentSummaries.take(5).map((s) => Padding(
                                padding: const EdgeInsets.only(bottom: AppSpace.s2),
                                child: Text('· $s',
                                    style: const TextStyle(
                                        fontSize: AppTheme.fontXs,
                                        color: AppTheme.textSecondary)),
                              )),
                        ],
                        if (_data!.aiMock) ...[
                          const SizedBox(height: AppSpace.s8),
                          const _AiMockBadge(),
                        ],
                      ],
                    ),
    );
  }
}

// ============================================
// AI 跟进建议 (点一下生成话术)
// ============================================

class AiFollowUpCard extends ConsumerStatefulWidget {
  final String customerId;
  const AiFollowUpCard({super.key, required this.customerId});

  @override
  ConsumerState<AiFollowUpCard> createState() => _AiFollowUpCardState();
}

class _AiFollowUpCardState extends ConsumerState<AiFollowUpCard> {
  FollowUpSuggestion? _data;
  bool _loading = false;
  String? _error;
  String? _reason;

  static const _reasonOptions = ['好久没来了', '想约她到店', '生日/节日问候', '该复购了'];

  Future<void> _generate([String? reason, bool regenerate = false]) async {
    _trackAiClick(ref, AiCard.followUp, regenerate: regenerate);
    final sw = Stopwatch()..start();
    setState(() {
      _loading = true;
      _error = null;
      if (reason != null) _reason = reason;
    });
    try {
      final d = await ref
          .read(aiServiceProvider)
          .followUpInsight(widget.customerId, reason: _reason);
      if (mounted) setState(() => _data = d);
      _trackAiResult(ref, AiCard.followUp,
          ok: true, ms: sw.elapsedMilliseconds);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      _trackAiResult(ref, AiCard.followUp,
          ok: false, ms: sw.elapsedMilliseconds);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AiCardShell(
      icon: Icons.chat_bubble_outline,
      iconColor: AppTheme.accent,
      title: 'AI 跟进建议',
      subtitle: '按她的情况写一段可以直接发的开口话术',
      trailing: _data == null
          ? null
          : IconButton(
              icon: const Icon(Icons.refresh, size: 22),
              tooltip: '重新生成',
              onPressed: _loading ? null : () => _generate(_reason, true),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 跟进原因 (可选): 选了话术更贴场景
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _reasonOptions
                .map((r) => ChoiceChip(
                      label: Text(r, style: const TextStyle(fontSize: AppTheme.fontSm)),
                      selected: _reason == r,
                      onSelected: (v) =>
                          setState(() => _reason = v ? r : null),
                    ))
                .toList(),
          ),
          const SizedBox(height: AppSpace.s12),
          if (_loading)
            const _AiLoading('AI 正在写话术...')
          else if (_error != null)
            _AiError(message: _error!, onRetry: () => _generate(_reason))
          else if (_data == null)
            _GenerateButton(
              label: '生成跟进话术',
              icon: Icons.chat,
              onTap: () => _generate(_reason),
            )
          else ...[
            _AiBody(text: _data!.suggestion),
            const SizedBox(height: AppSpace.s10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_data!.daysSinceLastVisit != null)
                  _pill('距上次 ${_data!.daysSinceLastVisit} 天'),
                if (_data!.avgInterval != null)
                  _pill('平均 ${_data!.avgInterval} 天一次'),
                if (_data!.reason.isNotEmpty) _pill(_data!.reason),
              ],
            ),
            const SizedBox(height: AppSpace.s12),
            Row(
              children: [
                Expanded(
                  child: BigActionButton(
                    icon: Icons.copy_all,
                    label: '复制话术',
                    compact: true,
                    onTap: () {
                      // 复制到剪贴板 (web + native 都支持)
                      Clipboard.setData(ClipboardData(text: _data!.suggestion));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('话术已复制')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: BigActionButton(
                    icon: Icons.add_task,
                    label: '建跟进任务',
                    compact: true,
                    onTap: () => showAddFollowUpSheet(context, ref,
                        customerId: widget.customerId,
                        aiSuggestion: _data?.suggestion),
                  ),
                ),
              ],
            ),
            if (_data!.aiMock) ...[
              const SizedBox(height: AppSpace.s8),
              const _AiMockBadge(),
            ],
          ],
        ],
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s10, vertical: AppSpace.s4),
        decoration: BoxDecoration(
          color: AppTheme.bgWarm,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.r12),
        ),
        child: Text(text,
            style: const TextStyle(
                fontSize: AppTheme.fontXs, color: AppTheme.textSecondary)),
      );
}

// ============================================
// AI 效果分析 (点一下生成)
// ============================================

class EffectAnalysisCard extends ConsumerStatefulWidget {
  final String customerId;
  const EffectAnalysisCard({super.key, required this.customerId});

  @override
  ConsumerState<EffectAnalysisCard> createState() => _EffectAnalysisCardState();
}

class _EffectAnalysisCardState extends ConsumerState<EffectAnalysisCard> {
  EffectAnalysis? _data;
  bool _loading = false;
  String? _error;

  Future<void> _generate({bool regenerate = false}) async {
    _trackAiClick(ref, AiCard.effect, regenerate: regenerate);
    final sw = Stopwatch()..start();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await ref.read(aiServiceProvider).effectAnalysis(widget.customerId);
      if (mounted) setState(() => _data = d);
      _trackAiResult(ref, AiCard.effect,
          ok: true, ms: sw.elapsedMilliseconds);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      _trackAiResult(ref, AiCard.effect,
          ok: false, ms: sw.elapsedMilliseconds);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AiCardShell(
      icon: Icons.timeline,
      iconColor: AppTheme.franchiseeA,
      title: '效果分析',
      subtitle: '多疗程前后变化趋势 + AI 总结',
      trailing: _data == null
          ? null
          : IconButton(
              icon: const Icon(Icons.refresh, size: 22),
              tooltip: '重新分析',
              onPressed: _loading ? null : () => _generate(regenerate: true),
            ),
      child: _loading
          ? const _AiLoading('AI 正在分析疗程效果...')
          : _error != null
              ? _AiError(message: _error!, onRetry: () => _generate())
              : _data == null
                  ? _GenerateButton(
                      label: '分析效果',
                      icon: Icons.timeline,
                      onTap: () => _generate(),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _metric('记录次数', '${_data!.totalVisits} 次'),
                            _metric('趋势', _data!.trendLabel),
                          ],
                        ),
                        if (_data!.from != null && _data!.to != null) ...[
                          const SizedBox(height: AppSpace.s8),
                          Text('统计区间: ${_data!.from} ~ ${_data!.to}',
                              style: const TextStyle(
                                  fontSize: AppTheme.fontXs,
                                  color: AppTheme.textSecondary)),
                        ],
                        if (_data!.aiSummary.isNotEmpty) ...[
                          const SizedBox(height: AppSpace.s10),
                          _AiBody(text: _data!.aiSummary),
                        ],
                        if (_data!.aiMock) ...[
                          const SizedBox(height: AppSpace.s8),
                          const _AiMockBadge(),
                        ],
                      ],
                    ),
    );
  }

  Widget _metric(String label, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.s12, vertical: AppSpace.s8),
        decoration: BoxDecoration(
          color: AppTheme.primaryLight.withOpacity(0.35),
          borderRadius: BorderRadius.circular(AppRadius.r10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: AppTheme.fontXs, color: AppTheme.textSecondary)),
            const SizedBox(height: AppSpace.s2),
            Text(value,
                style: const TextStyle(
                    fontSize: AppTheme.fontMd,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryDark)),
          ],
        ),
      );
}

// ============================================
// 共用小组件 (卡片外壳 / 加载 / 错误 / 生成按钮 / 正文 / mock 标)
// ============================================

class _AiCardShell extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _AiCardShell({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpace.s12),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 26, color: iconColor),
                const SizedBox(width: AppSpace.s8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: AppTheme.fontMd,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: AppSpace.s4),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: AppTheme.fontXs, color: AppTheme.textSecondary)),
            const SizedBox(height: AppSpace.s12),
            child,
          ],
        ),
      ),
    );
  }
}

class _AiLoading extends StatelessWidget {
  final String label;
  const _AiLoading(this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          width: AppSpace.s20,
          height: AppSpace.s20,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        const SizedBox(width: AppSpace.s12),
        Text(label,
            style: const TextStyle(
                fontSize: AppTheme.fontSm, color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _AiError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _AiError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('生成失败: $message',
            style: const TextStyle(
                fontSize: AppTheme.fontSm, color: AppTheme.danger)),
        const SizedBox(height: AppSpace.s8),
        BigActionButton(
          icon: Icons.refresh,
          label: '重试',
          compact: true,
          onTap: onRetry,
        ),
      ],
    );
  }
}

class _AiHint extends StatelessWidget {
  final String text;
  const _AiHint(this.text);

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: AppTheme.fontSm, color: AppTheme.textSecondary));
}

class _AiBody extends StatelessWidget {
  final String text;
  const _AiBody({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.s14),
      decoration: BoxDecoration(
        color: AppTheme.bgWarm,
        borderRadius: BorderRadius.circular(AppRadius.r12),
        border: Border.all(color: AppColors.divider),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(
          fontSize: AppTheme.fontSm,
          height: 1.6,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}

class _AiMockBadge extends StatelessWidget {
  const _AiMockBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.s8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.r6),
      ),
      child: const Text('示例数据 (AI 未接入时)',
          style: TextStyle(fontSize: AppTheme.fontXs, color: AppTheme.textSecondary)),
    );
  }
}

class _GenerateButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _GenerateButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BigActionButton(icon: icon, label: label, onTap: onTap);
  }
}

/// 详情页大按钮 (64pt 高, 中老年好点)
class BigActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  const BigActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: compact ? 48 : 56,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: compact ? 20 : 24),
        label: Text(label, style: TextStyle(fontSize: compact ? AppTheme.fontSm : AppTheme.fontMd)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.primaryDark,
          side: const BorderSide(color: AppTheme.primary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.r12)),
        ),
      ),
    );
  }
}
