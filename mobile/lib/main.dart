import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'core/config/app_config.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/notification_listener/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  await LocalNotificationService.instance.init();
  runApp(const ProviderScope(child: TuchiApp()));
}

class TuchiApp extends ConsumerStatefulWidget {
  const TuchiApp({super.key});

  @override
  ConsumerState<TuchiApp> createState() => _TuchiAppState();
}

class _TuchiAppState extends ConsumerState<TuchiApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPhase2Services());
  }

  Future<void> _initPhase2Services() async {
    if (Platform.isAndroid) {
      await LocalNotificationService.instance.requestPostNotificationsPermission();
      final capture = ref.read(notificationCaptureProvider);
      final granted = await capture.isPermissionGranted();
      final enabled = await capture.isEnabled();
      if (granted && enabled) {
        await capture.start();
      }
    }
    ref.read(alertPollerProvider).start();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Tuchi',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
