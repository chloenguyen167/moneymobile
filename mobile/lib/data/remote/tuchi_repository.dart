import 'dart:convert';

import '../../core/network/api_client.dart';
import '../models/models.dart';

class TuchiRepository {
  TuchiRepository(this._api);

  final ApiClient _api;

  Future<void> register(String email, String password, {String? displayName}) async {
    final resp = await _api.post('/auth/register', auth: false, body: {
      'email': email,
      'password': password,
      if (displayName != null) 'display_name': displayName,
    });
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    await _api.saveToken(data['access_token'] as String);
  }

  Future<void> login(String email, String password) async {
    final resp = await _api.post('/auth/login', auth: false, body: {
      'email': email,
      'password': password,
    });
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    await _api.saveToken(data['access_token'] as String);
  }

  Future<void> logout() => _api.clearToken();

  Future<List<TransactionModel>> getTransactions() async {
    final resp = await _api.get('/transactions');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => TransactionModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<TransactionModel> confirmCategory(int transactionId, int categoryId) async {
    final resp = await _api.post('/transactions/$transactionId/confirm?category_id=$categoryId');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    return TransactionModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Lưu giao dịch đã được xử lý on-device (OCR + phân loại chạy trên máy,
  /// backend chỉ lưu trữ).
  Future<TransactionModel> createTransaction({
    required double amount,
    String? merchantName,
    int? categoryId,
    String source = 'manual',
    List<Map<String, dynamic>>? items,
    DateTime? transactionDate,
    double? confidence,
    String? classificationReason,
    String? ocrTrackUsed,
  }) async {
    final resp = await _api.post('/transactions', body: {
      'amount': amount,
      if (merchantName != null) 'merchant_name': merchantName,
      if (categoryId != null) 'category_id': categoryId,
      'source': source,
      if (items != null && items.isNotEmpty) 'items': items,
      if (transactionDate != null)
        'transaction_date': transactionDate.toIso8601String().split('T').first,
      if (confidence != null) 'confidence': confidence,
      if (classificationReason != null) 'classification_reason': classificationReason,
      if (ocrTrackUsed != null) 'ocr_track_used': ocrTrackUsed,
    });
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    return TransactionModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<List<CategoryModel>> getCategories() async {
    final resp = await _api.get('/categories');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => CategoryModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<BudgetModel>> getBudgets() async {
    final resp = await _api.get('/budgets');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => BudgetModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<BudgetModel> createBudget({required int categoryId, required double limitAmount}) async {
    final resp = await _api.post('/budgets', body: {
      'category_id': categoryId,
      'limit_amount': limitAmount,
    });
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    return BudgetModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<AnalyticsSummaryModel> getAnalytics() async {
    final resp = await _api.get('/analytics/summary');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    return AnalyticsSummaryModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<List<NotificationTemplateModel>> getNotificationTemplates() async {
    final resp = await _api.get('/notification-templates');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => NotificationTemplateModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<AlertModel>> getAlerts({bool unreadOnly = false}) async {
    final path = unreadOnly ? '/alerts?unread_only=true' : '/alerts';
    final resp = await _api.get(path);
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => AlertModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> registerDevice({required String fcmToken, String platform = 'android'}) async {
    final resp = await _api.post('/devices/register', body: {
      'fcm_token': fcmToken,
      'platform': platform,
    });
    if (resp.statusCode >= 400) throw Exception(_error(resp));
  }

  Future<List<CategoryForecastModel>> getForecasts({bool refresh = false}) async {
    final resp = await _api.get('/analytics/forecasts?refresh=$refresh');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => CategoryForecastModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String> getGmailOAuthUrl() async {
    final resp = await _api.get('/email/oauth/url');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    return (jsonDecode(resp.body) as Map<String, dynamic>)['url'] as String;
  }

  Future<EmailStatusModel> connectGmail(String authorizationCode) async {
    final resp = await _api.post('/email/connect', body: {'authorization_code': authorizationCode});
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    return EmailStatusModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<EmailStatusModel> getEmailStatus() async {
    final resp = await _api.get('/email/status');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    return EmailStatusModel.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<int> syncEmails() async {
    final resp = await _api.post('/email/sync');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    return (jsonDecode(resp.body) as Map<String, dynamic>)['synced'] as int;
  }

  Future<void> disconnectEmail() async {
    final resp = await _api.delete('/email/disconnect');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
  }

  Future<List<SubscriptionModel>> getSubscriptions({bool refresh = false}) async {
    final resp = await _api.get('/subscriptions?refresh=$refresh');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => SubscriptionModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<SubscriptionModel>> detectSubscriptions() async {
    final resp = await _api.post('/subscriptions/detect');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
    final list = jsonDecode(resp.body) as List;
    return list.map((e) => SubscriptionModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> dismissSubscription(int id) async {
    final resp = await _api.post('/subscriptions/$id/dismiss');
    if (resp.statusCode >= 400) throw Exception(_error(resp));
  }

  String _error(dynamic resp) {
    try {
      final body = jsonDecode(resp.body as String);
      if (body is Map<String, dynamic>) {
        final detail = body['detail'];
        if (detail is String) return detail;
        if (detail is List && detail.isNotEmpty) {
          return detail.map((e) => e['msg'] ?? e.toString()).join(', ');
        }
      }
      return 'Request failed (${resp.statusCode})';
    } catch (_) {
      final raw = resp.body?.toString().trim();
      if (raw != null && raw.isNotEmpty && raw.length < 200) return raw;
      return 'Request failed (${resp.statusCode})';
    }
  }
}
