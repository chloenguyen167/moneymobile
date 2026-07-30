import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTx = ref.watch(transactionsProvider);
    final asyncCats = ref.watch(categoriesProvider);

    return asyncTx.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Lỗi: $e')),
      data: (transactions) {
        if (transactions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt, size: 64, color: AppColors.onSurfaceMuted.withValues(alpha: 0.5)),
                const SizedBox(height: 16),
                const Text('Chưa có giao dịch'),
                const SizedBox(height: 8),
                const Text('Chụp hóa đơn hoặc thêm thủ công', style: TextStyle(color: AppColors.onSurfaceMuted)),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(transactionsProvider);
            await ref.read(transactionsProvider.future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final tx = transactions[index];
              return _TransactionCard(
                transaction: tx,
                categories: asyncCats.valueOrNull ?? [],
                onConfirm: (catId) async {
                  await ref.read(repositoryProvider).confirmCategory(tx.id, catId);
                  ref.invalidate(transactionsProvider);
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.transaction,
    required this.categories,
    required this.onConfirm,
  });

  final TransactionModel transaction;
  final List<CategoryModel> categories;
  final ValueChanged<int> onConfirm;

  @override
  Widget build(BuildContext context) {
    final uploadedAtFmt = DateFormat('dd/MM/yyyy HH:mm');
    final needsConfirm = transaction.categoryName == null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/transactions/${transaction.id}', extra: transaction),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      transaction.merchantName ?? 'Không rõ merchant',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    ),
                  ),
                  Text(
                    formatVnd(transaction.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Gửi lúc ${uploadedAtFmt.format(transaction.createdAt)} · ${transaction.source}',
                style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 13),
              ),
              if (transaction.categoryName != null) ...[
                const SizedBox(height: 8),
                Chip(
                  label: Text(transaction.categoryName!),
                  visualDensity: VisualDensity.compact,
                ),
              ],
              if (transaction.classificationReason != null) ...[
                const SizedBox(height: 4),
                Text(
                  transaction.classificationReason!,
                  style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted, fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Chạm để xem chi tiết OCR',
                style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
              ),
              if (needsConfirm && categories.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Chọn category để xác nhận:', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categories.map((cat) {
                    return ActionChip(
                      label: Text(cat.name),
                      onPressed: () => onConfirm(cat.id),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
