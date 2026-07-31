/// Prompt dùng chung cho mọi AIProvider (Nano / Gemma / Cloud) — trả JSON.
library;

import 'dart:convert';

import 'receipt_models.dart';

String get _categoryList => kDefaultCategories.map((c) => '"$c"').join(', ');

/// Trích xuất field + phân loại category trong 1 lần gọi (lớp 1).
String receiptPrompt({String? ocrText}) {
  final buf = StringBuffer()
    ..writeln('Bạn là công cụ đọc hóa đơn mua hàng Việt Nam.')
    ..writeln('Phân tích hóa đơn và trả về DUY NHẤT một JSON đúng cấu trúc sau, không giải thích:')
    ..writeln('{"merchant": string|null, "date": "YYYY-MM-DD"|null, "total": number|null, '
        '"items": [{"name": string, "qty": number, "price": number}], "category": string}')
    ..writeln('Quy tắc:')
    ..writeln('- "total" là tổng tiền phải trả, đơn vị VND, chỉ ghi số (ví dụ 125000).')
    ..writeln('- "category" chọn đúng 1 giá trị trong: [$_categoryList].')
    ..writeln('- Trường nào không đọc được thì để null. Tuyệt đối không bịa dữ liệu.');
  if (ocrText != null && ocrText.trim().isNotEmpty) {
    buf
      ..writeln()
      ..writeln('Văn bản OCR của hóa đơn:')
      ..writeln('"""')
      ..writeln(ocrText.trim())
      ..writeln('"""');
  }
  return buf.toString();
}

/// Phân loại riêng (khi đã có merchant nhưng chưa có category).
String classifyPrompt(String merchant, {String? hint}) {
  return 'Cửa hàng/giao dịch: "$merchant"'
      '${hint != null && hint.isNotEmpty ? ' — chi tiết: $hint' : ''}.\n'
      'Chọn category chi tiêu phù hợp nhất trong: [$_categoryList].\n'
      'Trả về DUY NHẤT JSON: {"category": string}';
}

/// Parse thông báo giao dịch ngân hàng/ví điện tử (lớp 1 của tính năng 4).
String notificationPrompt(String text) {
  return 'Phân tích thông báo giao dịch ngân hàng/ví điện tử Việt Nam sau.\n'
      'Trả về DUY NHẤT JSON: {"amount": number|null, "type": "expense"|"income", '
      '"merchant": string|null, "category": string|null}\n'
      '- "amount" là số tiền giao dịch (VND, chỉ số).\n'
      '- "type": "expense" nếu tiền bị trừ, "income" nếu tiền được cộng.\n'
      '- "category" chọn trong [$_categoryList] hoặc null.\n'
      'Thông báo: """$text"""';
}

/// Sinh insight từ số liệu ĐÃ tính sẵn — model không được tự tính/bịa số.
String insightPrompt(Map<String, dynamic> stats) {
  return 'Bạn là trợ lý tài chính cá nhân nói tiếng Việt.\n'
      'Dưới đây là số liệu chi tiêu đã được tính toán chính xác từ trước (JSON). '
      'CHỈ được diễn giải và đưa gợi ý dựa trên các con số này, '
      'tuyệt đối không tự tính toán hay đưa ra con số mới.\n'
      'Viết 2-3 nhận xét/gợi ý ngắn gọn, thân thiện, mỗi ý một dòng bắt đầu bằng "- ".\n'
      'Số liệu: ${jsonEncode(stats)}';
}

/// Tách JSON object đầu tiên từ output của model (bỏ ```json fence, text thừa).
Map<String, dynamic>? extractJsonMap(String raw) {
  var text = raw.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', multiLine: true).firstMatch(text);
  if (fence != null) text = fence.group(1)!.trim();

  final start = text.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  for (var i = start; i < text.length; i++) {
    if (text[i] == '{') depth++;
    if (text[i] == '}') {
      depth--;
      if (depth == 0) {
        try {
          final decoded = jsonDecode(text.substring(start, i + 1));
          return decoded is Map<String, dynamic> ? decoded : null;
        } catch (_) {
          return null;
        }
      }
    }
  }
  return null;
}
