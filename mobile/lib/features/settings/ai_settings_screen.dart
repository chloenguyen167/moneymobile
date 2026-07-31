import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/ai/ai_channel.dart';
import '../../core/ai/ai_settings.dart';
import '../../core/theme/app_colors.dart';

/// Cấu hình model linh động: user chọn runtime (Auto / Gemini Nano / Gemma 3n /
/// Cloud API) — đổi config, không cần sửa code.
class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  AiEngineMode _mode = AiEngineMode.auto;
  String _nanoStatus = '...';
  bool _gemmaReady = false;
  String _gemmaPath = '';

  final _cloudKeyCtrl = TextEditingController();
  final _cloudModelCtrl = TextEditingController();
  final _gemmaUrlCtrl = TextEditingController();
  final _hfTokenCtrl = TextEditingController();

  bool _nanoDownloading = false;
  double? _gemmaProgress; // null = không tải, 0..1 = đang tải
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cloudKeyCtrl.dispose();
    _cloudModelCtrl.dispose();
    _gemmaUrlCtrl.dispose();
    _hfTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await AiSettings.load();
    final gemmaPath = await AiSettings.gemmaModelPath();
    final nanoStatus = await AiNative.nanoStatus();
    final gemmaReady = await AiNative.gemmaAvailable(gemmaPath);
    if (!mounted) return;
    setState(() {
      _mode = settings.mode;
      _cloudKeyCtrl.text = settings.cloudApiKey;
      _cloudModelCtrl.text = settings.cloudModel;
      _gemmaUrlCtrl.text = settings.gemmaModelUrl;
      _hfTokenCtrl.text = settings.hfToken;
      _gemmaPath = gemmaPath;
      _nanoStatus = nanoStatus;
      _gemmaReady = gemmaReady;
    });
  }

  Future<void> _saveMode(AiEngineMode mode) async {
    setState(() => _mode = mode);
    await AiSettings.save(mode: mode);
  }

  Future<void> _saveCloud() async {
    await AiSettings.save(
      cloudApiKey: _cloudKeyCtrl.text,
      cloudModel: _cloudModelCtrl.text,
    );
    setState(() => _message = 'Đã lưu cấu hình Cloud API');
  }

  Future<void> _downloadNano() async {
    setState(() {
      _nanoDownloading = true;
      _message = null;
    });
    try {
      await AiNative.nanoDownload();
      setState(() => _message = 'Đã tải Gemini Nano');
    } catch (e) {
      setState(() => _message = 'Lỗi tải Gemini Nano: $e');
    } finally {
      _nanoDownloading = false;
      await _load();
    }
  }

  Future<void> _downloadGemma() async {
    await AiSettings.save(
      gemmaModelUrl: _gemmaUrlCtrl.text,
      hfToken: _hfTokenCtrl.text,
    );
    setState(() {
      _gemmaProgress = 0;
      _message = null;
    });

    final tmpFile = File('$_gemmaPath.part');
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(_gemmaUrlCtrl.text.trim()));
      final token = _hfTokenCtrl.text.trim();
      if (token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';

      final response = await client.send(request);
      if (response.statusCode >= 400) {
        throw Exception('HTTP ${response.statusCode} — model Gemma trên HuggingFace '
            'cần chấp nhận license và dùng token hợp lệ');
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = tmpFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            setState(() => _gemmaProgress = received / total);
          }
        }
      } finally {
        await sink.close();
      }

      await tmpFile.rename(_gemmaPath);
      setState(() => _message = 'Đã tải model Gemma 3n');
    } catch (e) {
      if (tmpFile.existsSync()) tmpFile.deleteSync();
      setState(() => _message = 'Lỗi tải Gemma: $e');
    } finally {
      client.close();
      setState(() => _gemmaProgress = null);
      await _load();
    }
  }

  Future<void> _deleteGemma() async {
    await AiNative.gemmaUnload();
    final f = File(_gemmaPath);
    if (f.existsSync()) f.deleteSync();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt AI')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'OCR hóa đơn, phân loại chi tiêu, đọc thông báo ngân hàng và gợi ý '
            'đều chạy qua AI Provider bên dưới. Ưu tiên on-device: dữ liệu không rời khỏi máy.',
            style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Text('Runtime', style: Theme.of(context).textTheme.titleMedium),
          ...AiEngineMode.values.map(
            (mode) => RadioListTile<AiEngineMode>(
              value: mode,
              groupValue: _mode,
              onChanged: (v) => _saveMode(v!),
              title: Text(switch (mode) {
                AiEngineMode.auto => 'Tự động (Nano → Gemma → Cloud)',
                AiEngineMode.nano => 'Gemini Nano — on-device (AICore)',
                AiEngineMode.gemma => 'Gemma 3n — on-device (LiteRT-LM)',
                AiEngineMode.cloud => 'Cloud API (Gemini) — cần mạng',
              }),
              dense: true,
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Card(
              color: AppColors.secondary.withValues(alpha: 0.1),
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
            ),
          ],
          const Divider(height: 32),

          // --- Gemini Nano ---
          Text('Gemini Nano (ML Kit GenAI)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(
                _nanoStatus == 'available' ? Icons.check_circle : Icons.info_outline,
                color: _nanoStatus == 'available' ? AppColors.success : AppColors.warning,
              ),
              title: Text(switch (_nanoStatus) {
                'available' => 'Sẵn sàng',
                'downloadable' => 'Có thể tải về',
                'downloading' => 'Đang tải...',
                _ => 'Thiết bị không hỗ trợ AICore',
              }),
              subtitle: const Text('Cần thiết bị hỗ trợ AICore (Pixel 9+, Galaxy S24+...)'),
              trailing: _nanoStatus == 'downloadable'
                  ? FilledButton(
                      onPressed: _nanoDownloading ? null : _downloadNano,
                      child: Text(_nanoDownloading ? 'Đang tải...' : 'Tải'),
                    )
                  : null,
            ),
          ),
          const Divider(height: 32),

          // --- Gemma 3n ---
          Text('Gemma 3n (LiteRT-LM)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    _gemmaReady ? Icons.check_circle : Icons.download_for_offline_outlined,
                    color: _gemmaReady ? AppColors.success : AppColors.onSurfaceMuted,
                  ),
                  title: Text(_gemmaReady ? 'Model đã sẵn sàng' : 'Chưa có model'),
                  subtitle: Text(_gemmaPath, style: const TextStyle(fontSize: 11)),
                  trailing: _gemmaReady
                      ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteGemma)
                      : null,
                ),
                if (!_gemmaReady) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Column(
                      children: [
                        TextField(
                          controller: _gemmaUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: 'URL model (.litertlm)',
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _hfTokenCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'HuggingFace token (model Gemma cần chấp nhận license)',
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        if (_gemmaProgress != null) ...[
                          LinearProgressIndicator(value: _gemmaProgress == 0 ? null : _gemmaProgress),
                          const SizedBox(height: 4),
                          Text(
                            'Đang tải ${((_gemmaProgress ?? 0) * 100).toStringAsFixed(0)}% (~3GB, nên dùng Wi-Fi)',
                            style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
                          ),
                        ] else
                          FilledButton.icon(
                            onPressed: _downloadGemma,
                            icon: const Icon(Icons.download),
                            label: const Text('Tải model (~3GB)'),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 32),

          // --- Cloud API ---
          Text('Cloud API (fallback)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Chỉ dùng khi thiết bị không chạy được AI on-device. Ảnh hóa đơn sẽ được gửi lên server của Google.',
            style: TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cloudKeyCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Gemini API key', isDense: true),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _cloudModelCtrl,
            decoration: const InputDecoration(
              labelText: 'Model (mặc định ${AiSettings.defaultCloudModel})',
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _saveCloud, child: const Text('Lưu Cloud API')),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
