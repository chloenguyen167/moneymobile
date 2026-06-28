import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/models.dart';

/// iOS email parsing — connect Gmail via OAuth (Phase 3).
class EmailSettingsScreen extends ConsumerStatefulWidget {
  const EmailSettingsScreen({super.key});

  @override
  ConsumerState<EmailSettingsScreen> createState() => _EmailSettingsScreenState();
}

class _EmailSettingsScreenState extends ConsumerState<EmailSettingsScreen> {
  EmailStatusModel? _status;
  bool _loading = false;
  String? _error;
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final status = await ref.read(repositoryProvider).getEmailStatus();
      if (mounted) setState(() => _status = status);
    } catch (_) {}
  }

  Future<void> _connectGmail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final url = await ref.read(repositoryProvider).getGmailOAuthUrl();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitCode() async {
    if (_codeCtrl.text.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await ref.read(repositoryProvider).connectGmail(_codeCtrl.text.trim());
      setState(() => _status = status);
      ref.invalidate(transactionsProvider);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sync() async {
    setState(() => _loading = true);
    try {
      final count = await ref.read(repositoryProvider).syncEmails();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã sync $count giao dịch từ email')));
        ref.invalidate(transactionsProvider);
      }
      await _loadStatus();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _disconnect() async {
    await ref.read(repositoryProvider).disconnectEmail();
    setState(() => _status = EmailStatusModel(connected: false));
  }

  @override
  Widget build(BuildContext context) {
    final connected = _status?.connected ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Email (iOS)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.secondary.withValues(alpha: 0.1),
            child: const ListTile(
              leading: Icon(Icons.email, color: AppColors.secondary),
              title: Text('Dành cho iOS'),
              subtitle: Text(
                'Apple không cho phép đọc notification app khác. '
                'Kết nối Gmail để tự động lấy biên nhận từ ngân hàng/ví qua email.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (connected) ...[
            ListTile(
              leading: const Icon(Icons.check_circle, color: AppColors.success),
              title: Text(_status!.email ?? 'Gmail đã kết nối'),
              subtitle: _status!.lastSyncAt != null ? Text('Sync lần cuối: ${_status!.lastSyncAt}') : null,
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _sync,
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync email'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: _disconnect, child: const Text('Ngắt')),
              ],
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _loading ? null : _connectGmail,
              icon: const Icon(Icons.link),
              label: const Text('Kết nối Gmail'),
            ),
            const SizedBox(height: 16),
            Text('Sau khi đăng nhập Google, dán authorization code:', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _codeCtrl,
              decoration: const InputDecoration(hintText: 'Authorization code'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _loading ? null : _submitCode, child: const Text('Xác nhận kết nối')),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
