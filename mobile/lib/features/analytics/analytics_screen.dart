import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider);
    final alertsAsync = ref.watch(alertsProvider);
    final pipelineAsync = ref.watch(pipelineHealthProvider);
    final subsSummaryAsync = ref.watch(subscriptionsProvider);

    return analyticsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Lỗi: $e')),
      data: (summary) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(analyticsProvider);
            ref.invalidate(alertsProvider);
            ref.invalidate(pipelineHealthProvider);
            ref.invalidate(subscriptionsProvider);
            await ref.read(analyticsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Phân tích chi tiêu',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      title: 'Đã chi tháng này',
                      value: formatVnd(summary.totalSpent),
                      icon: Icons.payments,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: 'Dự báo cuối tháng',
                      value: formatVnd(summary.forecastEndOfMonth),
                      icon: Icons.trending_up,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (summary.byCategory.isNotEmpty) ...[
                Text('Theo category', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 200,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: summary.byCategory.asMap().entries.map((entry) {
                        final i = entry.key;
                        final item = entry.value;
                        final amount = (item['amount'] as num).toDouble();
                        final colors = AppColors.chartPalette;
                        return PieChartSectionData(
                          value: amount,
                          title: '${(amount / summary.totalSpent * 100).toStringAsFixed(0)}%',
                          color: colors[i % colors.length],
                          radius: 50,
                          titleStyle: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...summary.byCategory.map((item) {
                  return ListTile(
                    dense: true,
                    title: Text(item['category'] as String),
                    trailing: Text(formatVnd(item['amount'] as num)),
                  );
                }),
              ],
              if (summary.dailyTrend.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Xu hướng theo ngày', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: summary.dailyTrend.asMap().entries.map((e) {
                            return FlSpot(
                              e.key.toDouble(),
                              (e.value['amount'] as num).toDouble(),
                            );
                          }).toList(),
                          isCurved: true,
                          color: Theme.of(context).colorScheme.secondary,
                          barWidth: 3,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (summary.categoryForecasts.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Dự báo theo category (Holt-Winters)', style: Theme.of(context).textTheme.titleMedium),
                    Text('${summary.categoryForecasts.length} category', style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 8),
                ...summary.categoryForecasts.map((f) {
                  final forecast = (f['forecast_amount'] as num?)?.toDouble() ?? 0;
                  final spent = (f['current_spent'] as num?)?.toDouble() ?? 0;
                  final pct = forecast > 0 ? (spent / forecast * 100).clamp(0, 150) : 0;
                  final onTrack = spent <= forecast;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        onTrack ? Icons.trending_flat : Icons.trending_up,
                        color: onTrack ? AppColors.success : AppColors.warning,
                      ),
                      title: Text(f['category_name'] as String? ?? ''),
                      subtitle: Text('${f['method'] ?? 'forecast'} · ${f['historical_months'] ?? 0} tháng dữ liệu'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatVnd(spent), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          Text('/ ${formatVnd(forecast)}', style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 11)),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              subsSummaryAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (subs) {
                  if (subs.isEmpty) return const SizedBox.shrink();
                  final total = subs.fold<double>(0, (s, x) => s + x.monthlyCost);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Subscription đang active', style: Theme.of(context).textTheme.titleMedium),
                          TextButton(onPressed: () => context.push('/subscriptions'), child: const Text('Xem tất cả')),
                        ],
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.subscriptions, color: AppColors.secondary),
                          title: Text('${subs.length} subscription · ${formatVnd(total)}/tháng'),
                          subtitle: Text(subs.take(3).map((s) => s.merchantName).join(', ')),
                        ),
                      ),
                    ],
                  );
                },
              ),
              pipelineAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (health) {
                  if (health.ocrTotal == 0 && health.classifyTotal == 0) return const SizedBox.shrink();
                  final isWarning = health.status == 'warning';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Text('Pipeline health (${health.periodDays} ngày)', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Card(
                        color: isWarning ? AppColors.primary.withValues(alpha: 0.15) : null,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    isWarning ? Icons.warning_amber : Icons.check_circle,
                                    color: isWarning ? AppColors.warning : AppColors.success,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    isWarning ? 'Cần tối ưu GPU' : 'Ổn định',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'OCR smart track: ${health.ocrSmartTrackPct.toStringAsFixed(1)}% · '
                                'Classify LLM: ${health.classifySmartTrackPct.toStringAsFixed(1)}% · '
                                'Mục tiêu ≤ ${health.targetSmartTrackPct.toStringAsFixed(0)}%',
                                style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
                              ),
                              if (health.recommendations.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ...health.recommendations.map(
                                  (r) => Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text('• $r', style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              alertsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
                data: (alerts) {
                  if (alerts.isEmpty) return const SizedBox.shrink();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Text('Cảnh báo', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ...alerts.take(5).map((a) => Card(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            child: ListTile(
                              leading: const Icon(Icons.notifications_active, color: AppColors.warning),
                              title: Text(a.type),
                              subtitle: Text(a.payload.toString()),
                            ),
                          )),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, required this.icon});

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.secondary),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
