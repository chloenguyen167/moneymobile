import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(analyticsProvider);
    final cashflowProfileAsync = ref.watch(cashflowProfileProvider);
    final alertsAsync = ref.watch(alertsProvider);
    final subsSummaryAsync = ref.watch(subscriptionsProvider);

    return analyticsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Lỗi: $e')),
      data: (summary) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(analyticsProvider);
            ref.invalidate(cashflowProfileProvider);
            ref.invalidate(cashflowInsightsProvider);
            ref.invalidate(alertsProvider);
            ref.invalidate(subscriptionsProvider);
            await ref.read(analyticsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Phân tích chi tiêu',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showCashflowSetupDialog(context, ref),
                    icon: const Icon(Icons.tune),
                    label: const Text('Số dư'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              cashflowProfileAsync.when(
                loading: () => const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (e, _) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Không tải được cấu hình số dư'),
                        const SizedBox(height: 8),
                        Text(
                          '$e',
                          style: const TextStyle(
                            color: AppColors.onSurfaceMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (profile) {
                  if (profile == null) {
                    return _CashflowSetupCard(
                      onSetup: () => _showCashflowSetupDialog(context, ref),
                    );
                  }
                  final insightsAsync = ref.watch(cashflowInsightsProvider);
                  return insightsAsync.when(
                    loading: () => const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                    error: (e, _) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Không tải được dự báo số dư',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$e',
                              style: const TextStyle(
                                color: AppColors.onSurfaceMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    data: (insights) => _CashflowInsightsSection(
                      profile: profile,
                      insights: insights,
                      onEdit: () => _showCashflowSetupDialog(
                        context,
                        ref,
                        initial: profile,
                      ),
                    ),
                  );
                },
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
                Text(
                  'Theo danh mục',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                          title: summary.totalSpent > 0
                              ? '${(amount / summary.totalSpent * 100).toStringAsFixed(0)}%'
                              : '0%',
                          color: colors[i % colors.length],
                          radius: 50,
                          titleStyle: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
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
                Text(
                  'Xu hướng theo ngày',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                            color: Theme.of(
                              context,
                            ).colorScheme.secondary.withValues(alpha: 0.1),
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
                    Text(
                      'Dự báo theo danh mục',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${summary.categoryForecasts.length} nhóm',
                      style: const TextStyle(
                        color: AppColors.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...summary.categoryForecasts.map((f) {
                  final forecast =
                      (f['forecast_amount'] as num?)?.toDouble() ?? 0;
                  final spent = (f['current_spent'] as num?)?.toDouble() ?? 0;
                  final onTrack = spent <= forecast;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        onTrack ? Icons.trending_flat : Icons.trending_up,
                        color: onTrack ? AppColors.success : AppColors.warning,
                      ),
                      title: Text(f['category_name'] as String? ?? ''),
                      subtitle: Text(
                        'Dựa trên ${f['historical_months'] ?? 0} tháng gần đây',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatVnd(spent),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '/ ${formatVnd(forecast)}',
                            style: const TextStyle(
                              color: AppColors.onSurfaceMuted,
                              fontSize: 11,
                            ),
                          ),
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
                  final total = subs.fold<double>(
                    0,
                    (s, x) => s + x.monthlyCost,
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Chi tiêu định kỳ',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          TextButton(
                            onPressed: () => context.push('/subscriptions'),
                            child: const Text('Xem tất cả'),
                          ),
                        ],
                      ),
                      Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.subscriptions,
                            color: AppColors.secondary,
                          ),
                          title: Text(
                            '${subs.length} khoản · ${formatVnd(total)}/tháng',
                          ),
                          subtitle: Text(
                            subs.take(3).map((s) => s.merchantName).join(', '),
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
                      Text(
                        'Cảnh báo',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      ...alerts.take(5).map((a) {
                        final friendly = _friendlyAlert(a);
                        return Card(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          child: ListTile(
                            leading: const Icon(
                              Icons.notifications_active,
                              color: AppColors.warning,
                            ),
                            title: Text(friendly.$1),
                            subtitle: Text(friendly.$2),
                          ),
                        );
                      }),
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

  Future<void> _showCashflowSetupDialog(
    BuildContext context,
    WidgetRef ref, {
    CashflowProfileModel? initial,
  }) async {
    final startingCtrl = TextEditingController(
      text: initial != null ? initial.startingBalance.round().toString() : '',
    );
    final incomeCtrl = TextEditingController(
      text: initial?.monthlyIncome != null
          ? initial!.monthlyIncome!.round().toString()
          : '',
    );
    String? errorText;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(
            initial == null ? 'Thiết lập số dư' : 'Cập nhật số dư',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: startingCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số dư đầu tháng',
                  hintText: 'Ví dụ: 5000000',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: incomeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Thu nhập tháng (không bắt buộc)',
                  hintText: 'Ví dụ: 12000000',
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 12),
                Text(
                  errorText!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final starting = double.tryParse(
                        startingCtrl.text.replaceAll('.', '').trim(),
                      );
                      final incomeText = incomeCtrl.text
                          .replaceAll('.', '')
                          .trim();
                      final income = incomeText.isEmpty
                          ? null
                          : double.tryParse(incomeText);

                      if (starting == null || starting < 0) {
                        setState(
                          () => errorText = 'Số dư đầu tháng không hợp lệ',
                        );
                        return;
                      }
                      if (incomeText.isNotEmpty &&
                          (income == null || income < 0)) {
                        setState(
                          () => errorText = 'Thu nhập tháng không hợp lệ',
                        );
                        return;
                      }

                      setState(() {
                        isSaving = true;
                        errorText = null;
                      });
                      try {
                        await ref
                            .read(repositoryProvider)
                            .saveCashflowProfile(
                              startingBalance: starting,
                              monthlyIncome: income,
                            );
                        ref.invalidate(cashflowProfileProvider);
                        ref.invalidate(cashflowInsightsProvider);
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setState(() {
                          isSaving = false;
                          errorText = e.toString();
                        });
                      }
                    },
              child: Text(isSaving ? 'Đang lưu...' : 'Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}

(String, String) _friendlyAlert(AlertModel a) {
  final payload = a.payload;
  final category = payload['category_name']?.toString() ??
      payload['category']?.toString();
  final percent = payload['percent_used'] ?? payload['percent'];
  final spent = payload['spent'];
  final limit = payload['limit_amount'] ?? payload['limit'];

  switch (a.type) {
    case 'budget_80':
      return (
        'Sắp hết ngân sách',
        category != null
            ? '$category đã dùng khoảng ${percent ?? 80}%'
            : 'Một danh mục đã dùng khoảng 80% hạn mức',
      );
    case 'budget_100':
      return (
        'Đã hết ngân sách',
        category != null
            ? '$category đã đạt hạn mức'
            : 'Một danh mục đã đạt hạn mức',
      );
    case 'budget_120':
      return (
        'Vượt ngân sách',
        category != null
            ? '$category đã vượt hạn mức'
            : 'Một danh mục đã vượt hạn mức',
      );
    default:
      if (category != null && spent != null && limit != null) {
        return (
          'Cảnh báo ngân sách',
          '$category: ${formatVnd(spent as num)} / ${formatVnd(limit as num)}',
        );
      }
      return ('Nhắc nhở', 'Kiểm tra chi tiêu của bạn');
  }
}

class _CashflowSetupCard extends StatelessWidget {
  const _CashflowSetupCard({required this.onSetup});

  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.zero,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.secondary,
                AppColors.secondary.withValues(alpha: 0.86),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Quản lý số dư',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Thiết lập số dư để biết bạn đang chi ổn hay tiêu quá nhanh.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Nhập số dư đầu tháng. Nếu có thêm thu nhập tháng, dự báo sẽ sát hơn.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.84),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _CashflowFeatureChip(label: 'Dự chi cuối tháng'),
                    _CashflowFeatureChip(label: 'Cảnh báo cạn tiền'),
                    _CashflowFeatureChip(label: 'Gợi ý cắt giảm'),
                  ],
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.secondary,
                  ),
                  onPressed: onSetup,
                  icon: const Icon(Icons.add_chart),
                  label: const Text('Bắt đầu thiết lập'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CashflowInsightsSection extends StatelessWidget {
  const _CashflowInsightsSection({
    required this.profile,
    required this.insights,
    required this.onEdit,
  });

  final CashflowProfileModel profile;
  final CashflowInsightsModel insights;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final forecast = insights.forecast;
    final hasIncome = profile.monthlyIncome != null;
    final availableBase =
        forecast.startingBalance + (forecast.monthlyIncome ?? 0);
    final remainingRatio = availableBase > 0
        ? (forecast.remainingBalance / availableBase).clamp(0.0, 1.0)
        : 0.0;
    final status = _cashflowStatus(
      forecast.projectedEndBalance,
      remainingRatio,
    );
    final statusColor = switch (status) {
      _CashflowStatus.stable => AppColors.success,
      _CashflowStatus.tight => AppColors.warning,
      _CashflowStatus.risky => AppColors.error,
    };
    final statusLabel = switch (status) {
      _CashflowStatus.stable => 'Ổn định',
      _CashflowStatus.tight => 'Cần siết chi',
      _CashflowStatus.risky => 'Rủi ro',
    };
    final statusMessage = switch (status) {
      _CashflowStatus.stable =>
        'Dòng tiền hiện tại vẫn đang trong vùng an toàn.',
      _CashflowStatus.tight =>
        'Bạn vẫn còn tiền, nhưng nhịp chi hiện tại đã bắt đầu căng.',
      _CashflowStatus.risky =>
        'Nếu giữ nhịp chi này, số dư cuối tháng có nguy cơ âm.',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: EdgeInsets.zero,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, statusColor.withValues(alpha: 0.08)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dự báo cashflow tháng ${forecast.month}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Sửa'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      statusMessage,
                      style: const TextStyle(
                        color: AppColors.onSurfaceMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.onSurface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Số dư cuối tháng dự kiến',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            formatVnd(forecast.projectedEndBalance),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 28,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            hasIncome
                                ? 'Tính từ số dư đầu tháng và thu nhập tháng bạn đã nhập.'
                                : 'Hiện chưa cộng thêm thu nhập tháng vì bạn chưa nhập.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.68),
                              height: 1.35,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nhịp tiêu tiền hiện tại',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: remainingRatio,
                        minHeight: 10,
                        backgroundColor: AppColors.border,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CashflowMetricTile(
                            label: 'Còn lại hôm nay',
                            value: formatVnd(forecast.remainingBalance),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CashflowMetricTile(
                            label: hasIncome
                                ? 'Thu nhập tháng'
                                : 'Burn rate/ngày',
                            value: hasIncome
                                ? formatVnd(profile.monthlyIncome!)
                                : formatVnd(forecast.dailyBurnRate),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _CashflowMetricTile(
                            label: 'Đã chi tháng này',
                            value: formatVnd(forecast.spentSoFar),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CashflowMetricTile(
                            label: 'Dự chi cuối tháng',
                            value: formatVnd(forecast.forecastEndOfMonthSpend),
                            emphasize: status != _CashflowStatus.stable,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            status == _CashflowStatus.risky
                                ? Icons.priority_high_rounded
                                : Icons.track_changes_rounded,
                            color: statusColor,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              hasIncome &&
                                      forecast.canPredictDepletionDate &&
                                      forecast.projectedEndBalance < 0
                                  ? 'Nếu giữ nhịp chi hiện tại, bạn có thể cạn tiền vào khoảng ${forecast.depletionDate}.'
                                  : 'Hiện chưa đủ dữ liệu để chốt ngày hết tiền. App đang ưu tiên hiển thị dự chi và mức độ an toàn.',
                              style: const TextStyle(height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (insights.drivers.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.speed_rounded, color: statusColor, size: 18),
              const SizedBox(width: 8),
              Text(
                'Nhóm chi đang vượt nhịp',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...insights.drivers.map(
            (driver) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            driver.categoryName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${driver.paceRatio.toStringAsFixed(2)}x an toàn',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (driver.paceRatio / 2).clamp(0.0, 1.0),
                        minHeight: 8,
                        backgroundColor: AppColors.border,
                        color: AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _CashflowMetricTile(
                            label: 'Đã chi',
                            value: formatVnd(driver.spentSoFar),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CashflowMetricTile(
                            label: 'Ngưỡng an toàn',
                            value: formatVnd(driver.safeAmount),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _CashflowMetricTile(
                            label: 'Vượt dự kiến',
                            value: formatVnd(driver.excessAmount),
                            emphasize: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (insights.recommendations.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              const Icon(
                Icons.content_cut_rounded,
                color: AppColors.secondary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Gợi ý cắt giảm',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...insights.recommendations.asMap().entries.map(
            (entry) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: entry.value.priority == 'high'
                          ? AppColors.warning.withValues(alpha: 0.12)
                          : AppColors.secondary.withValues(alpha: 0.08),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.72),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${entry.key + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.value.categoryName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        _PriorityPill(priority: entry.value.priority),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.value.message,
                          style: const TextStyle(height: 1.45),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _CashflowMetricTile(
                                label: 'Mức giảm đề xuất',
                                value: formatVnd(
                                  entry.value.suggestedCutAmount,
                                ),
                                emphasize: true,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _CashflowMetricTile(
                                label: 'Quy đổi',
                                value: entry.value.suggestedCutCount != null
                                    ? '${entry.value.suggestedCutCount} lần chi'
                                    : 'Theo tổng mức',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          entry.value.basis == 'median_ticket'
                              ? 'Ước lượng dựa trên cỡ chi tiêu trung vị của nhóm này.'
                              : 'Ước lượng dựa trên mức vượt so với ngưỡng an toàn.',
                          style: const TextStyle(
                            color: AppColors.onSurfaceMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

enum _CashflowStatus { stable, tight, risky }

_CashflowStatus _cashflowStatus(
  double projectedEndBalance,
  double remainingRatio,
) {
  if (projectedEndBalance < 0) return _CashflowStatus.risky;
  if (remainingRatio < 0.25) return _CashflowStatus.tight;
  return _CashflowStatus.stable;
}

class _CashflowFeatureChip extends StatelessWidget {
  const _CashflowFeatureChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _CashflowMetricTile extends StatelessWidget {
  const _CashflowMetricTile({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasize
              ? AppColors.warning.withValues(alpha: 0.24)
              : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.onSurfaceMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: emphasize ? AppColors.warning : AppColors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityPill extends StatelessWidget {
  const _PriorityPill({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final isHigh = priority == 'high';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isHigh
            ? AppColors.warning.withValues(alpha: 0.14)
            : AppColors.secondary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isHigh ? 'Ưu tiên cao' : 'Theo dõi',
        style: TextStyle(
          color: isHigh ? AppColors.warning : AppColors.secondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

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
            Text(
              title,
              style: const TextStyle(
                color: AppColors.onSurfaceMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
