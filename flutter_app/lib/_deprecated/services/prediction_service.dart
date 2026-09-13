import 'package:dio/dio.dart';

/// 复购预测 (不调 LLM, 纯 SQL 计算)
class PredictionService {
  final Dio _dio;
  PredictionService(this._dio);

  Future<RepurchasePrediction> repurchase(String customerId) async {
    final res = await _dio.get('/ai/repurchase-prediction/$customerId');
    return RepurchasePrediction.fromJson(res.data as Map<String, dynamic>);
  }

  Future<EffectAnalysis> effectAnalysis(String customerId) async {
    final res = await _dio.get('/ai/effect-analysis/$customerId');
    return EffectAnalysis.fromJson(res.data as Map<String, dynamic>);
  }
}

class RepurchasePrediction {
  final String customerId;
  final String customerName;
  final String? lastVisit;
  final int? daysSinceLastVisit;
  final int? avgIntervalDays;
  final String? predictedNextVisit;
  final int? daysUntilPredicted;
  final String confidence; // high / medium / low
  final String reason;

  RepurchasePrediction({
    required this.customerId,
    required this.customerName,
    this.lastVisit,
    this.daysSinceLastVisit,
    this.avgIntervalDays,
    this.predictedNextVisit,
    this.daysUntilPredicted,
    required this.confidence,
    required this.reason,
  });

  factory RepurchasePrediction.fromJson(Map<String, dynamic> json) =>
      RepurchasePrediction(
        customerId: json['customerId'] as String,
        customerName: json['customerName'] as String,
        lastVisit: json['lastVisit'] as String?,
        daysSinceLastVisit: json['daysSinceLastVisit'] as int?,
        avgIntervalDays: json['avgIntervalDays'] as int?,
        predictedNextVisit: json['predictedNextVisit'] as String?,
        daysUntilPredicted: json['daysUntilPredicted'] as int?,
        confidence: json['confidence'] as String,
        reason: json['reason'] as String,
      );
}

class EffectAnalysis {
  final String customerId;
  final String customerName;
  final int totalVisits;
  final String? dateFrom;
  final String? dateTo;
  final String aiSummary;
  final String trend; // improving / stable / worsening / unknown
  final bool aiMock;

  EffectAnalysis({
    required this.customerId,
    required this.customerName,
    required this.totalVisits,
    this.dateFrom,
    this.dateTo,
    required this.aiSummary,
    required this.trend,
    required this.aiMock,
  });

  factory EffectAnalysis.fromJson(Map<String, dynamic> json) => EffectAnalysis(
        customerId: json['customerId'] as String,
        customerName: json['customerName'] as String,
        totalVisits: json['totalVisits'] as int,
        dateFrom: (json['dateRange'] as Map?)?['from'] as String?,
        dateTo: (json['dateRange'] as Map?)?['to'] as String?,
        aiSummary: json['aiSummary'] as String,
        trend: json['trend'] as String,
        aiMock: json['aiMock'] as bool,
      );
}