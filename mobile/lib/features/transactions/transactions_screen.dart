import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncTx = ref.watch(transactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/transactions/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Thêm'),
      ),
      body: asyncTx.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const _ErrorState(),
        data: (transactions) {
          if (transactions.isEmpty) {
            return _EmptyState(
              onAdd: () => context.push('/transactions/new'),
              onCapture: () => context.go('/capture'),
            );
          }

          final monthExpense = _monthTotal(transactions, income: false);
          final monthIncome = _monthTotal(transactions, income: true);
          final groups = _groupByDate(transactions);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(transactionsProvider);
              await ref.read(transactionsProvider.future);
            },
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: _MonthSummary(
                    expense: monthExpense,
                    income: monthIncome,
                    count: transactions
                        .where((t) => _isThisMonth(t.transactionDate))
                        .length,
                  ),
                ),
                ...groups.expand((group) {
                  return [
                    SliverToBoxAdapter(
                      child: _DateHeader(
                        date: group.date,
                        dayTotal: group.dayTotal,
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final tx = group.items[index];
                          return _TransactionTile(
                            transaction: tx,
                            onTap: () => context.push(
                              '/transactions/${tx.id}',
                              extra: tx,
                            ),
                            onConfirm: tx.categoryId == null
                                ? () => _showCategoryPicker(context, ref, tx)
                                : null,
                          );
                        },
                        childCount: group.items.length,
                      ),
                    ),
                  ];
                }),
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showCategoryPicker(
    BuildContext context,
    WidgetRef ref,
    TransactionModel tx,
  ) async {
    final cats = ref.read(categoriesProvider).valueOrNull ?? [];
    if (cats.isEmpty) return;

    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Chọn danh mục',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: cats.length,
                itemBuilder: (_, i) {
                  final cat = cats[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.secondary.withValues(
                        alpha: 0.12,
                      ),
                      child: Icon(
                        categoryIconFor(cat.name),
                        color: AppColors.secondary,
                        size: 20,
                      ),
                    ),
                    title: Text(cat.name),
                    onTap: () => Navigator.pop(ctx, cat.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null) return;
    await ref.read(repositoryProvider).confirmCategory(tx.id, selected);
    invalidateTransactionRelated(ref);
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({
    required this.expense,
    required this.income,
    required this.count,
  });

  final double expense;
  final double income;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.secondary, Color(0xFF3E7CAA)],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tháng ${formatMonthYear(DateTime.now())}',
            style: const TextStyle(
              color: Color(0xFFE3EEF7),
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chi',
                      style: TextStyle(color: Color(0xFFE3EEF7), fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatVnd(expense),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Thu',
                      style: TextStyle(color: Color(0xFFE3EEF7), fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatVnd(income),
                      style: const TextStyle(
                        color: Color(0xFFB8F5C4),
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$count giao dịch tháng này',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date, required this.dayTotal});

  final DateTime date;
  final double dayTotal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _friendlyDate(date),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: AppColors.onSurfaceMuted,
              ),
            ),
          ),
          Text(
            formatVnd(dayTotal),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: AppColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransactionTile extends StatefulWidget {
  const _TransactionTile({
    required this.transaction,
    required this.onTap,
    this.onConfirm,
  });

  final TransactionModel transaction;
  final VoidCallback onTap;
  final VoidCallback? onConfirm;

  @override
  State<_TransactionTile> createState() => _TransactionTileState();
}

class _TransactionTileState extends State<_TransactionTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    final cats = tx.itemCategories.isNotEmpty
        ? tx.itemCategories.map((c) => c.name).join(' · ')
        : (tx.categoryName ?? (tx.isIncome ? 'Thu nhập' : 'Chưa phân loại'));
    final needsCategory =
        !tx.isIncome && tx.categoryId == null && tx.itemCategories.isEmpty;
    final items = _visibleItems(tx.items ?? const []);
    final amountColor = tx.isIncome ? AppColors.success : AppColors.error;
    final amountPrefix = tx.isIncome ? '+' : '-';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: (tx.isIncome
                              ? AppColors.success
                              : AppColors.secondary)
                          .withValues(alpha: 0.12),
                      child: Icon(
                        tx.isIncome
                            ? Icons.south_west_rounded
                            : categoryIconFor(
                                tx.itemCategories.isNotEmpty
                                    ? tx.itemCategories.first.name
                                    : tx.categoryName,
                              ),
                        color: tx.isIncome
                            ? AppColors.success
                            : AppColors.secondary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx.merchantName?.trim().isNotEmpty == true
                                ? tx.merchantName!
                                : (tx.isIncome ? 'Thu nhập' : 'Chi tiêu'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  cats,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: needsCategory
                                        ? AppColors.warning
                                        : AppColors.onSurfaceMuted,
                                    fontWeight: needsCategory
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (needsCategory && widget.onConfirm != null) ...[
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: widget.onConfirm,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.35,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'Chọn',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$amountPrefix${formatVnd(tx.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: amountColor,
                          ),
                        ),
                        if (items.isNotEmpty)
                          GestureDetector(
                            onTap: () => setState(() => _expanded = !_expanded),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${items.length} món',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.secondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Icon(
                                    _expanded
                                        ? Icons.expand_less
                                        : Icons.expand_more,
                                    size: 16,
                                    color: AppColors.secondary,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded && items.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  children: [
                    const Divider(height: 1),
                    ...items.map((entry) {
                      final item = entry is Map<String, dynamic>
                          ? entry
                          : Map<String, dynamic>.from(entry as Map);
                      final qty = (item['qty'] as num?)?.toInt() ?? 1;
                      final price = (item['price'] as num?)?.toDouble() ?? 0;
                      final cat = item['category_name']?.toString();
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item['name']?.toString() ?? 'Không rõ',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  if (cat != null && cat.isNotEmpty)
                                    Text(
                                      cat,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.onSurfaceMuted,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (qty > 1)
                              Text(
                                'x$qty  ',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.onSurfaceMuted,
                                ),
                              ),
                            Text(
                              formatVnd(price * qty),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

List<dynamic> _visibleItems(List<dynamic> items) {
  return items.where((entry) {
    final item = entry is Map<String, dynamic>
        ? entry
        : Map<String, dynamic>.from(entry as Map);
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    return price >= 0;
  }).toList();
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, required this.onCapture});

  final VoidCallback onAdd;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                size: 40,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Chưa có giao dịch',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Thêm thủ công hoặc chụp hóa đơn để bắt đầu theo dõi chi tiêu.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.onSurfaceMuted, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Thêm giao dịch'),
            ),
            const SizedBox(height: 10),
            TextButton(onPressed: onCapture, child: const Text('Chụp hóa đơn')),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Không tải được danh sách.\nKéo xuống để thử lại.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.onSurfaceMuted),
        ),
      ),
    );
  }
}

class _TxGroup {
  _TxGroup({required this.date, required this.items});

  final DateTime date;
  final List<TransactionModel> items;

  double get dayTotal => items
      .where((t) => !t.isIncome)
      .fold(0.0, (s, t) => s + t.amount);
}

List<_TxGroup> _groupByDate(List<TransactionModel> txs) {
  final map = <String, List<TransactionModel>>{};
  for (final tx in txs) {
    final key = DateFormat('yyyy-MM-dd').format(tx.transactionDate);
    map.putIfAbsent(key, () => []).add(tx);
  }
  final keys = map.keys.toList()..sort((a, b) => b.compareTo(a));
  return keys
      .map(
        (k) => _TxGroup(
          date: DateTime.parse(k),
          items: map[k]!,
        ),
      )
      .toList();
}

double _monthTotal(List<TransactionModel> txs, {required bool income}) {
  return txs
      .where((t) => _isThisMonth(t.transactionDate) && t.isIncome == income)
      .fold(0.0, (s, t) => s + t.amount);
}

bool _isThisMonth(DateTime d) {
  final now = DateTime.now();
  return d.year == now.year && d.month == now.month;
}

String _friendlyDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(date.year, date.month, date.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Hôm qua';
  return formatWeekdayDate(date);
}
