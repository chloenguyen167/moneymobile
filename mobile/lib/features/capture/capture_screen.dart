import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../../core/utils/image_compress.dart';
import '../../data/models/models.dart';

/// MoMo-style capture tab: live camera + gallery FAB, bottom nav stays visible.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Future<void>? _initFuture;
  bool _initFailed = false;
  String? _initError;
  bool _busy = false;
  bool _pickingGallery = false;
  String? _status;
  Uint8List? _previewBytes;
  int _initGen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Do NOT dispose on inactive — gallery picker / permission dialogs trigger it
    // and leave the tab stuck on the loading spinner.
    if (state == AppLifecycleState.paused) {
      if (!_pickingGallery) {
        _disposeCamera();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null || _controller?.value.isInitialized != true) {
        _startCamera();
      }
    }
  }

  void _startCamera() {
    _initFailed = false;
    _initError = null;
    _initFuture = _initCamera();
    setState(() {});
  }

  Future<void> _disposeCamera() async {
    final cam = _controller;
    _controller = null;
    if (cam != null) {
      try {
        await cam.dispose();
      } catch (_) {}
    }
  }

  Future<void> _initCamera() async {
    final gen = ++_initGen;
    try {
      final cameras = await availableCameras().timeout(
        const Duration(seconds: 6),
        onTimeout: () => <CameraDescription>[],
      );
      if (gen != _initGen || !mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _initFailed = true;
          _initError = 'Không tìm thấy camera';
        });
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      await _disposeCamera();
      if (gen != _initGen || !mounted) return;

      final controller = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await controller.initialize().timeout(const Duration(seconds: 10));
      if (gen != _initGen || !mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initFailed = false;
        _initError = null;
      });
    } on TimeoutException {
      if (mounted && gen == _initGen) {
        setState(() {
          _initFailed = true;
          _initError = 'Camera mở quá lâu — dùng thư viện ảnh nhé';
        });
      }
    } catch (e) {
      if (mounted && gen == _initGen) {
        setState(() {
          _initFailed = true;
          _initError = 'Không mở được camera';
        });
      }
    }
  }

  Future<void> _takePhoto() async {
    final cam = _controller;
    if (cam == null || !cam.value.isInitialized || _busy) return;
    try {
      final file = await cam.takePicture();
      final raw = await File(file.path).readAsBytes();
      await _processBytes(Uint8List.fromList(raw), filename: 'capture.jpg');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không chụp được. Thử lại nhé.')),
        );
      }
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    _pickingGallery = true;
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (file == null) return;
      final raw = await file.readAsBytes();
      final name = file.name.endsWith('.jpg') || file.name.endsWith('.jpeg')
          ? file.name
          : '${file.name.split('.').first}.jpg';
      await _processBytes(Uint8List.fromList(raw), filename: name);
    } finally {
      _pickingGallery = false;
      if (mounted &&
          (_controller == null || _controller?.value.isInitialized != true)) {
        _startCamera();
      }
    }
  }

  Future<void> _processBytes(
    Uint8List raw, {
    required String filename,
  }) async {
    setState(() {
      _busy = true;
      _status = 'Đang đọc ảnh...';
      _previewBytes = null;
    });

    try {
      final compressed = compressImageBytes(raw, quality: 70);
      setState(() {
        _previewBytes = compressed;
        _status = 'Đang nhận diện hóa đơn / chuyển khoản...';
      });

      final result = await ref.read(repositoryProvider).processImage(
            compressed,
            filename: filename,
            // Blur IQA false-positives on bank screenshots caused retake loops
            isLowQuality: false,
          );
      invalidateTransactionRelated(ref);
      if (!mounted) return;
      setState(() => _status = null);
      _showResultSheet(result);
    } catch (e) {
      if (mounted) {
        setState(() => _status = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Không xử lý được ảnh. Thử lại hoặc chọn ảnh khác từ thư viện.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showResultSheet(ProcessImageResult result) {
    final amount = result.amount;
    final merchant = result.merchant;
    final cats = result.categoryLabels;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      result.transactionId != null
                          ? Icons.check_circle_rounded
                          : Icons.info_outline_rounded,
                      color: result.transactionId != null
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      result.transactionId != null
                          ? 'Đã lưu giao dịch'
                          : 'Đã đọc ảnh',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  result.kind == 'payment_screenshot'
                      ? 'Ảnh chuyển khoản / ví'
                      : 'Hóa đơn mua hàng',
                  style: const TextStyle(
                    color: AppColors.onSurfaceMuted,
                    fontSize: 13,
                  ),
                ),
                if (_previewBytes != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(
                      _previewBytes!,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                if (amount != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    formatVnd(amount),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
                if (merchant != null && merchant.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    merchant,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
                if (cats.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: cats
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
                const SizedBox(height: 18),
                if (result.transactionId != null)
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.push('/transactions/${result.transactionId}');
                    },
                    child: const Text('Xem giao dịch'),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Tiếp tục chụp'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cam = _controller;
    final ready = cam != null && cam.value.isInitialized;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            _CameraPreviewCover(controller: cam)
          else if (_initFailed)
            _CameraFallback(
              message: _initError ?? 'Không mở được camera',
              onGallery: _pickFromGallery,
              onRetry: _startCamera,
            )
          else
            FutureBuilder<void>(
              future: _initFuture,
              builder: (context, snap) {
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 12),
                      Text(
                        'Đang mở camera...',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                );
              },
            ),

          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            left: 16,
            right: 16,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Chụp hóa đơn hoặc ảnh chuyển khoản',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),

          if (ready && !_busy)
            const IgnorePointer(child: Center(child: _ScanFrame())),

          if (_busy)
            ColoredBox(
              color: Colors.black.withValues(alpha: 0.55),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_previewBytes != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          _previewBytes!,
                          height: 140,
                          width: 140,
                          fit: BoxFit.cover,
                        ),
                      ),
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(color: AppColors.primary),
                    const SizedBox(height: 12),
                    Text(
                      _status ?? 'Đang xử lý...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 28,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Row(
                  children: [
                    const SizedBox(width: 64),
                    const Spacer(),
                    _ShutterButton(
                      enabled: ready && !_busy,
                      onPressed: _takePhoto,
                    ),
                    const Spacer(),
                    _GalleryFab(
                      enabled: !_busy,
                      onPressed: _pickFromGallery,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreviewCover extends StatelessWidget {
  const _CameraPreviewCover({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    if (preview == null) return CameraPreview(controller);

    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: preview.height,
          height: preview.width,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: CustomPaint(painter: _CornerPainter()),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const len = 28.0;
    canvas.drawLine(Offset.zero, const Offset(len, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, len), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - len, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), paint);
    canvas.drawLine(Offset(0, size.height), Offset(len, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - len), paint);
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - len, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onPressed : null,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          color: Colors.white.withValues(alpha: 0.15),
        ),
        child: Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryFab extends StatelessWidget {
  const _GalleryFab({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onPressed : null,
            child: const SizedBox(
              width: 56,
              height: 56,
              child: Icon(
                Icons.add_photo_alternate_outlined,
                color: AppColors.secondary,
                size: 28,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Chọn ảnh',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _CameraFallback extends StatelessWidget {
  const _CameraFallback({
    required this.message,
    required this.onGallery,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onGallery;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_outlined,
              color: Colors.white70,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Chọn ảnh từ thư viện'),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text(
                'Thử mở camera lại',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
