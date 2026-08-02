import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../data/models/models.dart';

class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({
    super.key,
    required this.transactionId,
    this.initial,
  });

  final int transactionId;
  final TransactionModel? initial;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  TransactionModel? _tx;
  Uint8List? _imageBytes;
  bool _loading = false;
  bool _loadingImage = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tx = widget.initial;
    if (_tx == null) {
      _reload();
    } else if (_tx!.hasImage) {
      _loadImage();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tx = await ref
          .read(repositoryProvider)
          .getTransaction(widget.transactionId);
      if (mounted) {
        setState(() => _tx = tx);
        if (tx.hasImage) await _loadImage();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Không tải được giao dịch');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadImage() async {
    setState(() => _loadingImage = true);
    try {
      final bytes = await ref
          .read(repositoryProvider)
          .getTransactionImage(widget.transactionId);
      if (mounted && bytes != null) {
        setState(() => _imageBytes = Uint8List.fromList(bytes));
      }
    } catch (_) {
      // ignore — image optional
    } finally {
      if (mounted) setState(() => _loadingImage = false);
    }
  }

  Future<void> _edit() async {
    final tx = _tx;
    if (tx == null) return;
    final ok = await context.push<bool>(
      '/transactions/${tx.id}/edit',
      extra: tx,
    );
    if (ok == true) await _reload();
  }

  Future<void> _delete() async {
    final tx = _tx;
    if (tx == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa giao dịch?'),
        content: Text(
          'Xóa ${formatVnd(tx.amount)}${tx.merchantName != null ? ' · ${tx.merchantName}' : ''}?\n'
          'Ngân sách và thống kê sẽ được cập nhật.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(repositoryProvider).deleteTransaction(tx.id);
      invalidateTransactionRelated(ref);
      if (mounted) context.pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không xóa được. Thử lại nhé.')),
        );
      }
    }
  }

  Future<void> _changeCategory() async {
    final tx = _tx;
    if (tx == null) return;
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
                  final selected = cat.id == tx.categoryId;
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
                    trailing: selected
                        ? const Icon(Icons.check_rounded, color: AppColors.secondary)
                        : null,
                    onTap: () => Navigator.pop(ctx, cat.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );

    if (selected == null || selected == tx.categoryId) return;
    try {
      final updated = await ref
          .read(repositoryProvider)
          .updateTransaction(id: tx.id, categoryId: selected);
      invalidateTransactionRelated(ref);
      if (mounted) setState(() => _tx = updated);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không cập nhật được danh mục')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = _tx;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Chi tiết'),
        actions: [
          IconButton(
            tooltip: 'Sửa',
            onPressed: tx == null ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Xóa',
            onPressed: tx == null ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: _loading && tx == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && tx == null
              ? Center(child: Text(_error!))
              : tx == null
                  ? const SizedBox.shrink()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: [
                        _AmountHeader(transaction: tx),
                        const SizedBox(height: 16),
                        if (_loadingImage)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 16),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_imageBytes != null) ...[
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => Dialog(
                                  child: InteractiveViewer(
                                    child: Image.memory(_imageBytes!),
                                  ),
                                ),
                              );
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.memory(
                                _imageBytes!,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Chạm để xem ảnh gốc',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.onSurfaceMuted,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _InfoCard(
                          children: [
                            _InfoRow(
                              icon: Icons.storefront_rounded,
                              label: tx.isIncome ? 'Nguồn' : 'Người nhận',
                              value: tx.merchantName?.trim().isNotEmpty == true
                                  ? tx.merchantName!
                                  : 'Không rõ',
                            ),
                            _InfoRow(
                              icon: Icons.calendar_today_rounded,
                              label: 'Ngày',
                              value: formatFullDate(tx.transactionDate),
                            ),
                            _InfoRow(
                              icon: Icons.category_rounded,
                              label: 'Danh mục',
                              value: tx.itemCategories.isNotEmpty
                                  ? tx.itemCategories
                                      .map((c) => c.name)
                                      .join(' · ')
                                  : (tx.categoryName ??
                                      (tx.isIncome
                                          ? 'Thu nhập'
                                          : 'Chưa phân loại')),
                              valueColor: !tx.isIncome &&
                                      tx.categoryId == null &&
                                      tx.itemCategories.isEmpty
                                  ? AppColors.warning
                                  : null,
                              onTap: tx.hasItems ? null : _changeCategory,
                              trailing: tx.hasItems
                                  ? null
                                  : const Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppColors.onSurfaceMuted,
                                      size: 20,
                                    ),
                            ),
                            _InfoRow(
                              icon: Icons.swap_vert_rounded,
                              label: 'Loại',
                              value: tx.isIncome ? 'Thu vào' : 'Chi ra',
                            ),
                            _InfoRow(
                              icon: Icons.input_rounded,
                              label: 'Nguồn nhập',
                              value: sourceLabel(tx.source),
                            ),
                          ],
                        ),
                        ..._buildItemsSection(tx),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _edit,
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Sửa'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.error,
                                  side: const BorderSide(color: AppColors.error),
                                ),
                                onPressed: _delete,
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('Xóa'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
    );
  }

  List<Widget> _buildItemsSection(TransactionModel tx) {
    final items = _visibleItems(tx.items ?? const []);
    if (items.isEmpty) return const [];

    final breakdown = _buildBreakdown(items);
    return [
      const SizedBox(height: 20),
      if (breakdown.isNotEmpty) ...[
        const Text(
          'Theo nhóm',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 8),
        _InfoCard(
          children: breakdown
              .map(
                (row) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.categoryName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        formatVnd(row.totalAmount),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${row.itemCount} món',
                        style: const TextStyle(
                          color: AppColors.onSurfaceMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
      ],
      const Text(
        'Sản phẩm',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
      const SizedBox(height: 8),
      ...items.map((entry) {
        final item = entry is Map<String, dynamic>
            ? entry
            : Map<String, dynamic>.from(entry as Map);
        final qty = (item['qty'] as num?)?.toInt() ?? 1;
        final price = (item['price'] as num?)?.toDouble() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              title: Text(item['name']?.toString() ?? 'Không rõ tên'),
              subtitle: Text(
                qty > 1
                    ? 'SL: $qty · ${formatVnd(price)}'
                    : formatVnd(price),
              ),
              trailing: Text(
                formatVnd(price * qty),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        );
      }),
    ];
  }
}

class _AmountHeader extends StatelessWidget {
  const _AmountHeader({required this.transaction});

  final TransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.isIncome;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isIncome
              ? const [Color(0xFF2E7D32), Color(0xFF43A047)]
              : const [AppColors.secondary, Color(0xFF3E7CAA)],
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.18),
            child: Icon(
              isIncome
                  ? Icons.south_west_rounded
                  : categoryIconFor(
                      transaction.itemCategories.isNotEmpty
                          ? transaction.itemCategories.first.name
                          : transaction.categoryName,
                    ),
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${isIncome ? '+' : '-'}${formatVnd(transaction.amount)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            transaction.merchantName?.trim().isNotEmpty == true
                ? transaction.merchantName!
                : (isIncome ? 'Thu nhập' : 'Chi tiêu'),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1) const Divider(height: 1),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: valueColor,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _CategoryTotal {
  const _CategoryTotal({
    required this.categoryName,
    required this.totalAmount,
    required this.itemCount,
  });

  final String categoryName;
  final double totalAmount;
  final int itemCount;
}

List<_CategoryTotal> _buildBreakdown(List<dynamic> items) {
  final totals = <String, double>{};
  final counts = <String, int>{};

  for (final entry in items) {
    final item = entry is Map<String, dynamic>
        ? entry
        : Map<String, dynamic>.from(entry as Map);
    final category = item['category_name']?.toString();
    if (category == null || category.isEmpty) continue;
    final qty = (item['qty'] as num?)?.toInt() ?? 1;
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    totals[category] = (totals[category] ?? 0) + (price * qty);
    counts[category] = (counts[category] ?? 0) + qty;
  }

  final rows = totals.entries
      .map(
        (e) => _CategoryTotal(
          categoryName: e.key,
          totalAmount: e.value,
          itemCount: counts[e.key] ?? 0,
        ),
      )
      .toList();
  rows.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
  return rows;
}

List<dynamic> _visibleItems(List<dynamic> items) {
  return items.where((entry) {
    final item = entry is Map<String, dynamic>
        ? entry
        : Map<String, dynamic>.from(entry as Map);
    return !_isDiscountLikeItem(item);
  }).toList();
}

bool _isDiscountLikeItem(Map<String, dynamic> item) {
  final name = (item['name']?.toString() ?? '').trim().toLowerCase();
  final normalized = _normalizeVietnameseForUi(name);
  final price = (item['price'] as num?)?.toDouble() ?? 0;

  const discountKeywords = [
    'uu dai',
    'uu dai the',
    'giam gia',
    'khuyen mai',
    'voucher',
    'discount',
  ];

  if (price >= 0) return false;
  return discountKeywords.any((keyword) => normalized.contains(keyword));
}

String _normalizeVietnameseForUi(String text) {
  const replacements = {
    'à': 'a', 'á': 'a', 'ạ': 'a', 'ả': 'a', 'ã': 'a',
    'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ặ': 'a', 'ẳ': 'a', 'ẵ': 'a',
    'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ậ': 'a', 'ẩ': 'a', 'ẫ': 'a',
    'è': 'e', 'é': 'e', 'ẹ': 'e', 'ẻ': 'e', 'ẽ': 'e',
    'ê': 'e', 'ề': 'e', 'ế': 'e', 'ệ': 'e', 'ể': 'e', 'ễ': 'e',
    'ì': 'i', 'í': 'i', 'ị': 'i', 'ỉ': 'i', 'ĩ': 'i',
    'ò': 'o', 'ó': 'o', 'ọ': 'o', 'ỏ': 'o', 'õ': 'o',
    'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ộ': 'o', 'ổ': 'o', 'ỗ': 'o',
    'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ợ': 'o', 'ở': 'o', 'ỡ': 'o',
    'ù': 'u', 'ú': 'u', 'ụ': 'u', 'ủ': 'u', 'ũ': 'u',
    'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ự': 'u', 'ử': 'u', 'ữ': 'u',
    'ỳ': 'y', 'ý': 'y', 'ỵ': 'y', 'ỷ': 'y', 'ỹ': 'y', 'đ': 'd',
  };

  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();
}
