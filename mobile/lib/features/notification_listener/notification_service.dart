import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/notifications/local_notification_service.dart';
import '../../core/providers/providers.dart';
import '../../data/models/models.dart';
import '../../data/remote/tuchi_repository.dart';
import 'notification_parser.dart';
import 'template_cache.dart';

/// Package labels aligned with backend `DEFAULT_TEMPLATES`.
const supportedNotificationPackages = <String, String>{
  'com.VCB': 'Vietcombank',
  'com.mbmobile': 'MB Bank',
  'com.mservice.momotransfer': 'MoMo',
  'com.vietinbank.ipay': 'VietinBank',
  'com.tpb.mobilebanking': 'TPBank',
  'vn.com.techcombank.bb.app': 'Techcombank',
};

/// Phase 2: Android Notification Capture — on-device parse, structured fields only to server.
class NotificationCaptureService {
  NotificationCaptureService(this._repo);

  static const enabledPrefsKey = 'notification_capture_enabled';

  final TuchiRepository _repo;
  TemplateCache? _cache;
  StreamSubscription<ServiceNotificationEvent>? _sub;
  List<NotificationTemplateModel> _templates = [];
  final _processedKeys = <String>{};
  bool _running = false;

  bool get isRunning => _running;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledPrefsKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledPrefsKey, enabled);
  }

  Future<void> start() async {
    if (!Platform.isAndroid || _running) return;

    final granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) return;

    await setEnabled(true);
    await _refreshTemplates();
    await LocalNotificationService.instance.showForegroundService();

    _sub = NotificationListenerService.notificationsStream.listen(_onNotification);
    _running = true;
    log('NotificationCaptureService started');
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _running = false;
    await setEnabled(false);
    await LocalNotificationService.instance.cancelForegroundService();
    log('NotificationCaptureService stopped');
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
  }

  Future<void> _onNotification(ServiceNotificationEvent event) async {
    if (event.hasRemoved == true) return;

    final packageName = event.packageName ?? '';
    final text = _extractText(event);
    if (text.isEmpty) return;

    // Only parse on-device — never upload raw notification text
    ParsedNotification? parsed;
    for (final tpl in _templates) {
      if (tpl.packageName != packageName) continue;
      parsed = parseNotificationText(text, tpl.regexPattern, packageName: packageName);
      if (parsed != null) break;
    }
    parsed ??= parseGenericAmount(text, packageName: packageName);
    if (parsed == null) return;

    // Skip income transactions
    if (parsed.sign == '+') return;

    final dedupKey = '${packageName}_${parsed.amount}_${DateTime.now().hour}';
    if (_processedKeys.contains(dedupKey)) return;
    _processedKeys.add(dedupKey);
    if (_processedKeys.length > 200) {
      _processedKeys.remove(_processedKeys.first);
    }

    try {
      await _repo.ingestNotification(
        packageName: packageName,
        amount: parsed.amount,
        merchant: parsed.merchant ?? _packageLabel(packageName),
      );
      log('Ingested notification: ${parsed.amount} from $packageName');
    } catch (e) {
      log('Failed to ingest notification: $e');
    }
  }

  String _extractText(ServiceNotificationEvent event) {
    final parts = <String>[
      if (event.title != null) event.title!,
      if (event.content != null) event.content!,
    ];
    return parts.join(' ').trim();
  }

  String _packageLabel(String packageName) {
    return supportedNotificationPackages[packageName] ?? packageName.split('.').last;
  }
}

final notificationCaptureProvider = Provider<NotificationCaptureService>((ref) {
  return NotificationCaptureService(ref.watch(repositoryProvider));
});

/// Poll unread budget alerts and show local notifications.
class AlertPoller {
  AlertPoller(this._repo);

  final TuchiRepository _repo;
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
