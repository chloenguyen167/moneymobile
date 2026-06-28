import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../notification_listener/notification_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tuchi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Thêm nhanh',
            onPressed: () => context.push('/quick-add'),
          ),
          IconButton(
            icon: const Icon(Icons.subscriptions_outlined),
            tooltip: 'Subscription',
            onPressed: () => context.push('/subscriptions'),
          ),
          IconButton(
            icon: const Icon(Icons.email_outlined),
            tooltip: 'Email (iOS)',
            onPressed: () => context.push('/settings/email'),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Theo dõi giao dịch',
            onPressed: () => context.push('/settings/notifications'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(notificationCaptureProvider).stop();
              ref.read(alertPollerProvider).stop();
              await ref.read(repositoryProvider).logout();
              ref.invalidate(authTokenProvider);
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: shell.goBranch,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Giao dịch'),
          NavigationDestination(icon: Icon(Icons.camera_alt), label: 'Chụp HĐ'),
          NavigationDestination(icon: Icon(Icons.savings), label: 'Budget'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'Phân tích'),
        ],
      ),
    );
  }
}
