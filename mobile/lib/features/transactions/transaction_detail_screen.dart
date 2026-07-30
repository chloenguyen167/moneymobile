import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';

class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key, required this.transaction});

  final TransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm');
    final items = _visibleItems(transaction.items ?? const []);
    final breakdown = _buildBreakdown(items);
    final hasReceiptItems = items.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          hasReceiptItems ? 'Chi tiết hóa đơn' : 'Chi tiết giao dịch',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.merchantName ?? 'Không rõ merchant',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatVnd(transaction.amount),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${dateFmt.format(transaction.createdAt)} · ${transaction.source}',
                    style: const TextStyle(color: AppColors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ClassificationCard(transaction: transaction),
          if (hasReceiptItems && breakdown.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Tổng hợp theo nhóm',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: breakdown.map((row) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.categoryName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            formatVnd(row.totalAmount),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${row.itemCount} món',
                            style: const TextStyle(
                              color: AppColors.onSurfaceMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
          if (hasReceiptItems) ...[
            const SizedBox(height: 16),
            Text(
              'Danh sách sản phẩm OCR',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...items.map((entry) {
              final item = entry is Map<String, dynamic>
                  ? entry
                  : Map<String, dynamic>.from(entry as Map);
              final qty = (item['qty'] as num?)?.toInt() ?? 1;
              final price = (item['price'] as num?)?.toDouble() ?? 0;
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(item['name']?.toString() ?? 'Không rõ tên'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SL: $qty · Đơn giá: ${formatVnd(price)}'),
                      if (item['category_name'] != null)
                        Text(
                          'Nhóm: ${item['category_name']}',
                          style: const TextStyle(
                            color: AppColors.onSurfaceMuted,
                          ),
                        ),
                    ],
                  ),
                  trailing: Text(
                    formatVnd(price * qty),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _ClassificationCard extends StatelessWidget {
  const _ClassificationCard({required this.transaction});

  final TransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Phân loại giao dịch',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Nhóm',
              value: transaction.categoryName ?? 'Chưa phân loại',
            ),
            _InfoRow(
              label: 'Confidence',
              value: transaction.confidence != null
                  ? transaction.confidence!.toStringAsFixed(2)
                  : 'Không rõ',
            ),
            _InfoRow(
              label: 'Track',
              value: transaction.ocrTrackUsed ?? 'Không rõ',
            ),
            if (transaction.classificationReason != null &&
                transaction.classificationReason!.trim().isNotEmpty)
              _InfoRow(
                label: 'Lý do',
                value: transaction.classificationReason!,
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: const TextStyle(color: AppColors.onSurfaceMuted),
            ),
          ),
        ],
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

  final discountKeywords = [
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
    'à': 'a',
    'á': 'a',
    'ạ': 'a',
    'ả': 'a',
    'ã': 'a',
    'ă': 'a',
    'ằ': 'a',
    'ắ': 'a',
    'ặ': 'a',
    'ẳ': 'a',
    'ẵ': 'a',
    'â': 'a',
    'ầ': 'a',
    'ấ': 'a',
    'ậ': 'a',
    'ẩ': 'a',
    'ẫ': 'a',
    'è': 'e',
    'é': 'e',
    'ẹ': 'e',
    'ẻ': 'e',
    'ẽ': 'e',
    'ê': 'e',
    'ề': 'e',
    'ế': 'e',
    'ệ': 'e',
    'ể': 'e',
    'ễ': 'e',
    'ì': 'i',
    'í': 'i',
    'ị': 'i',
    'ỉ': 'i',
    'ĩ': 'i',
    'ò': 'o',
    'ó': 'o',
    'ọ': 'o',
    'ỏ': 'o',
    'õ': 'o',
    'ô': 'o',
    'ồ': 'o',
    'ố': 'o',
    'ộ': 'o',
    'ổ': 'o',
    'ỗ': 'o',
    'ơ': 'o',
    'ờ': 'o',
    'ớ': 'o',
    'ợ': 'o',
    'ở': 'o',
    'ỡ': 'o',
    'ù': 'u',
    'ú': 'u',
    'ụ': 'u',
    'ủ': 'u',
    'ũ': 'u',
    'ư': 'u',
    'ừ': 'u',
    'ứ': 'u',
    'ự': 'u',
    'ử': 'u',
    'ữ': 'u',
    'ỳ': 'y',
    'ý': 'y',
    'ỵ': 'y',
    'ỷ': 'y',
    'ỹ': 'y',
    'đ': 'd',
  };

  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(replacements[char] ?? char);
  }
  return buffer.toString().replaceAll(RegExp(r'[^a-z0-9\s]'), '').trim();
}
