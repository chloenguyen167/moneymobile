import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ai/receipt_models.dart';
import '../models/models.dart';

/// Lưu trữ cục bộ cho chế độ offline/demo (SharedPreferences).
class LocalStore {
  LocalStore(this._prefs);

  static const _txKey = 'offline_transactions_v1';
  static const _budgetKey = 'offline_budgets_v1';
  static const _txSeqKey = 'offline_tx_seq_v1';
  static const _budgetSeqKey = 'offline_budget_seq_v1';

  final SharedPreferences _prefs;

  static Future<LocalStore> create() async {
    return LocalStore(await SharedPreferences.getInstance());
  }

  static List<CategoryModel> seedCategories() {
    return [
      for (var i = 0; i < kDefaultCategories.length; i++)
        CategoryModel(id: i + 1, name: kDefaultCategories[i], icon: null),
    ];
  }

  List<TransactionModel> loadTransactions() {
    final raw = _prefs.getString(_txKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => TransactionModel.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) {
        final byDate = b.transactionDate.compareTo(a.transactionDate);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
  }

  Future<void> saveTransactions(List<TransactionModel> txs) async {
    await _prefs.setString(
      _txKey,
      jsonEncode(txs.map((t) => t.toJson()).toList()),
    );
  }

  Future<int> nextTransactionId() async {
    final next = (_prefs.getInt(_txSeqKey) ?? 0) + 1;
    await _prefs.setInt(_txSeqKey, next);
    return next;
  }

  List<BudgetModel> loadBudgets() {
    final raw = _prefs.getString(_budgetKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => BudgetModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> saveBudgets(List<BudgetModel> budgets) async {
    await _prefs.setString(
      _budgetKey,
      jsonEncode(budgets.map((b) => b.toJson()).toList()),
    );
  }

  Future<int> nextBudgetId() async {
    final next = (_prefs.getInt(_budgetSeqKey) ?? 0) + 1;
    await _prefs.setInt(_budgetSeqKey, next);
    return next;
  }

  /// Analytics rule-based từ giao dịch local (tháng hiện tại).
  AnalyticsSummaryModel computeAnalytics(List<TransactionModel> all) {
    final now = DateTime.now();
    final monthTxs = all
        .where((t) => t.transactionDate.year == now.year && t.transactionDate.month == now.month)
        .toList();

    final totalSpent = monthTxs.fold<double>(0, (s, t) => s + t.amount);

    final byCatMap = <String, double>{};
    for (final t in monthTxs) {
      final name = t.categoryName ?? 'Khác';
      byCatMap[name] = (byCatMap[name] ?? 0) + t.amount;
    }
    final byCategory = byCatMap.entries
        .map((e) => {'category': e.key, 'amount': e.value})
        .toList()
      ..sort((a, b) => ((b['amount'] as num).compareTo(a['amount'] as num)));

    final byDay = <String, double>{};
    for (final t in monthTxs) {
      final key =
          '${t.transactionDate.year.toString().padLeft(4, '0')}-'
          '${t.transactionDate.month.toString().padLeft(2, '0')}-'
          '${t.transactionDate.day.toString().padLeft(2, '0')}';
      byDay[key] = (byDay[key] ?? 0) + t.amount;
    }
    final dailyTrend = byDay.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final dailyTrendMaps =
        dailyTrend.map((e) => {'date': e.key, 'amount': e.value}).toList();

    final dayOfMonth = now.day.clamp(1, 31);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final forecast = dayOfMonth == 0 ? totalSpent : totalSpent / dayOfMonth * daysInMonth;
    final calendarExpected = forecast == 0 ? 0.0 : forecast * dayOfMonth / daysInMonth;
    final onPacePercent = calendarExpected <= 0
        ? 100.0
        : (totalSpent / calendarExpected) * 100;

    return AnalyticsSummaryModel(
      totalSpent: totalSpent,
      byCategory: byCategory,
      dailyTrend: dailyTrendMaps,
      forecastEndOfMonth: forecast,
      onPacePercent: onPacePercent.isFinite ? onPacePercent : 100,
      categoryForecasts: byCategory
          .map(
            (c) => {
              'category': c['category'],
              'forecast_amount': ((c['amount'] as num) / dayOfMonth) * daysInMonth,
            },
          )
          .toList(),
    );
  }

  List<BudgetModel> budgetsWithSpent(List<BudgetModel> budgets, List<TransactionModel> txs) {
    final now = DateTime.now();
    final monthTxs = txs.where(
      (t) => t.transactionDate.year == now.year && t.transactionDate.month == now.month,
    );
    return budgets.map((b) {
      final spent = monthTxs
          .where((t) => t.categoryId == b.categoryId)
          .fold<double>(0, (s, t) => s + t.amount);
      final pct = b.limitAmount <= 0 ? 0.0 : (spent / b.limitAmount) * 100;
      return BudgetModel(
        id: b.id,
        categoryId: b.categoryId,
        categoryName: b.categoryName,
        limitAmount: b.limitAmount,
        period: b.period,
        spent: spent,
        percentUsed: pct,
      );
    }).toList();
  }
}
