import 'package:dio/dio.dart';
import '../models/wellness_record.dart';

class WellnessRecordService {
  final Dio _dio;
  WellnessRecordService(this._dio);

  Future<List<WellnessRecord>> list({String? customerId, int limit = 50}) async {
    final res = await _dio.get('/wellness-records', queryParameters: {
      if (customerId != null) 'customerId': customerId,
      'limit': limit,
    });
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(WellnessRecord.fromJson).toList();
  }

  Future<WellnessRecord> getById(String id) async {
    final res = await _dio.get('/wellness-records/$id');
    return WellnessRecord.fromJson(res.data as Map<String, dynamic>);
  }

  Future<WellnessRecord> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/wellness-records', data: data);
    return WellnessRecord.fromJson(res.data as Map<String, dynamic>);
  }

  Future<WellnessRecord> update(String id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/wellness-records/$id', data: data);
    return WellnessRecord.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> delete(String id) async {
    await _dio.delete('/wellness-records/$id');
  }
}
