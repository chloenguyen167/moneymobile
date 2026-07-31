/// Orchestrator: lớp 0 (regex + cache) → AIProvider (Nano → Gemma → Cloud)
/// → validate/cross-check. Toàn bộ OCR structuring + phân loại chạy tại đây,
/// backend chỉ còn nhiệm vụ lưu trữ.
library;

import 'dart:developer';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_channel.dart';
import 'ai_provider.dart';
import 'ai_settings.dart';
import 'layer0.dart';
import 'receipt_models.dart';

class AiService {
  /// Provider khả dụng đầu tiên theo thứ tự ưu tiên của config.
  Future<AIProvider?> resolveProvider() async {
    final settings = await AiSettings.load();
    for (final provider in await buildProviders(settings)) {
      try {
        if (await provider.isAvailable()) return provider;
      } catch (_) {}
    }
    return null;
  }

  /// Trạng thái từng provider — cho màn hình Settings.
  Future<List<(AIProvider, bool)>> providerStatuses() async {
    final settings = await AiSettings.load();
    final all = await buildProviders(
      AiSettings(
        mode: AiEngineMode.auto,
        cloudApiKey: settings.cloudApiKey,
        cloudModel: settings.cloudModel,
        gemmaModelUrl: settings.gemmaModelUrl,
        hfToken: settings.hfToken,
      ),
    );
    final result = <(AIProvider, bool)>[];
    for (final p in all) {
      var ok = false;
      try {
        ok = await p.isAvailable();
      } catch (_) {}
      result.add((p, ok));
    }
    return result;
  }

  /// Pipeline hóa đơn: OCR text → lớp 0 → AI → cross-check.
  Future<ReceiptData> processReceipt(String imagePath) async {
    final ocrText = await AiNative.ocrText(imagePath);
    final layer0 = parseReceiptLayer0(ocrText);
    final cachedCategory = await MerchantCategoryCache.lookup(layer0.merchant);

    // Fast path: lớp 0 đủ trường quan trọng + merchant đã có trong cache
    if (layer0.total != null && layer0.date != null && cachedCategory != null) {
      return ReceiptData(
        merchant: layer0.merchant,
        total: layer0.total,
        date: layer0.date,
        category: cachedCategory,
        confidence: 0.9,
        needsReview: false,
        engine: 'layer0',
        rawText: ocrText,
      );
    }

    final provider = await resolveProvider();
    if (provider == null) {
      // Không có AI engine nào — trả kết quả lớp 0 để user tự sửa
      return ReceiptData(
        merchant: layer0.merchant,
        total: layer0.total,
        date: layer0.date,
        category: cachedCategory,
        confidence: layer0.total != null ? 0.4 : 0.1,
        needsReview: true,
        warnings: const ['Chưa có AI engine khả dụng — kiểm tra Cài đặt AI'],
        engine: 'layer0',
        rawText: ocrText,
      );
    }

    ReceiptData? ai;
    try {
      ai = await provider.extractReceipt(imagePath: imagePath, ocrText: ocrText);
    } catch (e) {
      log('extractReceipt failed on ${provider.id}: $e');
    }

    if (ai == null) {
      return ReceiptData(
        merchant: layer0.merchant,
        total: layer0.total,
        date: layer0.date,
        category: cachedCategory,
        confidence: 0.3,
        needsReview: true,
        warnings: ['AI (${provider.label}) không đọc được hóa đơn'],
        engine: provider.id,
        rawText: ocrText,
      );
    }

    // Cross-check AI với lớp 0: lệch nhiều → flag cho user xác nhận
    final warnings = <String>[];
    var needsReview = false;
    var total = ai.total ?? layer0.total;
    if (ai.total != null && layer0.total != null) {
      final diff = (ai.total! - layer0.total!).abs();
      if (diff > layer0.total! * 0.01) {
        warnings.add(
          'Tổng tiền AI đọc khác với số trên hóa đơn — vui lòng kiểm tra lại',
        );
        needsReview = true;
        total = layer0.total; // tin regex hơn với con số
      }
    }
    if (total == null) {
      warnings.add('Không đọc được tổng tiền');
      needsReview = true;
    }

    // Cache từ lịch sử user được ưu tiên hơn AI
    final category = cachedCategory ?? ai.category;
    if (category == null) needsReview = true;

    return ReceiptData(
      merchant: ai.merchant ?? layer0.merchant,
      total: total,
      date: ai.date ?? layer0.date,
      items: ai.items,
      category: category,
      confidence: needsReview ? 0.5 : 0.85,
      needsReview: needsReview,
      warnings: warnings,
      engine: provider.id,
      rawText: ocrText,
    );
  }

  /// AI fallback cho thông báo ngân hàng khi regex (lớp 0) không khớp.
  Future<AiParsedNotification?> parseNotification(String text) async {
    final provider = await resolveProvider();
    if (provider == null) return null;
    try {
      return await provider.parseNotification(text);
    } catch (e) {
      log('parseNotification failed on ${provider.id}: $e');
      return null;
    }
  }

  /// Phân loại merchant: cache trước, AI sau.
  Future<String?> classifyMerchant(String merchant, {String? hint}) async {
    final cached = await MerchantCategoryCache.lookup(merchant);
    if (cached != null) return cached;
    final provider = await resolveProvider();
    if (provider == null) return null;
    try {
      return await provider.classifyCategory(merchant, hint: hint);
    } catch (e) {
      log('classifyMerchant failed: $e');
      return null;
    }
  }

  /// Diễn giải số liệu (đã tính rule-based) thành gợi ý cá nhân hóa.
  Future<String?> generateInsight(Map<String, dynamic> stats) async {
    final provider = await resolveProvider();
    if (provider == null) return null;
    try {
      return await provider.generateInsight(stats);
    } catch (e) {
      log('generateInsight failed: $e');
      return null;
    }
  }

  /// Học từ xác nhận của user — lần sau trúng cache, khỏi gọi AI.
  Future<void> learnMerchant(String? merchant, String? category) async {
    if (merchant == null || category == null) return;
    await MerchantCategoryCache.save(merchant, category);
  }
}

final aiServiceProvider = Provider<AiService>((_) => AiService());
