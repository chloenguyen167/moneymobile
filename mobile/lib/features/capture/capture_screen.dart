import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  Uint8List? _imageBytes;
  String? _filename;
  ImageQualityResult? _quality;
  Map<String, dynamic>? _ocrResult;
  Map<String, dynamic>? _classification;
  bool _processing = false;
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
      _error = null;
    });
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
      ref.invalidate(transactionsProvider);
      setState(() {
        _ocrResult = result.ocr;
        _classification = result.classification;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
          Text(
            'Edge Gate kiểm tra chất lượng ảnh trước khi gửi OCR cascade',
            style: const TextStyle(color: AppColors.onSurfaceMuted),
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
              child: Image.memory(_imageBytes!, height: 200, width: double.infinity, fit: BoxFit.cover),
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
            onPressed: _imageBytes == null || _processing ? null : _processReceipt,
            icon: _processing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.document_scanner),
            label: Text(_processing ? 'Đang xử lý OCR...' : 'Gửi OCR Cascade'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (_ocrResult != null) ...[
            const SizedBox(height: 24),
            Text('Kết quả OCR', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ResultCard(data: _ocrResult!),
          ],
          if (_classification != null) ...[
            const SizedBox(height: 16),
            Text('Phân loại', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ResultCard(data: _classification!),
          ],
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: data.entries.map((e) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${e.key}: ${e.value}'),
            );
          }).toList(),
        ),
      ),
    );
  }
}
