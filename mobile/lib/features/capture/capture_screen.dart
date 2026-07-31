import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/ai/ai_service.dart';
import '../../core/ai/receipt_models.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';

/// Chụp hóa đơn — OCR structuring + phân loại chạy 100% on-device
/// (Gemini Nano → Gemma 3n → Cloud fallback), backend chỉ lưu kết quả.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  String? _imagePath;
  ImageQualityResult? _quality;
  ReceiptData? _result;
  bool _processing = false;
  bool _saving = false;
  String? _error;

  // Form xác nhận
  final _merchantCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  DateTime? _date;
  String? _category;

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _totalCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, imageQuality: 90);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final quality = evaluateImageQuality(bytes);

    setState(() {
      _imagePath = file.path;
      _quality = quality;
      _result = null;
      _error = null;
    });
  }

  Future<void> _process() async {
    final path = _imagePath;
    if (path == null) return;

    setState(() {
      _processing = true;
      _error = null;
      _result = null;
    });

    try {
      final result = await ref.read(aiServiceProvider).processReceipt(path);
      _merchantCtrl.text = result.merchant ?? '';
      _totalCtrl.text = result.total?.round().toString() ?? '';
      _date = result.date ?? DateTime.now();
      _category = result.category;
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _processing = false);
    }
  }

  Future<void> _save(List<CategoryModel> categories) async {
    final result = _result;
    if (result == null) return;

    final total = double.tryParse(_totalCtrl.text.replaceAll(RegExp(r'[^\d]'), ''));
    if (total == null || total <= 0) {
      setState(() => _error = 'Tổng tiền không hợp lệ');
      return;
    }
    final merchant = _merchantCtrl.text.trim();
    final categoryId =
        categories.where((c) => c.name == _category).firstOrNull?.id;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await ref.read(repositoryProvider).createTransaction(
            amount: total,
            merchantName: merchant.isEmpty ? null : merchant,
            categoryId: categoryId,
            source: 'ocr',
            items: result.items.map((e) => e.toJson()).toList(),
            transactionDate: _date,
            confidence: result.confidence,
            classificationReason: 'on-device (${result.engine})',
            ocrTrackUsed: result.engine,
          );
      // Học merchant→category cho fast path lần sau
      await ref.read(aiServiceProvider).learnMerchant(
            merchant.isEmpty ? null : merchant,
            _category,
          );
      ref.invalidate(transactionsProvider);
      ref.invalidate(analyticsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã lưu giao dịch')),
        );
        setState(() {
          _imagePath = null;
          _quality = null;
          _result = null;
        });
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Chụp hóa đơn',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Xử lý on-device: OCR + AI trích xuất và phân loại ngay trên máy',
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
          if (_imagePath != null) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_imagePath!),
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
                  color: _quality!.isLowQuality ? AppColors.warning : AppColors.success,
                ),
                title: Text(_quality!.message),
                subtitle: Text('Blur score: ${_quality!.blurScore.toStringAsFixed(1)}'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _imagePath == null || _processing ? null : _process,
            icon: _processing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_processing ? 'Đang xử lý trên máy...' : 'Xử lý on-device'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_result != null)
            categoriesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Không tải được danh sách category: $e'),
              data: (categories) => _buildReviewForm(categories),
            ),
        ],
      ),
    );
  }

  Widget _buildReviewForm(List<CategoryModel> categories) {
    final result = _result!;
    final engineLabel = switch (result.engine) {
      'layer0' => 'Regex (lớp 0)',
      'gemini-nano' => 'Gemini Nano · on-device',
      'gemma-3n' => 'Gemma 3n · on-device',
      'cloud' => 'Cloud API',
      _ => result.engine,
    };
    final categoryNames = {
      ...categories.map((c) => c.name),
      ...kDefaultCategories,
    }.toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Text('Kết quả', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Chip(
              avatar: Icon(
                result.engine == 'cloud' ? Icons.cloud_outlined : Icons.smartphone,
                size: 16,
              ),
              label: Text(engineLabel, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        if (result.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...result.warnings.map(
            (w) => Card(
              color: AppColors.primary.withValues(alpha: 0.15),
              child: ListTile(
                dense: true,
                leading: const Icon(Icons.warning_amber, color: AppColors.warning, size: 20),
                title: Text(w, style: const TextStyle(fontSize: 13)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _merchantCtrl,
          decoration: const InputDecoration(labelText: 'Cửa hàng', prefixIcon: Icon(Icons.storefront)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _totalCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Tổng tiền (VND)', prefixIcon: Icon(Icons.payments)),
        ),
        const SizedBox(height: 12),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          leading: const Icon(Icons.event),
          title: Text(_date != null ? DateFormat('dd/MM/yyyy').format(_date!) : 'Chọn ngày'),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked != null) setState(() => _date = picked);
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: categoryNames.contains(_category) ? _category : null,
          decoration: const InputDecoration(labelText: 'Category', prefixIcon: Icon(Icons.category)),
          items: categoryNames
              .map((name) => DropdownMenuItem(value: name, child: Text(name)))
              .toList(),
          onChanged: (v) => setState(() => _category = v),
        ),
        if (result.items.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Món hàng (${result.items.length})', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Card(
            child: Column(
              children: result.items
                  .take(10)
                  .map(
                    (item) => ListTile(
                      dense: true,
                      title: Text(item.name),
                      leading: Text('${item.qty}x', style: const TextStyle(color: AppColors.onSurfaceMuted)),
                      trailing: item.price != null ? Text(formatVnd(item.price!)) : null,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : () => _save(categories),
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: Text(_saving ? 'Đang lưu...' : 'Lưu giao dịch'),
        ),
      ],
    );
  }
}
