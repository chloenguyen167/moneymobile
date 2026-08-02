import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../home/app_bottom_nav.dart';

class ReceiptCaptureScreen extends ConsumerStatefulWidget {
  const ReceiptCaptureScreen({super.key});

  @override
  ConsumerState<ReceiptCaptureScreen> createState() =>
      _ReceiptCaptureScreenState();
}

class _ReceiptCaptureScreenState extends ConsumerState<ReceiptCaptureScreen> {
  Uint8List? _imageBytes;
  String? _filename;
  ImageQualityResult? _quality;
  Map<String, dynamic>? _ocrResult;
  Map<String, dynamic>? _classification;
  bool _processing = false;
  bool _classifying = false;
  String? _error;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final quality = evaluateImageQuality(bytes);

    setState(() {
      _imageBytes = bytes;
      _filename = file.name;
      _quality = quality;
      _ocrResult = null;
      _classification = null;
      _classifying = false;
      _error = null;
    });
  }

  Future<void> _processReceipt() async {
    if (_imageBytes == null || _filename == null) return;

    setState(() {
      _processing = true;
      _classifying = false;
      _ocrResult = null;
      _classification = null;
      _error = null;
    });

    try {
      final repository = ref.read(repositoryProvider);
      final result = await repository.processReceipt(
        _imageBytes!,
        filename: _filename!,
        isLowQuality: _quality?.isLowQuality ?? false,
        includeClassification: false,
        autoSave: false,
      );

      setState(() {
        _ocrResult = result.ocr;
        _processing = false;
        _classifying = true;
      });

      final classifyResult = await repository.classifyReceipt(
        result.ocr,
        autoSave: true,
      );
      ref.invalidate(transactionsProvider);
      ref.invalidate(budgetsProvider);
      ref.invalidate(analyticsProvider);
      ref.invalidate(cashflowInsightsProvider);
      ref.invalidate(subscriptionsProvider);
      if (!mounted) return;
      setState(() {
        _classification = classifyResult.classification;
        _classifying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _processing = false;
        _classifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chụp hóa đơn')),
      bottomNavigationBar: const AppBottomNav(selectedIndex: 1),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'OCR hóa đơn',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Dùng cho hóa đơn mua hàng có nhiều sản phẩm. Luồng này giữ nguyên pipeline OCR receipt hiện tại.',
              style: TextStyle(color: AppColors.onSurfaceMuted),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Thư viện'),
                  ),
                ),
              ],
            ),
            if (_imageBytes != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imageBytes!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            if (_quality != null) ...[
              const SizedBox(height: 12),
              Card(
                color: _quality!.isLowQuality
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.secondary.withValues(alpha: 0.1),
                child: ListTile(
                  leading: Icon(
                    _quality!.isLowQuality ? Icons.warning : Icons.check_circle,
                    color: _quality!.isLowQuality
                        ? AppColors.warning
                        : AppColors.success,
                  ),
                  title: Text(_quality!.message),
                  subtitle: Text(
                    'Blur score: ${_quality!.blurScore.toStringAsFixed(1)}',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _imageBytes == null || _processing
                  ? null
                  : _processReceipt,
              icon: _processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner),
              label: Text(_processing ? 'Đang quét OCR...' : 'Gửi OCR hóa đơn'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_ocrResult != null) ...[
              const SizedBox(height: 24),
              Text(
                'Kết quả OCR',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _ResultCard(data: _ocrResult!),
            ],
            if (_classifying) ...[
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                  title: const Text('Đang phân loại và lưu giao dịch'),
                  subtitle: const Text(
                    'OCR đã xong. App đang chạy tiếp bước phân loại ở nền để màn hình trả kết quả nhanh hơn.',
                  ),
                ),
              ),
            ],
            if (_classification != null) ...[
              const SizedBox(height: 16),
              Text('Phân loại', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              _ClassificationCard(data: _classification!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final merchant = data['merchant']?.toString() ?? 'Không rõ';
    final totalAmount = data['total_amount'];
    final transactionDate = data['transaction_date']?.toString() ?? 'Không rõ';
    final ocrTrack = data['ocr_track_used']?.toString() ?? 'Không rõ';
    final confidence = data['ocr_confidence']?.toString() ?? 'Không rõ';
    final items = (data['items'] as List<dynamic>?) ?? const [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResultRow(label: 'Merchant', value: merchant),
            _ResultRow(
              label: 'Tổng tiền',
              value: totalAmount != null
                  ? '${totalAmount.toString()} đ'
                  : 'Không rõ',
            ),
            _ResultRow(label: 'Ngày giao dịch', value: transactionDate),
            _ResultRow(label: 'Số sản phẩm', value: '${items.length} món'),
            _ResultRow(label: 'OCR track', value: ocrTrack),
            _ResultRow(label: 'Độ tin cậy', value: confidence, isLast: true),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => _showOcrDetailSheet(context, data),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Xem chi tiết OCR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
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

void _showOcrDetailSheet(BuildContext context, Map<String, dynamic> data) {
  final items = (data['items'] as List<dynamic>?) ?? const [];

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_ios_new_rounded),
                    tooltip: 'Quay lại',
                  ),
                  Expanded(
                    child: Text(
                      'Chi tiết OCR',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Đóng',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ...data.entries.where((entry) => entry.key != 'items').map((
                      entry,
                    ) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text('${entry.key}: ${entry.value}'),
                      );
                    }),
                    if (items.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Danh sách sản phẩm',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      ...items.take(20).map((item) {
                        final row = item is Map<String, dynamic>
                            ? item
                            : Map<String, dynamic>.from(item as Map);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(
                              row['name']?.toString() ?? 'Không rõ tên',
                            ),
                            subtitle: Text(
                              'SL: ${row['qty'] ?? 1} · Giá: ${row['price'] ?? 0} đ',
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ClassificationCard extends StatelessWidget {
  const _ClassificationCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final breakdown =
        (data['category_breakdown'] as List<dynamic>?) ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (breakdown.isNotEmpty) ...[
              Text(
                'Tổng hợp theo nhóm',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ...breakdown.map((entry) {
                final row = entry as Map<String, dynamic>;
                final amount = (row['total_amount'] as num?)?.toDouble() ?? 0;
                final itemCount = row['item_count'] as int? ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          row['category_name']?.toString() ?? 'Khác',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        '${amount.toStringAsFixed(0)} đ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$itemCount món',
                        style: const TextStyle(color: AppColors.onSurfaceMuted),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 24),
            ],
            ...data.entries.where((e) => e.key != 'category_breakdown').map((
              e,
            ) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${e.key}: ${e.value}'),
              );
            }),
          ],
        ),
      ),
    );
  }
}
