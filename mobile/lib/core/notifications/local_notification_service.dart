import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();
  static final instance = LocalNotificationService._();

  static const foregroundNotificationId = 9999;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _id = 0;

  Future<void> init() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: ios,
    );
    await _plugin.initialize(settings);

    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      const budgetChannel = AndroidNotificationChannel(
        'tuchi_budget_alerts',
        'Cảnh báo ngân sách',
        description: 'Thông báo khi sắp vượt hoặc vượt ngân sách',
        importance: Importance.high,
      );
      const foregroundChannel = AndroidNotificationChannel(
        'tuchi_foreground',
        'Theo dõi giao dịch',
        description: 'Thông báo đang chạy khi bắt thông báo ngân hàng/ví',
        importance: Importance.low,
      );
      await androidPlugin?.createNotificationChannel(budgetChannel);
      await androidPlugin?.createNotificationChannel(foregroundChannel);
    }

    _initialized = true;
  }

  /// Runtime permission for posting local notifications (Android 13+ / iOS).
  Future<bool> requestNotificationPermission() async {
    await init();
    if (Platform.isAndroid) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await androidPlugin?.requestNotificationsPermission();
      return granted ?? true;
    }
    if (Platform.isIOS) {
      final iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final granted = await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? true;
    }
    return true;
  }

  Future<void> showBudgetAlert({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    await init();
    await requestNotificationPermission();
    _id++;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tuchi_budget_alerts',
        'Cảnh báo ngân sách',
        channelDescription: 'Thông báo khi sắp vượt hoặc vượt ngân sách',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(_id, title, body, details, payload: payload?.toString());
  }

  /// Android only — ongoing notification while capture is active.
  Future<void> showForegroundService() async {
    if (!Platform.isAndroid) return;
    await init();
    await requestNotificationPermission();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tuchi_foreground',
        'Theo dõi giao dịch',
        channelDescription: 'Thông báo đang chạy khi bắt thông báo ngân hàng/ví',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        icon: '@mipmap/ic_launcher',
      ),
    );
    await _plugin.show(
      foregroundNotificationId,
      'Tuchi',
      'Đang theo dõi thông báo giao dịch...',
      details,
    );
  }

  Future<void> cancelForegroundService() async {
    if (!Platform.isAndroid) return;
    await init();
    await _plugin.cancel(foregroundNotificationId);
  }
}
