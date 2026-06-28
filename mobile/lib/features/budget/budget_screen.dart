import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen> {
  @override
  Widget build(BuildContext context) {
    final budgetsAsync = ref.watch(budgetsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return budgetsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Lỗi: $e')),
      data: (budgets) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(budgetsProvider);
            await ref.read(budgetsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Ngân sách tháng',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Theo dõi chi tiêu theo category — cảnh báo 80%/100%/120%',
                style: const TextStyle(color: AppColors.onSurfaceMuted),
              ),
              const SizedBox(height: 16),
              if (budgets.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text('Chưa có budget nào'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: categoriesAsync.valueOrNull == null
                              ? null
                              : () => _showAddBudget(context, categoriesAsync.value!),
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm budget'),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                ...budgets.map((b) => _BudgetCard(budget: b)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: categoriesAsync.valueOrNull == null
                      ? null
                      : () => _showAddBudget(context, categoriesAsync.value!),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm budget'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddBudget(BuildContext context, List<CategoryModel> categories) async {
    int? selectedCat = categories.isNotEmpty ? categories.first.id : null;
    final amountCtrl = TextEditingController(text: '1000000');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm budget'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: selectedCat,
              decoration: const InputDecoration(labelText: 'Category'),
              items: categories
                  .map<DropdownMenuItem<int>>((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => selectedCat = v,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Hạn mức (VND)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              if (selectedCat == null) return;
              await ref.read(repositoryProvider).createBudget(
                    categoryId: selectedCat!,
                    limitAmount: double.tryParse(amountCtrl.text.replaceAll('.', '')) ?? 0,
                  );
              ref.invalidate(budgetsProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.budget});

  final BudgetModel budget;

  @override
  Widget build(BuildContext context) {
    final pct = budget.percentUsed.clamp(0, 150);
    Color barColor = AppColors.secondary;
    if (pct >= 100) {
      barColor = AppColors.error;
    } else if (pct >= 80) {
      barColor = AppColors.warning;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(budget.categoryName ?? 'Category', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('${pct.toStringAsFixed(0)}%'),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0, 1),
                minHeight: 8,
                backgroundColor: AppColors.border,
                color: barColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatVnd(budget.spent)} / ${formatVnd(budget.limitAmount)}',
              style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
