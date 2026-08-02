import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/image_compress.dart';
import '../../data/models/models.dart';

class PaymentScreenshotScreen extends ConsumerStatefulWidget {
  const PaymentScreenshotScreen({super.key});

  @override
  ConsumerState<PaymentScreenshotScreen> createState() =>
      _PaymentScreenshotScreenState();
}

class _PaymentScreenshotScreenState
    extends ConsumerState<PaymentScreenshotScreen> {
  Uint8List? _imageBytes;
  String? _filename;
  ImageQualityResult? _quality;
  ProcessPaymentScreenshotResult? _result;
  bool _processing = false;
  String? _error;

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (file == null) return;

    final bytes = await file.readAsBytes();
    final compressed = compressImageBytes(Uint8List.fromList(bytes), quality: 70);
    setState(() {
      _imageBytes = compressed;
      _filename = file.name.endsWith('.jpg') || file.name.endsWith('.jpeg')
          ? file.name
          : '${file.name.split('.').first}.jpg';
      _quality = evaluateImageQuality(compressed, blurThreshold: 20);
      _result = null;
      _error = null;
    });
  }

  Future<void> _processScreenshot() async {
    if (_imageBytes == null || _filename == null) return;

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      final result = await ref
          .read(repositoryProvider)
          .processPaymentScreenshot(_imageBytes!, filename: _filename!);
      ref.invalidate(transactionsProvider);
      setState(() => _result = result);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final extraction = _result?.extraction;

    return Scaffold(
      appBar: AppBar(title: const Text('Ảnh giao dịch')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFBEC), AppColors.background],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          children: [
            const _PaymentHero(),
            const SizedBox(height: 18),
            const _PaymentFlowCard(),
            const SizedBox(height: 18),
            _UploadPanel(
              imageBytes: _imageBytes,
              filename: _filename,
              quality: _quality,
              onPick: _pickScreenshot,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _imageBytes == null || _processing
                  ? null
                  : _processScreenshot,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                disabledBackgroundColor: const Color(0xFFE5E7EB),
                disabledForegroundColor: const Color(0xFF9CA3AF),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: _processing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(
                _processing
                    ? 'Đang phân tích ảnh giao dịch...'
                    : 'Phân tích ảnh giao dịch',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _NoticeCard(
                icon: Icons.error_outline_rounded,
                accent: AppColors.error,
                title: 'Không xử lý được ảnh',
                message: _error!,
              ),
            ],
            if (extraction != null) ...[
              const SizedBox(height: 20),
              _SectionCard(
                title: 'Kết quả trích xuất',
                icon: Icons.text_snippet_outlined,
                accent: AppColors.secondary,
                child: Column(
                  children: [
                    _FieldRow(
                      label: 'Số tiền',
                      value: extraction.totalAmount != null
                          ? formatVnd(extraction.totalAmount!)
                          : 'Không rõ',
                    ),
                    _FieldRow(
                      label: 'Người nhận',
                      value: extraction.merchant ?? 'Không rõ',
                    ),
                    _FieldRow(
                      label: 'Ứng dụng',
                      value: extraction.paymentSource ?? 'Không rõ',
                    ),
                    _FieldRow(
                      label: 'Ngày',
                      value: extraction.transactionDate != null
                          ? DateFormat(
                              'dd/MM/yyyy',
                            ).format(extraction.transactionDate!)
                          : 'Không rõ',
                    ),
                    _FieldRow(
                      label: 'Nội dung',
                      value: extraction.description ?? '—',
                    ),
                    _FieldRow(
                      label: 'Mã giao dịch',
                      value: extraction.referenceCode ?? '—',
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              _PaymentClassificationCard(
                classification: _result!.classification,
                transactionId: _result!.transactionId,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentHero extends StatelessWidget {
  const _PaymentHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD84C), AppColors.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.34),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Ảnh thanh toán',
              style: TextStyle(
                color: AppColors.onPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Chọn ảnh chuyển khoản hoặc ví điện tử',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.onPrimary,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'App sẽ đọc số tiền, người nhận và lưu thành một giao dịch.',
            style: TextStyle(
              color: Color(0xFF4E3D00),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentFlowCard extends StatelessWidget {
  const _PaymentFlowCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: AppColors.secondary, size: 18),
              SizedBox(width: 8),
              Text(
                'Flow khuyến nghị',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ],
          ),
          SizedBox(height: 14),
          _StepRow(
            step: '1',
            title: 'Chụp màn hình thanh toán',
            subtitle:
                'Chụp ngay trong app ngân hàng hoặc ví sau khi giao dịch thành công.',
          ),
          SizedBox(height: 12),
          _StepRow(
            step: '2',
            title: 'Chọn ảnh từ thư viện',
            subtitle:
                'Ưu tiên album Screenshots để tìm nhanh và giữ ảnh rõ nét.',
          ),
          SizedBox(height: 12),
          _StepRow(
            step: '3',
            title: 'Kiểm tra kết quả',
            subtitle:
                'App sẽ trích xuất và phân loại giao dịch thay vì liệt kê sản phẩm như hóa đơn.',
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  final String step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(
              color: AppColors.secondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.onSurfaceMuted,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UploadPanel extends StatelessWidget {
  const _UploadPanel({
    required this.imageBytes,
    required this.filename,
    required this.quality,
    required this.onPick,
  });

  final Uint8List? imageBytes;
  final String? filename;
  final ImageQualityResult? quality;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.onPrimary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chọn screenshot',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Ưu tiên ảnh chụp đầy đủ số tiền, người nhận và nội dung giao dịch.',
                      style: TextStyle(
                        color: AppColors.onSurfaceMuted,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (imageBytes == null)
            _EmptyPreview(onPick: onPick)
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.memory(
                imageBytes!,
                fit: BoxFit.cover,
                height: 280,
                width: double.infinity,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    filename ?? 'Ảnh đã chọn',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: onPick,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Đổi ảnh'),
                ),
              ],
            ),
          ],
          if (quality != null) ...[
            const SizedBox(height: 10),
            _QualityBanner(quality: quality!),
          ],
        ],
      ),
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF5E29C)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.add_photo_alternate_outlined,
              color: AppColors.onPrimary,
              size: 28,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Chưa có ảnh nào được chọn',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          const Text(
            'Chọn ảnh từ thư viện để bắt đầu.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.onSurfaceMuted, height: 1.4),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.onSurface,
              side: const BorderSide(color: Color(0xFFF0CF57)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Chọn screenshot từ thư viện'),
          ),
        ],
      ),
    );
  }
}

class _QualityBanner extends StatelessWidget {
  const _QualityBanner({required this.quality});

  final ImageQualityResult quality;

  @override
  Widget build(BuildContext context) {
    final isLow = quality.isLowQuality;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isLow
            ? const Color(0xFFFFF1EB)
            : AppColors.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            isLow
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline_rounded,
            color: isLow ? AppColors.warning : AppColors.success,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLow ? 'Ảnh hơi mờ — vẫn có thể đọc' : 'Ảnh đủ rõ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: AppColors.onSurfaceMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _PaymentClassificationCard extends StatelessWidget {
  const _PaymentClassificationCard({
    required this.classification,
    required this.transactionId,
  });

  final Map<String, dynamic> classification;
  final int? transactionId;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: transactionId != null ? 'Đã lưu giao dịch' : 'Kết quả',
      icon: transactionId != null
          ? Icons.check_circle_outline_rounded
          : Icons.category_outlined,
      accent: AppColors.secondary,
      child: Column(
        children: [
          _FieldRow(
            label: 'Danh mục',
            value: classification['category_name']?.toString() ?? 'Chưa phân loại',
          ),
          _FieldRow(
            label: 'Trạng thái',
            value: transactionId != null
                ? 'Đã thêm vào danh sách chi tiêu'
                : 'Chưa lưu — kiểm tra lại số tiền',
            isLast: true,
          ),
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.onSurfaceMuted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
