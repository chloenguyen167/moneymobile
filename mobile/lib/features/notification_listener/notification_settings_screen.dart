import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/local_notification_service.dart';
import '../../core/theme/app_colors.dart';
import 'notification_service.dart';

class NotificationSettingsScreen extends ConsumerStatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  ConsumerState<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends ConsumerState<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  bool _granted = false;
  bool _running = false;
  bool _enabled = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }

  Future<void> _onResumed() async {
    if (!Platform.isAndroid) return;
    final service = ref.read(notificationCaptureProvider);
    final granted = await service.isPermissionGranted();
    final enabled = await service.isEnabled();
    if (granted && enabled && !service.isRunning) {
      await LocalNotificationService.instance.requestNotificationPermission();
      await service.start();
    }
    await _checkStatus();
  }

  Future<void> _checkStatus() async {
    if (!Platform.isAndroid) return;
    final service = ref.read(notificationCaptureProvider);
    final granted = await service.isPermissionGranted();
    final enabled = await service.isEnabled();
    if (mounted) {
      setState(() {
        _granted = granted;
        _enabled = enabled;
        _running = service.isRunning;
      });
    }
  }

  Future<void> _requestPermission() async {
    setState(() => _loading = true);
    final service = ref.read(notificationCaptureProvider);
    await LocalNotificationService.instance.requestNotificationPermission();
    final granted = await service.requestPermission();
    // System settings may open; mark enabled so resume can start capture.
    if (granted) {
      await service.start();
      ref.read(alertPollerProvider).start();
    } else {
      await service.setEnabled(true);
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
      await LocalNotificationService.instance.requestNotificationPermission();
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
          if (!Platform.isAndroid) ..._iosBody(context),
          if (Platform.isAndroid) ..._androidBody(context),
        ],
      ),
    );
  }

  List<Widget> _iosBody(BuildContext context) {
    return [
      Text(
        'Theo dõi giao dịch trên iOS',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'iOS không cho phép đọc thông báo app ngân hàng/ví. '
        'Dùng Gmail, dán SMS, hoặc quét ảnh — cùng mục tiêu như Android.',
        style: TextStyle(color: AppColors.onSurfaceMuted),
      ),
      const SizedBox(height: 24),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.mail_outline, color: AppColors.primary),
              title: const Text('Đồng bộ Gmail'),
              subtitle: const Text('Đọc email giao dịch ngân hàng / ví'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/email'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.playlist_add, color: AppColors.primary),
              title: const Text('Nhập nhanh / dán SMS'),
              subtitle: const Text('Dán nội dung SMS chuyển khoản'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/quick-add'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
              title: const Text('Quét hóa đơn / screenshot'),
              subtitle: const Text('Chụp hoặc chọn ảnh thanh toán'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/capture'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      Card(
        color: AppColors.primary.withValues(alpha: 0.12),
        child: const ListTile(
          leading: Icon(Icons.info_outline, color: AppColors.warning),
          title: Text('Giới hạn hệ điều hành'),
          subtitle: Text(
            'Notification Access chỉ có trên Android. '
            'Cảnh báo ngân sách vẫn gửi local notification trên iOS.',
          ),
        ),
      ),
    ];
  }

  List<Widget> _androidBody(BuildContext context) {
    return [
      Text(
        'Bắt thông báo giao dịch',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 8),
      const Text(
        'Tuchi đọc thông báo ngân hàng/ví trên thiết bị, trích xuất số tiền '
        'và merchant — không gửi nội dung thông báo gốc lên server.',
        style: TextStyle(color: AppColors.onSurfaceMuted),
      ),
      const SizedBox(height: 24),
      Card(
        child: SwitchListTile(
          title: const Text('Bật theo dõi tự động'),
          subtitle: Text(
            _granted
                ? (_running
                    ? 'Đang theo dõi'
                    : (_enabled ? 'Đang chờ quyền / khởi động' : 'Quyền đã cấp'))
                : 'Cần cấp quyền Notification Access',
          ),
          value: _running && _granted,
          onChanged: _loading ? null : _toggleService,
        ),
      ),
      if (!_granted) ...[
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _loading ? null : _requestPermission,
          icon: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.notifications_active),
          label: const Text('Cấp quyền Notification Access'),
        ),
      ],
      const SizedBox(height: 24),
      Text('App được hỗ trợ', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final entry in supportedNotificationPackages.entries)
        _SupportedAppTile(name: entry.value, package: entry.key),
      const SizedBox(height: 16),
      const Text(
        'Template regex được cập nhật từ server — không cần cập nhật app.',
        style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
      ),
      const SizedBox(height: 24),
      Text('Cách khác', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Đồng bộ Gmail'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/email'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.playlist_add),
              title: const Text('Nhập nhanh / dán SMS'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/quick-add'),
            ),
          ],
        ),
      ),
    ];
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
