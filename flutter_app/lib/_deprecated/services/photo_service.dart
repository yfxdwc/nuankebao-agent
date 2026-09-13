import 'package:dio/dio.dart';

class PhotoService {
  final Dio _dio;
  PhotoService(this._dio);

  /// 上传 base64 图片, 返回 URL
  Future<String> upload(String base64Data, {String? mimeType}) async {
    final res = await _dio.post('/photos', data: {
      'base64': base64Data,
      if (mimeType != null) 'mimeType': mimeType,
    });
    return (res.data as Map<String, dynamic>)['url'] as String;
  }
}