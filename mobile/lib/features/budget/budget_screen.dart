import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
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
      error: (_, _) => const Center(
        child: Text(
          'Không tải được ngân sách.\nKéo xuống để thử lại.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.onSurfaceMuted),
        ),
      ),
      data: (budgets) {
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(budgetsProvider);
            await ref.read(budgetsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Ngân sách tháng',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Đặt hạn mức theo danh mục — app sẽ nhắc khi gần hết.',
                style: TextStyle(color: AppColors.onSurfaceMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              if (budgets.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 40,
                          color: AppColors.secondary,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Chưa có hạn mức nào',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ví dụ: Ăn uống 3.000.000 đ / tháng',
                          style: TextStyle(color: AppColors.onSurfaceMuted),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: categoriesAsync.valueOrNull == null
                              ? null
                              : () => _showAddBudget(
                                    context,
                                    categoriesAsync.value!,
                                  ),
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm hạn mức'),
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
                  label: const Text('Thêm hạn mức'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddBudget(
    BuildContext context,
    List<CategoryModel> categories,
  ) async {
    int? selectedCat = categories.isNotEmpty ? categories.first.id : null;
    final amountCtrl = TextEditingController(text: '1000000');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm hạn mức'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: selectedCat,
              decoration: const InputDecoration(labelText: 'Danh mục'),
              items: categories
                  .map(
                    (c) => DropdownMenuItem(value: c.id, child: Text(c.name)),
                  )
                  .toList(),
              onChanged: (v) => selectedCat = v,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Hạn mức',
                suffixText: 'đ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () async {
              if (selectedCat == null) return;
              await ref.read(repositoryProvider).createBudget(
                    categoryId: selectedCat!,
                    limitAmount:
                        parseVndInput(amountCtrl.text) ?? 0,
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
    String status = 'Còn dư';
    if (pct >= 100) {
      barColor = AppColors.error;
      status = 'Vượt hạn mức';
    } else if (pct >= 80) {
      barColor = AppColors.warning;
      status = 'Sắp hết';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    budget.categoryName ?? 'Danh mục',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: barColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (pct / 100).clamp(0, 1),
                minHeight: 10,
                backgroundColor: AppColors.border,
                color: barColor,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${formatVnd(budget.spent)} / ${formatVnd(budget.limitAmount)}',
              style: const TextStyle(
                color: AppColors.onSurfaceMuted,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
