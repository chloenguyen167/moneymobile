import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  LocalNotificationService._();
  static final instance = LocalNotificationService._();

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
      const channel = AndroidNotificationChannel(
        'tuchi_budget_alerts',
        'Cảnh báo ngân sách',
        description: 'Thông báo khi sắp vượt hoặc vượt ngân sách',
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }

    _initialized = true;
  }

  Future<void> showBudgetAlert({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    await init();
    _id++;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tuchi_budget_alerts',
        'Cảnh báo ngân sách',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(),
    );
    await _plugin.show(_id, title, body, details, payload: payload?.toString());
  }

  /// Android only — foreground notification listener service.
  Future<void> showForegroundService() async {
    if (!Platform.isAndroid) return;
    await init();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tuchi_foreground',
        'Theo dõi giao dịch',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        icon: '@mipmap/ic_launcher',
      ),
    );
    await _plugin.show(9999, 'Tuchi', 'Đang theo dõi thông báo giao dịch...', details);
  }
}
