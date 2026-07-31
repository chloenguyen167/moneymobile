class CategoryModel {
  CategoryModel({required this.id, required this.name, this.icon, this.isUserDefined = false});

  final int id;
  final String name;
  final String? icon;
  final bool isUserDefined;

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id'] as int,
        name: json['name'] as String,
        icon: json['icon'] as String?,
        isUserDefined: json['is_user_defined'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (icon != null) 'icon': icon,
        'is_user_defined': isUserDefined,
      };
}

class TransactionModel {
  TransactionModel({
    required this.id,
    required this.amount,
    required this.source,
    required this.transactionDate,
    required this.createdAt,
    this.merchantName,
    this.categoryId,
    this.categoryName,
    this.confidence,
    this.ocrTrackUsed,
    this.classificationReason,
    this.items,
  });

  final int id;
  final String? merchantName;
  final double amount;
  final List<dynamic>? items;
  final int? categoryId;
  final String? categoryName;
  final String source;
  final double? confidence;
  final String? ocrTrackUsed;
  final DateTime transactionDate;
  final DateTime createdAt;
  final String? classificationReason;

  factory TransactionModel.fromJson(Map<String, dynamic> json) => TransactionModel(
        id: json['id'] as int,
        merchantName: json['merchant_name'] as String?,
        amount: (json['amount'] as num).toDouble(),
        items: json['items'] as List<dynamic>?,
        categoryId: json['category_id'] as int?,
        categoryName: json['category_name'] as String?,
        source: json['source'] as String,
        confidence: (json['confidence'] as num?)?.toDouble(),
        ocrTrackUsed: json['ocr_track_used'] as String?,
        transactionDate: DateTime.parse(json['transaction_date'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        classificationReason: json['classification_reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (merchantName != null) 'merchant_name': merchantName,
        'amount': amount,
        if (items != null) 'items': items,
        if (categoryId != null) 'category_id': categoryId,
        if (categoryName != null) 'category_name': categoryName,
        'source': source,
        if (confidence != null) 'confidence': confidence,
        if (ocrTrackUsed != null) 'ocr_track_used': ocrTrackUsed,
        'transaction_date': transactionDate.toIso8601String().split('T').first,
        'created_at': createdAt.toIso8601String(),
        if (classificationReason != null) 'classification_reason': classificationReason,
      };

  TransactionModel copyWith({
    int? categoryId,
    String? categoryName,
    String? classificationReason,
  }) =>
      TransactionModel(
        id: id,
        amount: amount,
        source: source,
        transactionDate: transactionDate,
        createdAt: createdAt,
        merchantName: merchantName,
        categoryId: categoryId ?? this.categoryId,
        categoryName: categoryName ?? this.categoryName,
        confidence: confidence,
        ocrTrackUsed: ocrTrackUsed,
        classificationReason: classificationReason ?? this.classificationReason,
        items: items,
      );
}

class BudgetModel {
  BudgetModel({
    required this.id,
    required this.categoryId,
    required this.limitAmount,
    required this.period,
    required this.spent,
    required this.percentUsed,
    this.categoryName,
  });

  final int id;
  final int categoryId;
  final String? categoryName;
  final double limitAmount;
  final String period;
  final double spent;
  final double percentUsed;

  factory BudgetModel.fromJson(Map<String, dynamic> json) => BudgetModel(
        id: json['id'] as int,
        categoryId: json['category_id'] as int,
        categoryName: json['category_name'] as String?,
        limitAmount: (json['limit_amount'] as num).toDouble(),
        period: json['period'] as String,
        spent: (json['spent'] as num?)?.toDouble() ?? 0,
        percentUsed: (json['percent_used'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'category_id': categoryId,
        if (categoryName != null) 'category_name': categoryName,
        'limit_amount': limitAmount,
        'period': period,
        'spent': spent,
        'percent_used': percentUsed,
      };
}

class AnalyticsSummaryModel {
  AnalyticsSummaryModel({
    required this.totalSpent,
    required this.byCategory,
    required this.dailyTrend,
    required this.forecastEndOfMonth,
    required this.onPacePercent,
    this.categoryForecasts = const [],
  });

  final double totalSpent;
  final List<Map<String, dynamic>> byCategory;
  final List<Map<String, dynamic>> dailyTrend;
  final double forecastEndOfMonth;
  final double onPacePercent;
  final List<Map<String, dynamic>> categoryForecasts;

  factory AnalyticsSummaryModel.fromJson(Map<String, dynamic> json) => AnalyticsSummaryModel(
        totalSpent: (json['total_spent'] as num).toDouble(),
        byCategory: (json['by_category'] as List).cast<Map<String, dynamic>>(),
        dailyTrend: (json['daily_trend'] as List).cast<Map<String, dynamic>>(),
        forecastEndOfMonth: (json['forecast_end_of_month'] as num).toDouble(),
        onPacePercent: (json['on_pace_percent'] as num).toDouble(),
        categoryForecasts: (json['category_forecasts'] as List?)?.cast<Map<String, dynamic>>() ?? [],
      );
}

class CategoryForecastModel {
  CategoryForecastModel({
    required this.categoryId,
    required this.categoryName,
    required this.forecastAmount,
    this.currentSpent = 0,
    this.method = 'holt_winters',
    this.historicalMonths = 0,
    this.onTrack = true,
  });

  final int categoryId;
  final String categoryName;
  final double forecastAmount;
  final double currentSpent;
  final String method;
  final int historicalMonths;
  final bool onTrack;

  factory CategoryForecastModel.fromJson(Map<String, dynamic> json) => CategoryForecastModel(
        categoryId: json['category_id'] as int,
        categoryName: json['category_name'] as String,
        forecastAmount: (json['forecast_amount'] as num).toDouble(),
        currentSpent: (json['current_spent'] as num?)?.toDouble() ?? 0,
        method: json['method'] as String? ?? 'holt_winters',
        historicalMonths: json['historical_months'] as int? ?? 0,
        onTrack: json['on_track'] as bool? ?? true,
      );
}

class EmailStatusModel {
  EmailStatusModel({required this.connected, this.email, this.lastSyncAt});

  final bool connected;
  final String? email;
  final String? lastSyncAt;

  factory EmailStatusModel.fromJson(Map<String, dynamic> json) => EmailStatusModel(
        connected: json['connected'] as bool,
        email: json['email'] as String?,
        lastSyncAt: json['last_sync_at'] as String?,
      );
}

class NotificationTemplateModel {
  NotificationTemplateModel({
    required this.id,
    required this.packageName,
    required this.regexPattern,
    required this.templateType,
    required this.version,
  });

  final int id;
  final String packageName;
  final String regexPattern;
  final String templateType;
  final int version;

  factory NotificationTemplateModel.fromJson(Map<String, dynamic> json) => NotificationTemplateModel(
        id: json['id'] as int,
        packageName: json['package_name'] as String,
        regexPattern: json['regex_pattern'] as String,
        templateType: json['template_type'] as String,
        version: json['version'] as int,
      );
}

class AlertModel {
  AlertModel({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.readAt,
  });

  final int id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final DateTime? readAt;

  factory AlertModel.fromJson(Map<String, dynamic> json) => AlertModel(
        id: json['id'] as int,
        type: json['type'] as String,
        payload: json['payload'] as Map<String, dynamic>,
        createdAt: DateTime.parse(json['created_at'] as String),
        readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
      );
}

class SubscriptionModel {
  SubscriptionModel({
    required this.id,
    required this.merchantName,
    required this.amount,
    required this.cycleDays,
    required this.occurrenceCount,
    required this.lastChargeDate,
    required this.monthlyCost,
    this.nextExpectedDate,
  });

  final int id;
  final String merchantName;
  final double amount;
  final int cycleDays;
  final int occurrenceCount;
  final DateTime lastChargeDate;
  final DateTime? nextExpectedDate;
  final double monthlyCost;

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) => SubscriptionModel(
        id: json['id'] as int,
        merchantName: json['merchant_name'] as String,
        amount: (json['amount'] as num).toDouble(),
        cycleDays: json['cycle_days'] as int,
        occurrenceCount: json['occurrence_count'] as int,
        lastChargeDate: DateTime.parse(json['last_charge_date'] as String),
        nextExpectedDate: json['next_expected_date'] != null
            ? DateTime.parse(json['next_expected_date'] as String)
            : null,
        monthlyCost: (json['monthly_cost'] as num).toDouble(),
      );
}

