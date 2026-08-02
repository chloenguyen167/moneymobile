import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

class ApiClient {
  ApiClient(this._storage);

  final FlutterSecureStorage _storage;
  static const _tokenKey = 'access_token';

  Future<String?> get token => _storage.read(key: _tokenKey);

  Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  Future<void> clearToken() => _storage.delete(key: _tokenKey);

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final headers = {'Content-Type': 'application/json'};
    if (auth) {
      final t = await token;
      if (t != null) headers['Authorization'] = 'Bearer $t';
    }
    return headers;
  }

  Future<http.Response> get(String path, {bool auth = true}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    try {
      return await http.get(uri, headers: await _headers(auth: auth));
    } on Exception catch (e) {
      throw Exception('Không kết nối được backend (${AppConfig.apiBaseUrl}): $e');
    }
  }

  Future<http.Response> post(String path, {Object? body, bool auth = true}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    try {
      return await http.post(uri, headers: await _headers(auth: auth), body: jsonEncode(body));
    } on Exception catch (e) {
      throw Exception('Không kết nối được backend (${AppConfig.apiBaseUrl}): $e');
    }
  }

  Future<bool> pingHealth() async {
    final apiUri = Uri.parse(AppConfig.apiBaseUrl);
    final healthUri = Uri(
      scheme: apiUri.scheme,
      host: apiUri.host,
      port: apiUri.port,
      path: '/health',
    );
    final resp = await http.get(healthUri).timeout(const Duration(seconds: 8));
    return resp.statusCode == 200;
  }

  Future<http.Response> patch(String path, {Object? body, bool auth = true}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    return http.patch(uri, headers: await _headers(auth: auth), body: jsonEncode(body));
  }

  Future<http.Response> delete(String path, {bool auth = true}) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    return http.delete(uri, headers: await _headers(auth: auth));
  }

  Future<http.StreamedResponse> multipart(
    String path, {
    required List<int> fileBytes,
    required String filename,
    Map<String, String> fields = const {},
    Duration timeout = const Duration(minutes: 10),
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
    final request = http.MultipartRequest('POST', uri);
    final t = await token;
    if (t != null) request.headers['Authorization'] = 'Bearer $t';
    request.fields.addAll(fields);
    request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: filename));
    final client = http.Client();
    try {
      return await client.send(request).timeout(timeout);
    } on Exception catch (e) {
      throw Exception(
        'Không gửi được ảnh lên backend (${AppConfig.apiBaseUrl}$path): $e',
      );
    } finally {
      client.close();
    }
  }
}
