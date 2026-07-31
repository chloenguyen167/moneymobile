import 'dart:io';

import 'package:flutter/services.dart';

/// Cầu nối tới native Android (AiBridge.kt) — OCR, Gemini Nano, Gemma/LiteRT-LM.
class AiNative {
  static const _channel = MethodChannel('tuchi/ai');

  static bool get supported => Platform.isAndroid;

  /// OCR text on-device bằng ML Kit Text Recognition (đầu vào cho lớp 0).
  static Future<String?> ocrText(String imagePath) async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('ocrText', {'imagePath': imagePath});
    } on PlatformException {
      return null;
    }
  }

  /// 'available' | 'downloadable' | 'downloading' | 'unavailable'
  static Future<String> nanoStatus() async {
    if (!supported) return 'unavailable';
    try {
      return await _channel.invokeMethod<String>('nanoStatus') ?? 'unavailable';
    } on PlatformException {
      return 'unavailable';
    }
  }

  static Future<void> nanoDownload() async {
    await _channel.invokeMethod<String>('nanoDownload');
  }

  static Future<String> nanoGenerate(String prompt, {String? imagePath}) async {
    final result = await _channel.invokeMethod<String>('nanoGenerate', {
      'prompt': prompt,
      if (imagePath != null) 'imagePath': imagePath,
    });
    if (result == null) throw Exception('Gemini Nano không trả kết quả');
    return result;
  }

  static Future<bool> gemmaAvailable(String modelPath) async {
    if (!supported) return false;
    try {
      return await _channel
              .invokeMethod<bool>('gemmaAvailable', {'modelPath': modelPath}) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  static Future<String> gemmaGenerate(
    String prompt, {
    String? imagePath,
    required String modelPath,
  }) async {
    final result = await _channel.invokeMethod<String>('gemmaGenerate', {
      'prompt': prompt,
      if (imagePath != null) 'imagePath': imagePath,
      'modelPath': modelPath,
    });
    if (result == null) throw Exception('Gemma không trả kết quả');
    return result;
  }

  static Future<void> gemmaUnload() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod('gemmaUnload');
    } on PlatformException {
      // ignore
    }
  }
}
