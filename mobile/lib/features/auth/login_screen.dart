import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/providers/providers.dart';
import '../../core/theme/app_colors.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController(text: 'demo@tuchi.app');
  final _password = TextEditingController(text: 'demo123');
  final _name = TextEditingController(text: 'Demo User');
  final _serverUrl = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;
  bool _showServer = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _serverUrl.text = AppConfig.apiBaseUrl;
    _showServer = AppConfig.needsManualServerUrl;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _serverUrl.dispose();
    super.dispose();
  }

  Future<void> _saveServer() async {
    await AppConfig.saveApiBaseUrl(_serverUrl.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server: ${AppConfig.apiBaseUrl}')),
      );
    }
  }

  Future<void> _testServer() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppConfig.saveApiBaseUrl(_serverUrl.text);
      final ok = await ref.read(apiClientProvider).pingHealth();
      if (!ok) throw Exception('HTTP health check failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kết nối OK: ${AppConfig.apiBaseUrl}')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Không kết nối được backend.\n'
          'URL: ${AppConfig.apiBaseUrl}\n\n'
          '${AppConfig.ipadHint}\n\n'
          'Trên Mac chạy: ipconfig getifaddr en0');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_showServer || _serverUrl.text.trim().isNotEmpty) {
        await AppConfig.saveApiBaseUrl(_serverUrl.text);
      }
      final repo = ref.read(repositoryProvider);
      if (_isRegister) {
        await repo.register(_email.text.trim(), _password.text, displayName: _name.text.trim());
      } else {
        await repo.login(_email.text.trim(), _password.text);
      }
      ref.invalidate(authTokenProvider);
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.account_balance_wallet, size: 64, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Tuchi',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quản lý chi tiêu thông minh — OCR + AI',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceMuted),
                  ),
                  const SizedBox(height: 32),
                  if (AppConfig.needsManualServerUrl || _showServer) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        AppConfig.ipadHint,
                        style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _serverUrl,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Backend URL',
                        hintText: 'http://192.168.1.5:8000/api/v1',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _loading ? null : _testServer,
                            child: const Text('Thử kết nối'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: _loading ? null : _saveServer,
                            child: const Text('Lưu URL'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ] else
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(() => _showServer = true),
                        child: Text('Server: ${AppConfig.apiBaseUrl}', style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                  if (_isRegister)
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Tên hiển thị'),
                    ),
                  if (_isRegister) const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Mật khẩu'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: _loading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_isRegister ? 'Đăng ký' : 'Đăng nhập'),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : () => setState(() => _isRegister = !_isRegister),
                    child: Text(_isRegister ? 'Đã có tài khoản? Đăng nhập' : 'Chưa có tài khoản? Đăng ký'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
