/// Abstraction layer AIProvider — mọi use case (OCR/category, insight, parse
/// thông báo) gọi qua interface này, không gọi thẳng SDK cụ thể.
/// 3 implementation: ML Kit GenAI (Gemini Nano), LiteRT-LM (Gemma 3n), Cloud API.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_channel.dart';
import 'ai_settings.dart';
import 'prompts.dart';
import 'receipt_models.dart';

abstract class AIProvider {
  String get id;
  String get label;

  /// Provider có ăn được ảnh trực tiếp không (multimodal).
  bool get supportsVision;

  Future<bool> isAvailable();

  /// Lời gọi model thô — subclass chỉ cần implement hàm này.
  Future<String> generate(String prompt, {String? imagePath});

  // ---- Use case dùng chung (implement sẵn bên dưới) ----

  Future<ReceiptData?> extractReceipt({required String imagePath, String? ocrText}) async {
    final prompt = receiptPrompt(ocrText: ocrText);
    final raw = await generate(prompt, imagePath: supportsVision ? imagePath : null);
    final json = extractJsonMap(raw);
    if (json == null) return null;

    final items = (json['items'] is List)
        ? (json['items'] as List).map(ReceiptItemData.tryParse).nonNulls.toList()
        : <ReceiptItemData>[];
    final category = json['category']?.toString();
    DateTime? date;
    if (json['date'] != null) date = DateTime.tryParse(json['date'].toString());

    return ReceiptData(
      merchant: _cleanString(json['merchant']),
      total: _toDouble(json['total']),
      date: date,
      items: items,
      category: kDefaultCategories.contains(category) ? category : null,
      confidence: 0.8,
      needsReview: false,
      engine: id,
      rawText: ocrText,
    );
  }

  Future<String?> classifyCategory(String merchant, {String? hint}) async {
    final raw = await generate(classifyPrompt(merchant, hint: hint));
    final category = extractJsonMap(raw)?['category']?.toString();
    return kDefaultCategories.contains(category) ? category : null;
  }

  Future<String> generateInsight(Map<String, dynamic> stats) async {
    return (await generate(insightPrompt(stats))).trim();
  }

  Future<AiParsedNotification?> parseNotification(String text) async {
    final raw = await generate(notificationPrompt(text));
    final json = extractJsonMap(raw);
    final amount = _toDouble(json?['amount']);
    if (json == null || amount == null || amount <= 0) return null;
    final category = json['category']?.toString();
    return AiParsedNotification(
      amount: amount,
      isExpense: json['type']?.toString() != 'income',
      merchant: _cleanString(json['merchant']),
      category: kDefaultCategories.contains(category) ? category : null,
    );
  }

  static String? _cleanString(dynamic v) {
    final s = v?.toString().trim();
    if (s == null || s.isEmpty || s == 'null') return null;
    return s;
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v');
  }
}

/// Lớp 1 chính: Gemini Nano on-device qua ML Kit GenAI Prompt API (AICore).
class MlKitNanoProvider extends AIProvider {
  @override
  String get id => 'gemini-nano';

  @override
  String get label => 'Gemini Nano (on-device)';

  @override
  bool get supportsVision => true;

  @override
  Future<bool> isAvailable() async => await AiNative.nanoStatus() == 'available';

  @override
  Future<String> generate(String prompt, {String? imagePath}) =>
      AiNative.nanoGenerate(prompt, imagePath: imagePath);
}

/// Lớp 2 fallback: Gemma 3n qua LiteRT-LM (thiết bị không hỗ trợ AICore).
class GemmaProvider extends AIProvider {
  GemmaProvider(this.modelPath);

  final String modelPath;

  @override
  String get id => 'gemma-3n';

  @override
  String get label => 'Gemma 3n (on-device)';

  @override
  bool get supportsVision => true;

  @override
  Future<bool> isAvailable() => AiNative.gemmaAvailable(modelPath);

  @override
  Future<String> generate(String prompt, {String? imagePath}) =>
      AiNative.gemmaGenerate(prompt, imagePath: imagePath, modelPath: modelPath);
}

/// Fallback cuối: Cloud API (Gemini) — cần API key, dữ liệu rời máy.
class CloudGeminiProvider extends AIProvider {
  CloudGeminiProvider({required this.apiKey, required this.model});

  final String apiKey;
  final String model;

  @override
  String get id => 'cloud';

  @override
  String get label => 'Cloud API (Gemini)';

  @override
  bool get supportsVision => true;

  @override
  Future<bool> isAvailable() async => apiKey.isNotEmpty;

  @override
  Future<String> generate(String prompt, {String? imagePath}) async {
    final parts = <Map<String, dynamic>>[
      if (imagePath != null)
        {
          'inline_data': {
            'mime_type': _mimeType(imagePath),
            'data': base64Encode(await File(imagePath).readAsBytes()),
          },
        },
      {'text': prompt},
    ];

    final resp = await http
        .post(
          Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
          ),
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: jsonEncode({
            'contents': [
              {'parts': parts},
            ],
            'generationConfig': {'temperature': 0.1},
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (resp.statusCode >= 400) {
      throw Exception('Cloud API lỗi ${resp.statusCode}: ${resp.body}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = body['candidates'] as List?;
    final parts0 =
        ((candidates?.firstOrNull as Map?)?['content'] as Map?)?['parts'] as List?;
    final text = (parts0?.firstOrNull as Map?)?['text']?.toString();
    if (text == null) throw Exception('Cloud API không trả text');
    return text;
  }

  static String _mimeType(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}

/// Tạo danh sách provider theo config, đúng thứ tự ưu tiên của mode.
Future<List<AIProvider>> buildProviders(AiSettings settings) async {
  final gemmaPath = await AiSettings.gemmaModelPath();
  final nano = MlKitNanoProvider();
  final gemma = GemmaProvider(gemmaPath);
  final cloud = CloudGeminiProvider(
    apiKey: settings.cloudApiKey,
    model: settings.cloudModel,
  );

  return switch (settings.mode) {
    AiEngineMode.auto => [nano, gemma, cloud],
    AiEngineMode.nano => [nano],
    AiEngineMode.gemma => [gemma],
    AiEngineMode.cloud => [cloud],
  };
}
