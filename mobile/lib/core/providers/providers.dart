import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;

import '../../core/network/api_client.dart';
import '../../data/models/models.dart';
import '../../data/remote/tuchi_repository.dart';

final secureStorageProvider = Provider((_) => const FlutterSecureStorage());

final apiClientProvider = Provider((ref) => ApiClient(ref.watch(secureStorageProvider)));

final repositoryProvider = Provider((ref) => TuchiRepository(ref.watch(apiClientProvider)));

final authTokenProvider = FutureProvider<String?>((ref) async {
  return ref.watch(apiClientProvider).token;
});

final transactionsProvider = FutureProvider<List<TransactionModel>>((ref) async {
  return ref.watch(repositoryProvider).getTransactions();
});

final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) async {
  return ref.watch(repositoryProvider).getCategories();
});

final budgetsProvider = FutureProvider<List<BudgetModel>>((ref) async {
  return ref.watch(repositoryProvider).getBudgets();
});

final analyticsProvider = FutureProvider<AnalyticsSummaryModel>((ref) async {
  return ref.watch(repositoryProvider).getAnalytics();
});

final alertsProvider = FutureProvider<List<AlertModel>>((ref) async {
  return ref.watch(repositoryProvider).getAlerts();
});

final subscriptionsProvider = FutureProvider<List<SubscriptionModel>>((ref) async {
  return ref.watch(repositoryProvider).getSubscriptions();
});

final pipelineHealthProvider = FutureProvider<PipelineHealthModel>((ref) async {
  return ref.watch(repositoryProvider).getPipelineHealth();
});

final notificationTemplatesProvider = FutureProvider<List<NotificationTemplateModel>>((ref) async {
  return ref.watch(repositoryProvider).getNotificationTemplates();
});

/// Edge Gate IQA — Laplacian variance blur detection (MVP).
class ImageQualityResult {
  ImageQualityResult({required this.isLowQuality, required this.blurScore, required this.message});

  final bool isLowQuality;
  final double blurScore;
  final String message;
}

ImageQualityResult evaluateImageQuality(Uint8List bytes, {double blurThreshold = 100}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return ImageQualityResult(isLowQuality: true, blurScore: 0, message: 'Không đọc được ảnh');
  }

  final gray = img.grayscale(decoded);
  final resized = img.copyResize(gray, width: 320);
  double variance = 0;
  final w = resized.width;
  final h = resized.height;

  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final c = resized.getPixel(x, y).r;
      final lap = (-4 * c +
              resized.getPixel(x - 1, y).r +
              resized.getPixel(x + 1, y).r +
              resized.getPixel(x, y - 1).r +
              resized.getPixel(x, y + 1).r)
          .toDouble();
      variance += lap * lap;
    }
  }
  variance /= ((w - 2) * (h - 2));

  if (variance < blurThreshold) {
    return ImageQualityResult(
      isLowQuality: true,
      blurScore: variance,
      message: 'Ảnh bị mờ — vui lòng chụp lại rõ hơn',
    );
  }
  return ImageQualityResult(
    isLowQuality: false,
    blurScore: variance,
    message: 'Chất lượng ảnh OK',
  );
}

String formatVnd(num amount) {
  final s = amount.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${buf.toString()} đ';
}
