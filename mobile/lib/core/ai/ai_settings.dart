import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runtime AI đang chọn — đổi được trong Settings, không cần sửa code.
enum AiEngineMode {
  auto,
  nano, // ML Kit GenAI (Gemini Nano, on-device)
  gemma, // LiteRT-LM (Gemma 3n, on-device)
  cloud; // Cloud API (Gemini) — fallback

  static AiEngineMode parse(String? raw) =>
      AiEngineMode.values.where((e) => e.name == raw).firstOrNull ?? AiEngineMode.auto;
}

class AiSettings {
  AiSettings({
    required this.mode,
    required this.cloudApiKey,
    required this.cloudModel,
    required this.gemmaModelUrl,
    required this.hfToken,
  });

  final AiEngineMode mode;
  final String cloudApiKey;
  final String cloudModel;
  final String gemmaModelUrl;
  final String hfToken;

  static const _kMode = 'ai_engine_mode';
  static const _kCloudKey = 'ai_cloud_api_key';
  static const _kCloudModel = 'ai_cloud_model';
  static const _kGemmaUrl = 'ai_gemma_model_url';
  static const _kHfToken = 'ai_hf_token';

  static const defaultCloudModel = 'gemini-2.5-flash';
  static const defaultGemmaUrl =
      'https://huggingface.co/google/gemma-3n-E2B-it-litert-lm/resolve/main/gemma-3n-E2B-it-int4.litertlm';

  static Future<AiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AiSettings(
      mode: AiEngineMode.parse(prefs.getString(_kMode)),
      cloudApiKey: prefs.getString(_kCloudKey) ?? '',
      cloudModel: prefs.getString(_kCloudModel) ?? defaultCloudModel,
      gemmaModelUrl: prefs.getString(_kGemmaUrl) ?? defaultGemmaUrl,
      hfToken: prefs.getString(_kHfToken) ?? '',
    );
  }

  static Future<void> save({
    AiEngineMode? mode,
    String? cloudApiKey,
    String? cloudModel,
    String? gemmaModelUrl,
    String? hfToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (mode != null) await prefs.setString(_kMode, mode.name);
    if (cloudApiKey != null) await prefs.setString(_kCloudKey, cloudApiKey.trim());
    if (cloudModel != null) {
      await prefs.setString(
        _kCloudModel,
        cloudModel.trim().isEmpty ? defaultCloudModel : cloudModel.trim(),
      );
    }
    if (gemmaModelUrl != null) {
      await prefs.setString(
        _kGemmaUrl,
        gemmaModelUrl.trim().isEmpty ? defaultGemmaUrl : gemmaModelUrl.trim(),
      );
    }
    if (hfToken != null) await prefs.setString(_kHfToken, hfToken.trim());
  }

  /// Đường dẫn cố định của file model Gemma trong bộ nhớ app.
  static Future<String> gemmaModelPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final models = Directory('${dir.path}/models');
    if (!models.existsSync()) models.createSync(recursive: true);
    return '${models.path}/gemma-3n.litertlm';
  }
}
