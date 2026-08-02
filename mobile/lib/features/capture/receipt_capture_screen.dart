import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/image_compress.dart';

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
  int? _transactionId;
  bool _processing = false;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCamera());
  }

  Future<void> _openCamera() => _pickImage(ImageSource.camera);

  Future<void> _openGallery() => _pickImage(ImageSource.gallery);

  Future<void> _pickImage(ImageSource source) async {
    if (_picking || _processing) return;
    setState(() => _picking = true);
    try {
      final picker = ImagePicker();
      // Full frame — no crop. Quality hint; we re-compress to 70% after.
      final file = await picker.pickImage(
        source: source,
        imageQuality: 100,
        maxWidth: null,
        maxHeight: null,
      );
      if (file == null) return;

      final raw = await file.readAsBytes();
      final bytes = compressImageBytes(Uint8List.fromList(raw), quality: 70);
      final quality = evaluateImageQuality(bytes);

      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _filename = file.name.endsWith('.jpg') || file.name.endsWith('.jpeg')
            ? file.name
            : '${file.name.split('.').first}.jpg';
        _quality = quality;
        _ocrResult = null;
        _classification = null;
        _transactionId = null;
        _error = null;
      });
      await _processReceipt();
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _processReceipt() async {
    if (_imageBytes == null || _filename == null) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final result = await ref.read(repositoryProvider).processReceipt(
            _imageBytes!,
            filename: _filename!,
            isLowQuality: _quality?.isLowQuality ?? false,
          );
      invalidateTransactionRelated(ref);
      if (!mounted) return;
      setState(() {
        _ocrResult = result.ocr;
        _classification = result.classification;
        _transactionId = result.transactionId;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Không đọc được hóa đơn. Thử chọn ảnh khác.');
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chụp hóa đơn'),
        actions: [
          IconButton(
            tooltip: 'Chọn từ thư viện',
            onPressed: _picking || _processing ? null : _openGallery,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          IconButton(
            tooltip: 'Chụp lại',
            onPressed: _picking || _processing ? null : _openCamera,
            icon: const Icon(Icons.camera_alt_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_picking && _imageBytes == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_imageBytes == null)
            _EmptyCapture(onCamera: _openCamera, onGallery: _openGallery)
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                _imageBytes!,
                height: 240,
                width: double.infinity,
                fit: BoxFit.contain,
              ),
            ),
            if (_quality != null && _quality!.isLowQuality) ...[
              const SizedBox(height: 12),
              Card(
                color: AppColors.primary.withValues(alpha: 0.18),
                child: const ListTile(
                  leading: Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                  ),
                  title: Text('Ảnh hơi mờ'),
                  subtitle: Text('Vẫn tiếp tục đọc bình thường.'),
                ),
              ),
            ],
            if (_processing) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              const Text(
                'Đang đọc hóa đơn...',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.onSurfaceMuted),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.error)),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _processReceipt,
                child: const Text('Thử lại'),
              ),
            ],
            if (_ocrResult != null && !_processing) ...[
              const SizedBox(height: 24),
              _SuccessCard(
                ocr: _ocrResult!,
                classification: _classification,
                transactionId: _transactionId,
                onView: _transactionId == null
                    ? null
                    : () => context.push('/transactions/$_transactionId'),
                onDone: () => context.go('/'),
                onRetake: _openCamera,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _EmptyCapture extends StatelessWidget {
  const _EmptyCapture({required this.onCamera, required this.onGallery});

  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(
            Icons.document_scanner_outlined,
            size: 64,
            color: AppColors.secondary,
          ),
          const SizedBox(height: 16),
          const Text(
            'Đưa camera vào hóa đơn để quét',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hoặc chọn ảnh có sẵn từ thư viện.',
            style: TextStyle(color: AppColors.onSurfaceMuted),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onCamera,
            icon: const Icon(Icons.camera_alt_rounded),
            label: const Text('Mở camera'),
          ),
          TextButton.icon(
            onPressed: onGallery,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Thư viện ảnh'),
          ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({
    required this.ocr,
    required this.classification,
    required this.transactionId,
    this.onView,
    required this.onDone,
    required this.onRetake,
  });

  final Map<String, dynamic> ocr;
  final Map<String, dynamic>? classification;
  final int? transactionId;
  final VoidCallback? onView;
  final VoidCallback onDone;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final merchant = ocr['merchant']?.toString();
    final amount = (ocr['total_amount'] as num?)?.toDouble();
    final breakdown =
        (classification?['category_breakdown'] as List<dynamic>?) ?? const [];
    final uniqueCats = <String>{};
    for (final entry in breakdown) {
      final name = (entry as Map)['category_name']?.toString();
      if (name != null && name.isNotEmpty) uniqueCats.add(name);
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                transactionId != null
                    ? Icons.check_circle_rounded
                    : Icons.info_outline_rounded,
                color: transactionId != null
                    ? AppColors.success
                    : AppColors.warning,
              ),
              const SizedBox(width: 8),
              Text(
                transactionId != null ? 'Đã lưu giao dịch' : 'Đã đọc hóa đơn',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (amount != null)
            Text(
              formatVnd(amount),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.secondary,
              ),
            ),
          if (merchant != null && merchant.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(merchant, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          if (uniqueCats.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: uniqueCats
                  .map(
                    (c) => Chip(
                      label: Text(c, style: const TextStyle(fontSize: 12)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor:
                          AppColors.secondary.withValues(alpha: 0.1),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (breakdown.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Theo nhóm', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...breakdown.map((entry) {
              final row = entry as Map<String, dynamic>;
              final amt = (row['total_amount'] as num?)?.toDouble() ?? 0;
              final count = row['item_count'] as int? ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(row['category_name']?.toString() ?? 'Khác'),
                    ),
                    Text(
                      formatVnd(amt),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$count món',
                      style: const TextStyle(
                        color: AppColors.onSurfaceMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 16),
          if (onView != null)
            FilledButton(
              onPressed: onView,
              child: const Text('Xem giao dịch'),
            ),
          TextButton(onPressed: onDone, child: const Text('Về danh sách')),
          TextButton(onPressed: onRetake, child: const Text('Chụp hóa đơn khác')),
        ],
      ),
    );
  }
}
