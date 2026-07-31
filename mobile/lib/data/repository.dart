import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import 'local/offline_repository.dart';
import 'models/models.dart';
import 'remote/tuchi_repository.dart';

/// Facade: online (Tuchi API) hoặc offline (SharedPreferences) theo [AppConfig.offlineMode].
class AppRepository {
  AppRepository.online(ApiClient api) : _online = TuchiRepository(api), _offline = null;

  AppRepository.offline() : _online = null, _offline = OfflineRepository();

  final TuchiRepository? _online;
  final OfflineRepository? _offline;

  bool get isOffline => _offline != null;

  Future<void> register(String email, String password, {String? displayName}) =>
      _dispatch((o) => o.register(email, password, displayName: displayName),
          (f) => f.register(email, password, displayName: displayName));

  Future<void> login(String email, String password) =>
      _dispatch((o) => o.login(email, password), (f) => f.login(email, password));

  Future<void> logout() => _dispatch((o) => o.logout(), (f) => f.logout());

  Future<List<TransactionModel>> getTransactions() =>
      _dispatch((o) => o.getTransactions(), (f) => f.getTransactions());

  Future<TransactionModel> confirmCategory(int transactionId, int categoryId) =>
      _dispatch(
        (o) => o.confirmCategory(transactionId, categoryId),
        (f) => f.confirmCategory(transactionId, categoryId),
      );

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
  }) =>
      _dispatch(
        (o) => o.createTransaction(
          amount: amount,
          merchantName: merchantName,
          categoryId: categoryId,
          source: source,
          items: items,
          transactionDate: transactionDate,
          confidence: confidence,
          classificationReason: classificationReason,
          ocrTrackUsed: ocrTrackUsed,
        ),
        (f) => f.createTransaction(
          amount: amount,
          merchantName: merchantName,
          categoryId: categoryId,
          source: source,
          items: items,
          transactionDate: transactionDate,
          confidence: confidence,
          classificationReason: classificationReason,
          ocrTrackUsed: ocrTrackUsed,
        ),
      );

  Future<List<CategoryModel>> getCategories() =>
      _dispatch((o) => o.getCategories(), (f) => f.getCategories());

  Future<List<BudgetModel>> getBudgets() =>
      _dispatch((o) => o.getBudgets(), (f) => f.getBudgets());

  Future<BudgetModel> createBudget({required int categoryId, required double limitAmount}) =>
      _dispatch(
        (o) => o.createBudget(categoryId: categoryId, limitAmount: limitAmount),
        (f) => f.createBudget(categoryId: categoryId, limitAmount: limitAmount),
      );

  Future<AnalyticsSummaryModel> getAnalytics() =>
      _dispatch((o) => o.getAnalytics(), (f) => f.getAnalytics());

  Future<List<NotificationTemplateModel>> getNotificationTemplates() =>
      _dispatch((o) => o.getNotificationTemplates(), (f) => f.getNotificationTemplates());

  Future<List<AlertModel>> getAlerts({bool unreadOnly = false}) =>
      _dispatch((o) => o.getAlerts(unreadOnly: unreadOnly), (f) => f.getAlerts(unreadOnly: unreadOnly));

  Future<void> registerDevice({required String fcmToken, String platform = 'android'}) =>
      _dispatch(
        (o) => o.registerDevice(fcmToken: fcmToken, platform: platform),
        (f) => f.registerDevice(fcmToken: fcmToken, platform: platform),
      );

  Future<List<CategoryForecastModel>> getForecasts({bool refresh = false}) =>
      _dispatch((o) => o.getForecasts(refresh: refresh), (f) => f.getForecasts(refresh: refresh));

  Future<String> getGmailOAuthUrl() =>
      _dispatch((o) => o.getGmailOAuthUrl(), (f) => f.getGmailOAuthUrl());

  Future<EmailStatusModel> connectGmail(String authorizationCode) =>
      _dispatch((o) => o.connectGmail(authorizationCode), (f) => f.connectGmail(authorizationCode));

  Future<EmailStatusModel> getEmailStatus() =>
      _dispatch((o) => o.getEmailStatus(), (f) => f.getEmailStatus());

  Future<int> syncEmails() => _dispatch((o) => o.syncEmails(), (f) => f.syncEmails());

  Future<void> disconnectEmail() =>
      _dispatch((o) => o.disconnectEmail(), (f) => f.disconnectEmail());

  Future<List<SubscriptionModel>> getSubscriptions({bool refresh = false}) =>
      _dispatch((o) => o.getSubscriptions(refresh: refresh), (f) => f.getSubscriptions(refresh: refresh));

  Future<List<SubscriptionModel>> detectSubscriptions() =>
      _dispatch((o) => o.detectSubscriptions(), (f) => f.detectSubscriptions());

  Future<void> dismissSubscription(int id) =>
      _dispatch((o) => o.dismissSubscription(id), (f) => f.dismissSubscription(id));

  Future<T> _dispatch<T>(
    Future<T> Function(TuchiRepository online) online,
    Future<T> Function(OfflineRepository offline) offline,
  ) {
    final off = _offline;
    if (off != null) return offline(off);
    final on = _online;
    if (on == null) throw StateError('AppRepository chưa khởi tạo');
    return online(on);
  }

  static AppRepository fromConfig(ApiClient api) {
    if (AppConfig.offlineMode) return AppRepository.offline();
    return AppRepository.online(api);
  }
}
