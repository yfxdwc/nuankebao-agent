import 'package:dio/dio.dart';
import '../models/dictionaries.dart';
import '../models/follow_up.dart';
import '../models/dashboard.dart';

class DictionaryService {
  final Dio _dio;
  DictionaryService(this._dio);

  Future<Dictionaries> all() async {
    final res = await _dio.get('/dictionaries');
    return Dictionaries.fromJson(res.data as Map<String, dynamic>);
  }
}

class FollowUpService {
  final Dio _dio;
  FollowUpService(this._dio);

  Future<List<FollowUpTask>> list({String status = 'pending'}) async {
    final res = await _dio.get('/follow-ups', queryParameters: {'status': status});
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(FollowUpTask.fromJson).toList();
  }

  Future<FollowUpTask> complete(String id, {String? notes}) async {
    final res = await _dio.patch('/follow-ups/$id', data: {
      'action': 'complete',
      if (notes != null) 'notes': notes,
    });
    return FollowUpTask.fromJson(res.data as Map<String, dynamic>);
  }

  Future<FollowUpTask> cancel(String id) async {
    final res = await _dio.patch('/follow-ups/$id', data: {'action': 'cancel'});
    return FollowUpTask.fromJson(res.data as Map<String, dynamic>);
  }

  Future<FollowUpTask> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/follow-ups', data: data);
    return FollowUpTask.fromJson(res.data as Map<String, dynamic>);
  }
}

class InteractionService {
  final Dio _dio;
  InteractionService(this._dio);

  Future<List<Interaction>> listByCustomer(String customerId) async {
    final res = await _dio.get('/interactions', queryParameters: {'customerId': customerId});
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Interaction.fromJson).toList();
  }

  Future<Interaction> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/interactions', data: data);
    return Interaction.fromJson(res.data as Map<String, dynamic>);
  }
}

class DashboardService {
  final Dio _dio;
  DashboardService(this._dio);

  Future<({DashboardStats stats, List<ServiceDistribution> distribution})> stats() async {
    final res = await _dio.get('/dashboard/stats');
    final data = res.data as Map<String, dynamic>;
    return (
      stats: DashboardStats.fromJson(data['stats'] as Map<String, dynamic>),
      distribution: (data['distribution'] as List)
          .cast<Map<String, dynamic>>()
          .map(ServiceDistribution.fromJson)
          .toList(),
    );
  }
}

class AiService {
  final Dio _dio;
  AiService(this._dio);

  /// 跟进话术
  Future<({String suggestion, bool mock})> suggestFollowUp(String customerId) async {
    final res = await _dio.post('/ai/follow-up', data: {'customerId': customerId});
    final data = res.data as Map<String, dynamic>;
    return (suggestion: data['suggestion'] as String, mock: data['aiMock'] as bool);
  }

  /// 客户画像
  Future<({String summary, bool mock})> customerProfile(String customerId) async {
    final res = await _dio.get('/ai/profile/$customerId');
    final data = res.data as Map<String, dynamic>;
    return (summary: data['aiSummary'] as String, mock: data['aiMock'] as bool);
  }
}
