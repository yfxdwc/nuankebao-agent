import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/service_providers.dart';
import '../../services/prediction_service.dart';

/// 复购预测小卡片 (在客户详情 / 跟进页面显示)
class RepurchasePredictionCard extends ConsumerStatefulWidget {
  final String customerId;
  const RepurchasePredictionCard({super.key, required this.customerId});

  @override
  ConsumerState<RepurchasePredictionCard> createState() => _RepurchasePredictionCardState();
}

class _RepurchasePredictionCardState extends ConsumerState<RepurchasePredictionCard> {
  RepurchasePrediction? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(predictionServiceProvider);
      _data = await svc.repurchase(widget.customerId);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _confidenceColor() {
    switch (_data?.confidence) {
      case 'high':
        return Colors.green;
      case 'medium':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.trending_up, color: Colors.indigo),
                    SizedBox(width: 8),
                    Text('复购预测', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ],
                ),
                if (_data != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _confidenceColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '置信度 ${_data!.confidence}',
                      style: TextStyle(fontSize: 11, color: _confidenceColor()),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (_error != null)
              Text('加载失败: $_error', style: const TextStyle(color: Colors.red, fontSize: 12))
            else if (_data == null)
              const Text('暂无数据', style: TextStyle(color: Colors.black54))
            else ...[
              if (_data!.daysSinceLastVisit != null)
                Text('距上次到店: ${_data!.daysSinceLastVisit} 天'),
              if (_data!.avgIntervalDays != null)
                Text('平均复购周期: ${_data!.avgIntervalDays} 天'),
              if (_data!.predictedNextVisit != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '预计下次: ${_data!.predictedNextVisit}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.indigo),
                  ),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_data!.reason, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_data!.daysUntilPredicted != null && _data!.daysUntilPredicted! <= 7)
                    OutlinedButton.icon(
                      onPressed: () => context.push('/follow-ups?customerId=${_data!.customerId}'),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('创建跟进'),
                    ),
                  const Spacer(),
                  IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 效果分析小卡片
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final svc = ref.read(predictionServiceProvider);
      _data = await svc.effectAnalysis(widget.customerId);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _trendIcon() {
    switch (_data?.trend) {
      case 'improving':
        return Icons.trending_up;
      case 'worsening':
        return Icons.trending_down;
      default:
        return Icons.trending_flat;
    }
  }

  Color _trendColor() {
    switch (_data?.trend) {
      case 'improving':
        return Colors.green;
      case 'worsening':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _trendLabel() {
    switch (_data?.trend) {
      case 'improving':
        return '持续改善';
      case 'worsening':
        return '需关注';
      case 'stable':
        return '稳定';
      default:
        return '数据不足';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.analytics, color: Colors.deepPurple),
                    SizedBox(width: 8),
                    Text('效果分析', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ],
                ),
                if (_data != null)
                  Row(
                    children: [
                      if (_data!.aiMock)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('Mock', style: TextStyle(fontSize: 10)),
                        ),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _trendColor().withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_trendIcon(), color: _trendColor(), size: 12),
                            const SizedBox(width: 2),
                            Text(_trendLabel(), style: TextStyle(fontSize: 10, color: _trendColor())),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            else if (_error != null)
              Text('加载失败: $_error', style: const TextStyle(color: Colors.red, fontSize: 12))
            else if (_data == null)
              const Text('暂无数据', style: TextStyle(color: Colors.black54))
            else ...[
              Text(
                '共 ${_data!.totalVisits} 次到店',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              if (_data!.dateFrom != null)
                Text(
                  '时间: ${_data!.dateFrom} ~ ${_data!.dateTo}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(_data!.aiSummary, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}