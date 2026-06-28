import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';

class SubscriptionsScreen extends ConsumerWidget {
  const SubscriptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subsAsync = ref.watch(subscriptionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Quét lại',
            onPressed: () async {
              ref.invalidate(subscriptionsProvider);
              await ref.read(repositoryProvider).detectSubscriptions();
              ref.invalidate(subscriptionsProvider);
            },
          ),
        ],
      ),
      body: subsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Lỗi: $e')),
        data: (subs) {
          if (subs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.subscriptions_outlined, size: 64, color: AppColors.onSurfaceMuted.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    const Text('Chưa phát hiện subscription nào', textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    Text(
                      'Netflix, Spotify, iCloud… sẽ được nhận diện tự động từ lịch sử giao dịch.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            );
          }

          final totalMonthly = subs.fold<double>(0, (sum, s) => sum + s.monthlyCost);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(subscriptionsProvider);
              await ref.read(subscriptionsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: AppColors.secondary.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Tổng chi phí/tháng', style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12)),
                              const SizedBox(height: 4),
                              Text(
                                formatVnd(totalMonthly),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${subs.length} subscription', style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12)),
                            const SizedBox(height: 4),
                            const Icon(Icons.autorenew),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...subs.map((sub) => _SubscriptionTile(sub: sub)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SubscriptionTile extends ConsumerWidget {
  const _SubscriptionTile({required this.sub});

  final SubscriptionModel sub;

  String _cycleLabel(int days) {
    if (days >= 350) return 'Hàng năm';
    if (days >= 25 && days <= 35) return 'Hàng tháng';
    if (days >= 6 && days <= 8) return 'Hàng tuần';
    return 'Mỗi $days ngày';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(sub.merchantName.isNotEmpty ? sub.merchantName[0].toUpperCase() : '?'),
        ),
        title: Text(sub.merchantName),
        subtitle: Text(
          '${_cycleLabel(sub.cycleDays)} · ${sub.occurrenceCount} lần · ${formatVnd(sub.amount)}/lần',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatVnd(sub.monthlyCost), style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('/tháng', style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 11)),
          ],
        ),
        onLongPress: () async {
          final dismiss = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Ẩn subscription?'),
              content: Text('${sub.merchantName} sẽ không hiện trong danh sách.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ẩn')),
              ],
            ),
          );
          if (dismiss == true) {
            await ref.read(repositoryProvider).dismissSubscription(sub.id);
            ref.invalidate(subscriptionsProvider);
          }
        },
      ),
    );
  }
}
