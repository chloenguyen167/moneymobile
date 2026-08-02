import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/providers.dart';
import '../data/models/models.dart';
import '../features/analytics/analytics_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/budget/budget_screen.dart';
import '../features/capture/capture_screen.dart';
import '../features/home/home_screen.dart';
import '../features/email/email_settings_screen.dart';
import '../features/notification_listener/notification_settings_screen.dart';
import '../features/quick_add/quick_add_screen.dart';
import '../features/subscriptions/subscriptions_screen.dart';
import '../features/transactions/transaction_detail_screen.dart';
import '../features/transactions/transaction_form_screen.dart';
import '../features/transactions/transactions_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final tokenAsync = ref.watch(authTokenProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      if (tokenAsync.isLoading) return null;
      final token = tokenAsync.valueOrNull;
      final loggingIn = state.matchedLocation == '/login';
      if (token == null && !loggingIn) return '/login';
      if (token != null && loggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(
        path: '/settings/notifications',
        builder: (_, _) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/email',
        builder: (_, _) => const EmailSettingsScreen(),
      ),
      GoRoute(path: '/quick-add', builder: (_, _) => const QuickAddScreen()),
      GoRoute(
        path: '/subscriptions',
        builder: (_, _) => const SubscriptionsScreen(),
      ),
      GoRoute(
        path: '/transactions/new',
        builder: (_, _) => const TransactionFormScreen(),
      ),
      GoRoute(
        path: '/transactions/:id/edit',
        builder: (_, state) {
          final id = int.parse(state.pathParameters['id']!);
          final tx = state.extra is TransactionModel
              ? state.extra as TransactionModel
              : null;
          return TransactionFormScreen(transactionId: id, transaction: tx);
        },
      ),
      GoRoute(
        path: '/transactions/:id',
        builder: (_, state) {
          final id = int.parse(state.pathParameters['id']!);
          final extra = state.extra;
          return TransactionDetailScreen(
            transactionId: id,
            initial: extra is TransactionModel ? extra : null,
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeScreen(shell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const TransactionsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/capture',
                builder: (_, _) => const CaptureScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/budget', builder: (_, _) => const BudgetScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/analytics',
                builder: (_, _) => const AnalyticsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
