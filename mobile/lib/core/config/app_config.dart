import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static const _envApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const prefsKey = 'api_base_url';
  static const offlinePrefsKey = 'offline_mode';

  static String? _savedUrl;
  static bool _offlineMode = false;

  /// Gọi trong main() trước runApp.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _savedUrl = prefs.getString(prefsKey);
    _offlineMode = prefs.getBool(offlinePrefsKey) ?? false;
  }

  static bool get offlineMode => _offlineMode;

  /// Chế độ demo: không cần backend, lưu giao dịch trên máy, AI vẫn on-device.
  static Future<void> setOfflineMode(bool enabled) async {
    _offlineMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(offlinePrefsKey, enabled);
  }

  static Future<void> saveApiBaseUrl(String url) async {
    var trimmed = url.trim();
    if (trimmed.isEmpty) {
      _savedUrl = null;
      await SharedPreferences.getInstance().then((p) => p.remove(prefsKey));
      return;
    }
    trimmed = trimmed.replaceAll(RegExp(r'/+$'), '');
    if (!trimmed.endsWith('/api/v1')) {
      trimmed = trimmed.endsWith('/api') ? '$trimmed/v1' : '$trimmed/api/v1';
    }
    _savedUrl = trimmed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, trimmed);
  }

  static String get apiBaseUrl {
    if (_savedUrl != null && _savedUrl!.isNotEmpty) return _savedUrl!;
    if (_envApiBaseUrl.isNotEmpty) return _envApiBaseUrl;
    if (Platform.isAndroid) return 'http://10.0.2.2:8000/api/v1';
    // Chỉ đúng với iOS Simulator — iPad thật phải nhập IP Mac
    return 'http://localhost:8000/api/v1';
  }

  /// iPad/iPhone thật không dùng được localhost (kể cả cắm USB).
  static bool get needsManualServerUrl {
    if (!Platform.isIOS) return false;
    final u = apiBaseUrl.toLowerCase();
    return u.contains('localhost') || u.contains('127.0.0.1');
  }

  static String get ipadHint =>
      'iPad: nhập http://<IP-Mac>:8000/api/v1 — Mac & iPad cùng Wi‑Fi. '
      'Cắm USB không thay localhost.';
}
