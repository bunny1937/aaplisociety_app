import 'package:dio/dio.dart';

Future<Map<String, dynamic>> submitProfileEditRequest(Dio dio, Map<String, dynamic> body) async {
  final res = await dio.post('/profile-edit-requests', data: body);
  return Map<String, dynamic>.from(res.data as Map);
}

Future<List> fetchProfileEditRequests(Dio dio) async {
  final res = await dio.get('/profile-edit-requests');
  return res.data as List;
}
