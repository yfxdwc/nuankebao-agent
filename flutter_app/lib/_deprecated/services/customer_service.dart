import 'package:dio/dio.dart';
import '../models/customer.dart';

class CustomerService {
  final Dio _dio;
  CustomerService(this._dio);

  /// 客户列表
  Future<List<Customer>> list({String? search, int limit = 50, int offset = 0}) async {
    final res = await _dio.get('/customers', queryParameters: {
      if (search != null && search.isNotEmpty) 'search': search,
      'limit': limit,
      'offset': offset,
    });
    final items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    return items.map(Customer.fromJson).toList();
  }

  /// 客户详情
  Future<Customer> getById(String id) async {
    final res = await _dio.get('/customers/$id');
    return Customer.fromJson(res.data as Map<String, dynamic>);
  }

  /// 创建客户
  Future<Customer> create(Map<String, dynamic> data) async {
    final res = await _dio.post('/customers', data: data);
    return Customer.fromJson(res.data as Map<String, dynamic>);
  }

  /// 更新客户
  Future<Customer> update(String id, Map<String, dynamic> data) async {
    final res = await _dio.patch('/customers/$id', data: data);
    return Customer.fromJson(res.data as Map<String, dynamic>);
  }

  /// 删除 (软删除)
  Future<void> delete(String id) async {
    await _dio.delete('/customers/$id');
  }
}
