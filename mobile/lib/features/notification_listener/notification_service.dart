import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';

import '../../core/ai/ai_service.dart';
import '../../core/notifications/local_notification_service.dart';
import '../../core/providers/providers.dart';
import '../../data/models/models.dart';
import '../../data/repository.dart';
import 'notification_parser.dart';
import 'template_cache.dart';

/// Whitelist package ngân hàng/ví — chỉ thông báo từ các app này được xử lý,
/// mọi thông báo khác bị bỏ qua ngay (tiết kiệm tài nguyên + privacy).
const kBankPackageWhitelist = <String>{
  'com.VCB', // Vietcombank
  'com.mbmobile', // MB Bank
  'com.mservice.momotransfer', // MoMo
  'vn.com.vng.zalopay', // ZaloPay
  'com.zing.zalo', // Zalo (thông báo ZaloPay)
  'com.vietinbank.ipay', // VietinBank
  'com.tpb.mobilebanking', // TPBank
  'vn.com.techcombank.bb.app', // Techcombank
  'com.vnpay.bidv', // BIDV
  'com.vnpay.Agribank3g', // Agribank
  'com.acb.acbone', // ACB
  'com.vpbankonline.mobile', // VPBank
  'src.com.sacombank.ewallet', // Sacombank Pay
};

/// Notification Capture — parse & phân loại 100% on-device:
/// lớp 0 regex theo bank (template + generic), lớp 1 AI local qua AIProvider.
/// Nội dung thông báo không bao giờ rời khỏi máy — chỉ gửi field đã trích xuất.
class NotificationCaptureService {
  NotificationCaptureService(this._repo, this._ai);

  final AppRepository _repo;
  final AiService _ai;
  TemplateCache? _cache;
  StreamSubscription<ServiceNotificationEvent>? _sub;
  List<NotificationTemplateModel> _templates = [];
  List<LearnedNotificationPattern> _learnedPatterns = [];
  List<CategoryModel> _categories = [];
  final _processedKeys = <String>{};
  Future<void> _processingQueue = Future.value();
  bool _running = false;

  bool get isRunning => _running;

  Future<void> start() async {
    if (!Platform.isAndroid || _running) return;

    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) return;

    await _refreshTemplates();
    await LocalNotificationService.instance.showForegroundService();

    // Callback hệ thống cần trả về thật nhanh; parse được đưa vào queue nền.
    _sub = NotificationListenerService.notificationsStream.listen(_onNotification);
    _running = true;
    log('NotificationCaptureService started');
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _running = false;
  }

  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    return NotificationListenerService.requestPermission();
  }

  Future<bool> isPermissionGranted() async {
    if (!Platform.isAndroid) return false;
    return NotificationListenerService.isPermissionGranted();
  }

  Future<void> _refreshTemplates() async {
    _cache ??= await TemplateCache.create();
    try {
      _templates = await _repo.getNotificationTemplates();
      await _cache!.save(_templates);
    } catch (_) {
      _templates = _cache!.load();
    }
    _learnedPatterns = _cache!.loadLearned();
  }

  void _onNotification(ServiceNotificationEvent event) {
    _processingQueue = _processingQueue.then((_) => _handleNotification(event)).catchError((
      Object e,
      StackTrace st,
    ) {
      log('Notification processing error: $e', stackTrace: st);
    });
  }

  Future<void> _handleNotification(ServiceNotificationEvent event) async {
    if (event.hasRemoved == true) return;

    final packageName = event.packageName ?? '';
    // Lọc whitelist ngay từ đầu — thông báo ngoài danh sách bị bỏ qua hoàn toàn
    if (!kBankPackageWhitelist.contains(packageName) &&
        !_templates.any((t) => t.packageName == packageName) &&
        !_learnedPatterns.any((t) => t.packageName == packageName)) {
      return;
    }

    final text = _extractText(event);
    if (text.isEmpty) return;

    // Lớp 0 — regex theo bank (template server + learned cache + generic): nhanh, miễn phí
    ParsedNotification? parsed;
    LearnedNotificationPattern? learned;

    for (final tpl in _templates) {
      if (tpl.packageName != packageName) continue;
      parsed = parseNotificationText(text, tpl.regexPattern, packageName: packageName);
      if (parsed != null) break;
    }

    if (parsed == null) {
      for (final pattern in _learnedPatterns) {
        if (pattern.packageName != packageName) continue;
        parsed = parseNotificationText(text, pattern.regexPattern, packageName: packageName);
        if (parsed != null) {
          learned = pattern;
          break;
        }
      }
    }

    parsed ??= parseGenericAmount(text, packageName: packageName);

    double? amount;
    String? merchant;
    String? category;
    var parseTrack = 'regex';

    if (parsed != null) {
      if (parsed.sign == '+') return; // bỏ giao dịch tiền vào
      amount = parsed.amount;
      merchant = parsed.merchant;
      category = learned?.categoryHint;
      parseTrack = learned == null ? 'regex' : 'learned-regex';
    } else {
      // Lớp 1 — AI local qua AIProvider (fallback khi regex không khớp,
      // ví dụ bank đổi format thông báo)
      final aiParsed = await _ai.parseNotification(text);
      if (aiParsed == null || !aiParsed.isExpense) return;
      amount = aiParsed.amount;
      merchant = aiParsed.merchant;
      category = aiParsed.category;
      parseTrack = 'ai-fallback';
      await _learnPatternFromAi(
        text: text,
        packageName: packageName,
        amount: aiParsed.amount,
        merchant: aiParsed.merchant,
        category: aiParsed.category,
      );
    }

    final dedupKey = '${packageName}_${_normalizeText(text)}';
    if (_processedKeys.contains(dedupKey)) return;
    _processedKeys.add(dedupKey);
    if (_processedKeys.length > 400) {
      _processedKeys.remove(_processedKeys.first);
    }

    merchant ??= learned?.merchantHint;
    merchant ??= _packageLabel(packageName);
    // Phân loại on-device: cache merchant→category trước, AI sau
    category ??= await _ai.classifyMerchant(merchant);

    try {
      await _repo.createTransaction(
        amount: amount,
        merchantName: merchant,
        categoryId: await _categoryIdOf(category),
        source: 'notification',
        classificationReason: 'on-device notification parse ($parseTrack)',
      );
      log('Saved notification transaction: $amount from $packageName ($parseTrack)');
    } catch (e) {
      log('Failed to save notification transaction: $e');
    }
  }

  Future<void> _learnPatternFromAi({
    required String text,
    required String packageName,
    required double amount,
    String? merchant,
    String? category,
  }) async {
    final cache = _cache;
    if (cache == null) return;

    final regexPattern = _buildAmountPattern(text, amount: amount);
    if (regexPattern == null) return;

    final learned = LearnedNotificationPattern(
      packageName: packageName,
      regexPattern: regexPattern,
      merchantHint: merchant,
      categoryHint: category,
    );

    await cache.upsertLearned(learned);

    _learnedPatterns.removeWhere(
      (p) => p.packageName == learned.packageName && p.regexPattern == learned.regexPattern,
    );
    _learnedPatterns.insert(0, learned);
  }

  String? _buildAmountPattern(String text, {required double amount}) {
    final normalized = _normalizeText(text);
    if (normalized.isEmpty) return null;

    final candidates = RegExp(
      r'(?<sign>[+-])?\s*(?<amount>[\d][\d.,]{0,24})',
      caseSensitive: false,
    ).allMatches(normalized);

    RegExpMatch? selected;
    for (final match in candidates) {
      final rawAmount = match.namedGroup('amount');
      if (rawAmount == null) continue;
      final value = _parseAmount(rawAmount);
      if (value == null) continue;
      if ((value - amount).abs() <= 1) {
        selected = match;
        break;
      }
    }
    if (selected == null) return null;

    final matchedToken = normalized.substring(selected.start, selected.end);
    final escapedText = RegExp.escape(normalized);
    final escapedToken = RegExp.escape(matchedToken);
    if (!escapedText.contains(escapedToken)) return null;

    final withAmount = escapedText.replaceFirst(
      escapedToken,
      r'(?<sign>[+-])?\s*(?<amount>[\d.,]+)',
    );
    final withFlexibleSpace = withAmount.replaceAll(r'\ ', r'\s+');
    return '^${withFlexibleSpace}\$';
  }

  double? _parseAmount(String token) {
    final compact = token.replaceAll(RegExp(r'[^\d]'), '');
    return double.tryParse(compact);
  }

  String _normalizeText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<int?> _categoryIdOf(String? categoryName) async {
    if (categoryName == null) return null;
    if (_categories.isEmpty) {
      try {
        _categories = await _repo.getCategories();
      } catch (_) {
        return null;
      }
    }
    return _categories.where((c) => c.name == categoryName).firstOrNull?.id;
  }

  String _extractText(ServiceNotificationEvent event) {
    final parts = <String>[
      if (event.title != null) event.title!,
      if (event.content != null) event.content!,
    ];
    return parts.join(' ').trim();
  }

  String _packageLabel(String packageName) {
    const labels = {
      'com.VCB': 'Vietcombank',
      'com.mbmobile': 'MB Bank',
      'com.mservice.momotransfer': 'MoMo',
      'com.zing.zalo': 'ZaloPay',
      'com.vietinbank.ipay': 'VietinBank',
      'com.tpb.mobilebanking': 'TPBank',
    };
    return labels[packageName] ?? packageName.split('.').last;
  }
}

final notificationCaptureProvider = Provider<NotificationCaptureService>((ref) {
  return NotificationCaptureService(
    ref.watch(repositoryProvider),
    ref.watch(aiServiceProvider),
  );
});

/// Poll unread budget alerts and show local notifications.
class AlertPoller {
  AlertPoller(this._repo);

  final AppRepository _repo;
  Timer? _timer;
  final _seenAlertIds = <int>{};

  void start({Duration interval = const Duration(minutes: 5)}) {
    _timer?.cancel();
    _poll();
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    try {
      final alerts = await _repo.getAlerts(unreadOnly: true);
      for (final alert in alerts) {
        if (_seenAlertIds.contains(alert.id)) continue;
        _seenAlertIds.add(alert.id);

        final (title, body) = _alertMessage(alert);
        await LocalNotificationService.instance.showBudgetAlert(
          title: title,
          body: body,
          payload: alert.payload,
        );
      }
    } catch (_) {}
  }

  (String, String) _alertMessage(AlertModel alert) {
    final cat = alert.payload['category']?.toString() ?? '';
    final pct = alert.payload['percent']?.toString() ?? '';
    return switch (alert.type) {
      'budget_80' => ('⚠️ Sắp vượt ngân sách', '$cat: $pct% ngân sách'),
      'budget_100' => ('🚨 Vượt ngân sách', 'Đã dùng hết ngân sách $cat'),
      'budget_120' => ('🔴 Vượt nghiêm trọng', '$cat: $pct% ngân sách'),
      _ => ('Tuchi', 'Cảnh báo ngân sách'),
    };
  }
}

final alertPollerProvider = Provider<AlertPoller>((ref) {
  return AlertPoller(ref.watch(repositoryProvider));
});
