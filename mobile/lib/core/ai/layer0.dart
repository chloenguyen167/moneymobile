/// Lớp 0 — regex/heuristic miễn phí, tức thời: bắt tổng tiền + ngày từ text OCR
/// và cache merchant→category. Chạy TRƯỚC mọi lời gọi AI, đồng thời dùng để
/// cross-check kết quả AI.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'receipt_models.dart';

class Layer0Result {
  Layer0Result({this.merchant, this.total, this.date});

  final String? merchant;
  final double? total;
  final DateTime? date;
}

final _amountRe = RegExp(r'(\d{1,3}(?:[.,]\d{3})+|\d{4,9})');
final _totalLineRe = RegExp(
  r'(tổng cộng|tổng tiền|tổng thanh toán|tong cong|tong tien|thành tiền|thanh tien|tổng hóa đơn|total|amount due|grand total|t\.cộng|phải thu|phai thu)',
  caseSensitive: false,
);

double? _parseAmount(String raw) {
  final digits = raw.replaceAll(RegExp(r'[.,\s]'), '');
  final value = double.tryParse(digits);
  if (value == null || value < 500 || value > 1000000000) return null;
  return value;
}

/// Bắt tổng tiền: ưu tiên dòng có từ khóa "tổng/total", fallback số lớn nhất.
double? parseTotalFromText(String text) {
  final lines = text.split('\n');
  double? keywordTotal;
  for (var i = 0; i < lines.length; i++) {
    if (!_totalLineRe.hasMatch(lines[i])) continue;
    // Số tiền có thể nằm cùng dòng hoặc dòng kế tiếp (OCR tách cột)
    for (final candidate in [lines[i], if (i + 1 < lines.length) lines[i + 1]]) {
      final amounts =
          _amountRe.allMatches(candidate).map((m) => _parseAmount(m.group(0)!)).nonNulls;
      if (amounts.isNotEmpty) {
        final v = amounts.reduce((a, b) => a > b ? a : b);
        if (keywordTotal == null || v > keywordTotal) keywordTotal = v;
      }
    }
  }
  if (keywordTotal != null) return keywordTotal;

  final all = _amountRe.allMatches(text).map((m) => _parseAmount(m.group(0)!)).nonNulls;
  if (all.isEmpty) return null;
  return all.reduce((a, b) => a > b ? a : b);
}

final _dateRes = [
  RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})'), // dd/mm/yyyy
  RegExp(r'(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})'), // yyyy-mm-dd
  RegExp(r'(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2})(?!\d)'), // dd/mm/yy
];

DateTime? parseDateFromText(String text) {
  for (var i = 0; i < _dateRes.length; i++) {
    final m = _dateRes[i].firstMatch(text);
    if (m == null) continue;
    int d, mo, y;
    if (i == 1) {
      y = int.parse(m.group(1)!);
      mo = int.parse(m.group(2)!);
      d = int.parse(m.group(3)!);
    } else {
      d = int.parse(m.group(1)!);
      mo = int.parse(m.group(2)!);
      y = int.parse(m.group(3)!);
      if (i == 2) y += 2000;
    }
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) continue;
    final date = DateTime(y, mo, d);
    if (date.isAfter(DateTime.now().add(const Duration(days: 1)))) continue;
    return date;
  }
  return null;
}

String? guessMerchantFromText(String text) {
  for (final line in text.split('\n')) {
    final t = line.trim();
    if (t.length < 3 || t.length > 50) continue;
    if (!RegExp(r'[a-zA-ZÀ-ỹ]').hasMatch(t)) continue;
    if (RegExp(r'(hóa đơn|hoa don|receipt|invoice|bill|phiếu|xin chào|welcome)',
            caseSensitive: false)
        .hasMatch(t)) {
      continue;
    }
    return t;
  }
  return null;
}

Layer0Result parseReceiptLayer0(String? ocrText) {
  if (ocrText == null || ocrText.trim().isEmpty) return Layer0Result();
  return Layer0Result(
    merchant: guessMerchantFromText(ocrText),
    total: parseTotalFromText(ocrText),
    date: parseDateFromText(ocrText),
  );
}

/// Cache merchant→category học từ lịch sử xác nhận của user.
/// Trúng cache thì khỏi gọi AI — nhanh, miễn phí và cá nhân hóa.
class MerchantCategoryCache {
  static const _key = 'merchant_category_cache_v1';

  static String normalize(String merchant) =>
      merchant.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  static Future<Map<String, String>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  static Future<String?> lookup(String? merchant) async {
    if (merchant == null || merchant.trim().isEmpty) return null;
    final map = await _load();
    final category = map[normalize(merchant)];
    return kDefaultCategories.contains(category) ? category : null;
  }

  static Future<void> save(String merchant, String category) async {
    if (merchant.trim().isEmpty || !kDefaultCategories.contains(category)) return;
    final map = await _load();
    map[normalize(merchant)] = category;
    // Giữ cache gọn
    while (map.length > 500) {
      map.remove(map.keys.first);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(map));
  }
}
