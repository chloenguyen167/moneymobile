class CategoryModel {
  CategoryModel({
    required this.id,
    required this.name,
    this.icon,
    this.isUserDefined = false,
  });

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
    this.itemCategories = const [],
    this.transactionType = 'expense',
    this.hasImage = false,
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
  final List<ItemCategoryModel> itemCategories;
  final String transactionType;
  final bool hasImage;
  final String source;
  final double? confidence;
  final String? ocrTrackUsed;
  final DateTime transactionDate;
  final DateTime createdAt;
  final String? classificationReason;

  bool get isIncome => transactionType == 'income';
  bool get hasItems => items != null && items!.isNotEmpty;

  factory TransactionModel.fromJson(Map<String, dynamic> json) =>
      TransactionModel(
        id: json['id'] as int,
        merchantName: json['merchant_name'] as String?,
        amount: (json['amount'] as num).toDouble(),
        items: json['items'] as List<dynamic>?,
        categoryId: json['category_id'] as int?,
        categoryName: json['category_name'] as String?,
        itemCategories:
            (json['item_categories'] as List?)
                ?.map(
                  (e) => ItemCategoryModel.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            const [],
        transactionType: json['transaction_type'] as String? ?? 'expense',
        hasImage: json['has_image'] as bool? ?? false,
        source: json['source'] as String,
        confidence: (json['confidence'] as num?)?.toDouble(),
        ocrTrackUsed: json['ocr_track_used'] as String?,
        transactionDate: DateTime.parse(json['transaction_date'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        classificationReason: json['classification_reason'] as String?,
      );
}

class ItemCategoryModel {
  ItemCategoryModel({this.id, required this.name});

  final int? id;
  final String name;

  factory ItemCategoryModel.fromJson(Map<String, dynamic> json) =>
      ItemCategoryModel(
        id: json['id'] as int?,
        name: json['name'] as String,
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

  factory AnalyticsSummaryModel.fromJson(Map<String, dynamic> json) =>
      AnalyticsSummaryModel(
        totalSpent: (json['total_spent'] as num).toDouble(),
        byCategory: (json['by_category'] as List).cast<Map<String, dynamic>>(),
        dailyTrend: (json['daily_trend'] as List).cast<Map<String, dynamic>>(),
        forecastEndOfMonth: (json['forecast_end_of_month'] as num).toDouble(),
        onPacePercent: (json['on_pace_percent'] as num).toDouble(),
        categoryForecasts:
            (json['category_forecasts'] as List?)
                ?.cast<Map<String, dynamic>>() ??
            [],
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

  factory CategoryForecastModel.fromJson(Map<String, dynamic> json) =>
      CategoryForecastModel(
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

  factory EmailStatusModel.fromJson(Map<String, dynamic> json) =>
      EmailStatusModel(
        connected: json['connected'] as bool,
        email: json['email'] as String?,
        lastSyncAt: json['last_sync_at'] as String?,
      );
}

class ProcessReceiptResult {
  ProcessReceiptResult({
    required this.ocr,
    required this.classification,
    this.transactionId,
  });

  final Map<String, dynamic> ocr;
  final Map<String, dynamic> classification;
  final int? transactionId;

  factory ProcessReceiptResult.fromJson(Map<String, dynamic> json) =>
      ProcessReceiptResult(
        ocr: json['ocr'] as Map<String, dynamic>,
        classification: json['classification'] as Map<String, dynamic>,
        transactionId: json['transaction_id'] as int?,
      );
}

class PaymentScreenshotExtractModel {
  PaymentScreenshotExtractModel({
    this.merchant,
    this.totalAmount,
    this.transactionDate,
    this.paymentSource,
    this.description,
    this.referenceCode,
    this.ocrTrackUsed,
    this.ocrConfidence,
    this.rawText,
  });

  final String? merchant;
  final double? totalAmount;
  final DateTime? transactionDate;
  final String? paymentSource;
  final String? description;
  final String? referenceCode;
  final String? ocrTrackUsed;
  final double? ocrConfidence;
  final String? rawText;

  factory PaymentScreenshotExtractModel.fromJson(Map<String, dynamic> json) =>
      PaymentScreenshotExtractModel(
        merchant: json['merchant'] as String?,
        totalAmount: (json['total_amount'] as num?)?.toDouble(),
        transactionDate: json['transaction_date'] != null
            ? DateTime.parse(json['transaction_date'] as String)
            : null,
        paymentSource: json['payment_source'] as String?,
        description: json['description'] as String?,
        referenceCode: json['reference_code'] as String?,
        ocrTrackUsed: json['ocr_track_used'] as String?,
        ocrConfidence: (json['ocr_confidence'] as num?)?.toDouble(),
        rawText: json['raw_text'] as String?,
      );
}

class ProcessPaymentScreenshotResult {
  ProcessPaymentScreenshotResult({
    required this.extraction,
    required this.classification,
    this.transactionId,
  });

  final PaymentScreenshotExtractModel extraction;
  final Map<String, dynamic> classification;
  final int? transactionId;

  factory ProcessPaymentScreenshotResult.fromJson(Map<String, dynamic> json) =>
      ProcessPaymentScreenshotResult(
        extraction: PaymentScreenshotExtractModel.fromJson(
          json['extraction'] as Map<String, dynamic>,
        ),
        classification: json['classification'] as Map<String, dynamic>,
        transactionId: json['transaction_id'] as int?,
      );
}

class ProcessImageResult {
  ProcessImageResult({
    required this.kind,
    this.transactionId,
    this.ocr,
    this.extraction,
    this.classification,
  });

  final String kind;
  final int? transactionId;
  final Map<String, dynamic>? ocr;
  final PaymentScreenshotExtractModel? extraction;
  final Map<String, dynamic>? classification;

  double? get amount {
    if (kind == 'payment_screenshot') return extraction?.totalAmount;
    return (ocr?['total_amount'] as num?)?.toDouble();
  }

  String? get merchant {
    if (kind == 'payment_screenshot') {
      return extraction?.merchant ?? extraction?.paymentSource;
    }
    return ocr?['merchant']?.toString();
  }

  List<String> get categoryLabels {
    final labels = <String>{};
    final breakdown =
        (classification?['category_breakdown'] as List<dynamic>?) ?? const [];
    for (final entry in breakdown) {
      final name = (entry as Map)['category_name']?.toString();
      if (name != null && name.isNotEmpty) labels.add(name);
    }
    final primary = classification?['category_name']?.toString();
    if (primary != null && primary.isNotEmpty) labels.add(primary);
    return labels.toList();
  }

  factory ProcessImageResult.fromJson(Map<String, dynamic> json) =>
      ProcessImageResult(
        kind: json['kind'] as String? ?? 'receipt',
        transactionId: json['transaction_id'] as int?,
        ocr: json['ocr'] as Map<String, dynamic>?,
        extraction: json['extraction'] != null
            ? PaymentScreenshotExtractModel.fromJson(
                json['extraction'] as Map<String, dynamic>,
              )
            : null,
        classification: json['classification'] as Map<String, dynamic>?,
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

  factory NotificationTemplateModel.fromJson(Map<String, dynamic> json) =>
      NotificationTemplateModel(
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
    readAt: json['read_at'] != null
        ? DateTime.parse(json['read_at'] as String)
        : null,
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

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) =>
      SubscriptionModel(
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

class PipelineHealthModel {
  PipelineHealthModel({
    required this.status,
    required this.periodDays,
    required this.ocrTotal,
    required this.ocrSmartTrackPct,
    required this.classifyTotal,
    required this.classifySmartTrackPct,
    required this.targetSmartTrackPct,
    required this.recommendations,
    required this.dailyBreakdown,
    required this.currentThresholds,
  });

  final String status;
  final int periodDays;
  final int ocrTotal;
  final double ocrSmartTrackPct;
  final int classifyTotal;
  final double classifySmartTrackPct;
  final double targetSmartTrackPct;
  final List<String> recommendations;
  final List<Map<String, dynamic>> dailyBreakdown;
  final Map<String, dynamic> currentThresholds;

  factory PipelineHealthModel.fromJson(Map<String, dynamic> json) =>
      PipelineHealthModel(
        status: json['status'] as String,
        periodDays: json['period_days'] as int,
        ocrTotal: json['ocr_total'] as int,
        ocrSmartTrackPct: (json['ocr_smart_track_pct'] as num).toDouble(),
        classifyTotal: json['classify_total'] as int,
        classifySmartTrackPct: (json['classify_smart_track_pct'] as num)
            .toDouble(),
        targetSmartTrackPct: (json['target_smart_track_pct'] as num).toDouble(),
        recommendations: (json['recommendations'] as List).cast<String>(),
        dailyBreakdown: (json['daily_breakdown'] as List)
            .cast<Map<String, dynamic>>(),
        currentThresholds: json['current_thresholds'] as Map<String, dynamic>,
      );
}

class CashflowProfileModel {
  CashflowProfileModel({
    required this.startingBalance,
    required this.currency,
    this.monthlyIncome,
    this.updatedAt,
  });

  final double startingBalance;
  final double? monthlyIncome;
  final String currency;
  final DateTime? updatedAt;

  factory CashflowProfileModel.fromJson(Map<String, dynamic> json) =>
      CashflowProfileModel(
        startingBalance: (json['starting_balance'] as num).toDouble(),
        monthlyIncome: (json['monthly_income'] as num?)?.toDouble(),
        currency: json['currency'] as String? ?? 'VND',
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : null,
      );
}

class CashflowForecastModel {
  CashflowForecastModel({
    required this.month,
    required this.startingBalance,
    required this.spentSoFar,
    required this.remainingBalance,
    required this.daysElapsed,
    required this.daysRemaining,
    required this.dailyBurnRate,
    required this.forecastEndOfMonthSpend,
    required this.projectedEndBalance,
    required this.canPredictDepletionDate,
    this.monthlyIncome,
    this.depletionDate,
  });

  final String month;
  final double startingBalance;
  final double? monthlyIncome;
  final double spentSoFar;
  final double remainingBalance;
  final int daysElapsed;
  final int daysRemaining;
  final double dailyBurnRate;
  final double forecastEndOfMonthSpend;
  final double projectedEndBalance;
  final String? depletionDate;
  final bool canPredictDepletionDate;

  factory CashflowForecastModel.fromJson(Map<String, dynamic> json) =>
      CashflowForecastModel(
        month: json['month'] as String,
        startingBalance: (json['starting_balance'] as num).toDouble(),
        monthlyIncome: (json['monthly_income'] as num?)?.toDouble(),
        spentSoFar: (json['spent_so_far'] as num).toDouble(),
        remainingBalance: (json['remaining_balance'] as num).toDouble(),
        daysElapsed: json['days_elapsed'] as int,
        daysRemaining: json['days_remaining'] as int,
        dailyBurnRate: (json['daily_burn_rate'] as num).toDouble(),
        forecastEndOfMonthSpend: (json['forecast_end_of_month_spend'] as num)
            .toDouble(),
        projectedEndBalance: (json['projected_end_balance'] as num).toDouble(),
        depletionDate: json['depletion_date'] as String?,
        canPredictDepletionDate:
            json['can_predict_depletion_date'] as bool? ?? false,
      );
}

class CashflowDriverModel {
  CashflowDriverModel({
    required this.categoryName,
    required this.spentSoFar,
    required this.forecastEndOfMonth,
    required this.safeAmount,
    required this.excessAmount,
    required this.paceRatio,
  });

  final String categoryName;
  final double spentSoFar;
  final double forecastEndOfMonth;
  final double safeAmount;
  final double excessAmount;
  final double paceRatio;

  factory CashflowDriverModel.fromJson(Map<String, dynamic> json) =>
      CashflowDriverModel(
        categoryName: json['category_name'] as String,
        spentSoFar: (json['spent_so_far'] as num).toDouble(),
        forecastEndOfMonth: (json['forecast_end_of_month'] as num).toDouble(),
        safeAmount: (json['safe_amount'] as num).toDouble(),
        excessAmount: (json['excess_amount'] as num).toDouble(),
        paceRatio: (json['pace_ratio'] as num).toDouble(),
      );
}

class CashflowRecommendationModel {
  CashflowRecommendationModel({
    required this.categoryName,
    required this.suggestedCutAmount,
    required this.basis,
    required this.message,
    required this.priority,
    this.suggestedCutCount,
  });

  final String categoryName;
  final double suggestedCutAmount;
  final int? suggestedCutCount;
  final String basis;
  final String message;
  final String priority;

  factory CashflowRecommendationModel.fromJson(Map<String, dynamic> json) =>
      CashflowRecommendationModel(
        categoryName: json['category_name'] as String,
        suggestedCutAmount: (json['suggested_cut_amount'] as num).toDouble(),
        suggestedCutCount: json['suggested_cut_count'] as int?,
        basis: json['basis'] as String,
        message: json['message'] as String,
        priority: json['priority'] as String,
      );
}

class CashflowInsightsModel {
  CashflowInsightsModel({
    required this.forecast,
    required this.drivers,
    required this.recommendations,
  });

  final CashflowForecastModel forecast;
  final List<CashflowDriverModel> drivers;
  final List<CashflowRecommendationModel> recommendations;

  factory CashflowInsightsModel.fromJson(Map<String, dynamic> json) =>
      CashflowInsightsModel(
        forecast: CashflowForecastModel.fromJson(
          json['forecast'] as Map<String, dynamic>,
        ),
        drivers: (json['drivers'] as List)
            .map((e) => CashflowDriverModel.fromJson(e as Map<String, dynamic>))
            .toList(),
        recommendations: (json['recommendations'] as List)
            .map(
              (e) => CashflowRecommendationModel.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList(),
      );
}
