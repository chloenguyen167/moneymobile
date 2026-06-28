import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import 'notification_service.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen> {
  bool _granted = false;
  bool _running = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (!Platform.isAndroid) return;
    final service = ref.read(notificationCaptureProvider);
    final granted = await service.isPermissionGranted();
    if (mounted) {
      setState(() {
        _granted = granted;
        _running = service.isRunning;
      });
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _loading = true);
    final service = ref.read(notificationCaptureProvider);
    final granted = await service.requestPermission();
    if (granted) {
      await service.start();
      ref.read(alertPollerProvider).start();
    }
    await _checkStatus();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggleService(bool enable) async {
    final service = ref.read(notificationCaptureProvider);
    if (enable) {
      if (!_granted) {
        await _requestPermission();
        return;
      }
      await service.start();
      ref.read(alertPollerProvider).start();
    } else {
      await service.stop();
    }
    await _checkStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Theo dõi giao dịch')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!Platform.isAndroid)
            Card(
              color: AppColors.primary.withValues(alpha: 0.15),
              child: const ListTile(
                leading: Icon(Icons.info_outline, color: AppColors.warning),
                title: Text('Chỉ hỗ trợ Android'),
                subtitle: Text(
                  'iOS không cho phép đọc thông báo app khác. '
                  'Dùng chụp hóa đơn hoặc nhập tay trên iOS.',
                ),
              ),
            ),
          if (Platform.isAndroid) ...[
            Text(
              'Bắt thông báo giao dịch',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Tuchi đọc thông báo ngân hàng/ví trên thiết bị, trích xuất số tiền '
              'và merchant — không gửi nội dung thông báo gốc lên server.',
              style: const TextStyle(color: AppColors.onSurfaceMuted),
            ),
            const SizedBox(height: 24),
            Card(
              child: SwitchListTile(
                title: const Text('Bật theo dõi tự động'),
                subtitle: Text(_granted ? 'Quyền đã cấp' : 'Cần cấp quyền Notification Access'),
                value: _running && _granted,
                onChanged: _loading ? null : _toggleService,
              ),
            ),
            if (!_granted) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _requestPermission,
                icon: _loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.notifications_active),
                label: const Text('Cấp quyền Notification Access'),
              ),
            ],
            const SizedBox(height: 24),
            Text('App được hỗ trợ', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const _SupportedAppTile(name: 'Vietcombank', package: 'com.VCB'),
            const _SupportedAppTile(name: 'MB Bank', package: 'com.mbmobile'),
            const _SupportedAppTile(name: 'MoMo', package: 'com.mservice.momotransfer'),
            const _SupportedAppTile(name: 'ZaloPay', package: 'com.zing.zalo'),
            const SizedBox(height: 16),
            Text(
              'Template regex được cập nhật từ server — không cần cập nhật app.',
              style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _SupportedAppTile extends StatelessWidget {
  const _SupportedAppTile({required this.name, required this.package});

  final String name;
  final String package;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.account_balance, size: 20),
      title: Text(name),
      trailing: Text(package, style: const TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted)),
    );
  }
}
