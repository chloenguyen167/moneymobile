import '../models/models.dart';
import 'local_store.dart';

/// Repository offline/demo — cùng surface API với [TuchiRepository],
/// lưu trên SharedPreferences, không gọi backend.
class OfflineRepository {
  OfflineRepository();

  LocalStore? _store;

  Future<LocalStore> _ensureStore() async {
    return _store ??= await LocalStore.create();
  }

  Future<void> register(String email, String password, {String? displayName}) async {}

  Future<void> login(String email, String password) async {}

  Future<void> logout() async {}

  Future<List<TransactionModel>> getTransactions() async {
    return (await _ensureStore()).loadTransactions();
  }

  Future<TransactionModel> confirmCategory(int transactionId, int categoryId) async {
    final store = await _ensureStore();
    final cats = LocalStore.seedCategories();
    final cat = cats.where((c) => c.id == categoryId).firstOrNull;
    final txs = store.loadTransactions();
    final idx = txs.indexWhere((t) => t.id == transactionId);
    if (idx < 0) throw Exception('Transaction not found');
    final updated = txs[idx].copyWith(
      categoryId: categoryId,
      categoryName: cat?.name,
      classificationReason: 'offline confirm',
    );
    txs[idx] = updated;
    await store.saveTransactions(txs);
    return updated;
  }

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
    final store = await _ensureStore();
    final cats = LocalStore.seedCategories();
    final catName = categoryId == null
        ? null
        : cats.where((c) => c.id == categoryId).firstOrNull?.name;
    final tx = TransactionModel(
      id: await store.nextTransactionId(),
      amount: amount,
      merchantName: merchantName,
      categoryId: categoryId,
      categoryName: catName,
      source: source,
      items: items,
      transactionDate: transactionDate ?? DateTime.now(),
      createdAt: DateTime.now(),
      confidence: confidence,
      classificationReason: classificationReason ?? 'offline',
      ocrTrackUsed: ocrTrackUsed,
    );
    final txs = store.loadTransactions();
    txs.insert(0, tx);
    await store.saveTransactions(txs);
    return tx;
  }

  Future<List<CategoryModel>> getCategories() async => LocalStore.seedCategories();

  Future<List<BudgetModel>> getBudgets() async {
    final store = await _ensureStore();
    final budgets = store.loadBudgets();
    return store.budgetsWithSpent(budgets, store.loadTransactions());
  }

  Future<BudgetModel> createBudget({required int categoryId, required double limitAmount}) async {
    final store = await _ensureStore();
    final cats = LocalStore.seedCategories();
    final cat = cats.where((c) => c.id == categoryId).firstOrNull;
    final budget = BudgetModel(
      id: await store.nextBudgetId(),
      categoryId: categoryId,
      categoryName: cat?.name,
      limitAmount: limitAmount,
      period: 'monthly',
      spent: 0,
      percentUsed: 0,
    );
    final all = store.loadBudgets();
    all.add(budget);
    await store.saveBudgets(all);
    return (await getBudgets()).firstWhere((b) => b.id == budget.id);
  }

  Future<AnalyticsSummaryModel> getAnalytics() async {
    final store = await _ensureStore();
    return store.computeAnalytics(store.loadTransactions());
  }

  Future<List<NotificationTemplateModel>> getNotificationTemplates() async => [];

  Future<List<AlertModel>> getAlerts({bool unreadOnly = false}) async => [];

  Future<void> registerDevice({required String fcmToken, String platform = 'android'}) async {}

  Future<List<CategoryForecastModel>> getForecasts({bool refresh = false}) async => [];

  Future<String> getGmailOAuthUrl() async {
    throw Exception('Email không khả dụng ở chế độ offline');
  }

  Future<EmailStatusModel> connectGmail(String authorizationCode) async {
    throw Exception('Email không khả dụng ở chế độ offline');
  }

  Future<EmailStatusModel> getEmailStatus() async {
    return EmailStatusModel(connected: false);
  }

  Future<int> syncEmails() async => 0;

  Future<void> disconnectEmail() async {}

  Future<List<SubscriptionModel>> getSubscriptions({bool refresh = false}) async => [];

  Future<List<SubscriptionModel>> detectSubscriptions() async => [];

  Future<void> dismissSubscription(int id) async {}
}
