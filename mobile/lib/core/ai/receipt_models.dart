/// Model kết quả xử lý on-device (OCR structuring + phân loại).
library;

/// Danh sách category hệ thống — khớp DEFAULT_CATEGORIES ở backend.
const kDefaultCategories = [
  'Ăn uống',
  'Mua sắm',
  'Di chuyển',
  'Giải trí',
  'Hóa đơn & Tiện ích',
  'Sức khỏe',
  'Giáo dục',
  'Khác',
];

class ReceiptItemData {
  ReceiptItemData({required this.name, this.qty = 1, this.price});

  final String name;
  final num qty;
  final num? price;

  Map<String, dynamic> toJson() => {
        'name': name,
        'qty': qty,
        if (price != null) 'price': price,
        if (price != null) 'line_total': (price! * qty),
      };

  static ReceiptItemData? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final name = raw['name']?.toString().trim();
    if (name == null || name.isEmpty) return null;
    return ReceiptItemData(
      name: name,
      qty: raw['qty'] is num ? raw['qty'] as num : num.tryParse('${raw['qty']}') ?? 1,
      price: raw['price'] is num ? raw['price'] as num : num.tryParse('${raw['price']}'),
    );
  }
}

/// Kết quả trích xuất hóa đơn — có thể do lớp 0 (regex), AI on-device hoặc cloud.
class ReceiptData {
  ReceiptData({
    this.merchant,
    this.total,
    this.date,
    this.items = const [],
    this.category,
    this.confidence = 0,
    this.needsReview = true,
    this.warnings = const [],
    required this.engine,
    this.rawText,
  });

  final String? merchant;
  final double? total;
  final DateTime? date;
  final List<ReceiptItemData> items;
  final String? category;
  final double confidence;

  /// true khi AI và regex lệch nhau hoặc thiếu trường quan trọng — user cần xác nhận.
  final bool needsReview;
  final List<String> warnings;

  /// 'layer0' | 'gemini-nano' | 'gemma-3n' | 'cloud'
  final String engine;
  final String? rawText;

  ReceiptData copyWith({
    String? merchant,
    double? total,
    DateTime? date,
    List<ReceiptItemData>? items,
    String? category,
    double? confidence,
    bool? needsReview,
    List<String>? warnings,
    String? engine,
    String? rawText,
  }) {
    return ReceiptData(
      merchant: merchant ?? this.merchant,
      total: total ?? this.total,
      date: date ?? this.date,
      items: items ?? this.items,
      category: category ?? this.category,
      confidence: confidence ?? this.confidence,
      needsReview: needsReview ?? this.needsReview,
      warnings: warnings ?? this.warnings,
      engine: engine ?? this.engine,
      rawText: rawText ?? this.rawText,
    );
  }
}

/// Kết quả AI parse thông báo ngân hàng/ví (fallback khi regex không khớp).
class AiParsedNotification {
  AiParsedNotification({
    required this.amount,
    this.isExpense = true,
    this.merchant,
    this.category,
  });

  final double amount;
  final bool isExpense;
  final String? merchant;
  final String? category;
}
