import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/models.dart';

class LearnedNotificationPattern {
  LearnedNotificationPattern({
    required this.packageName,
    required this.regexPattern,
    this.merchantHint,
    this.categoryHint,
  });

  final String packageName;
  final String regexPattern;
  final String? merchantHint;
  final String? categoryHint;

  factory LearnedNotificationPattern.fromJson(Map<String, dynamic> json) {
    return LearnedNotificationPattern(
      packageName: (json['package_name'] ?? '').toString(),
      regexPattern: (json['regex_pattern'] ?? '').toString(),
      merchantHint: json['merchant_hint']?.toString(),
      categoryHint: json['category_hint']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'package_name': packageName,
        'regex_pattern': regexPattern,
        if (merchantHint != null && merchantHint!.isNotEmpty)
          'merchant_hint': merchantHint,
        if (categoryHint != null && categoryHint!.isNotEmpty)
          'category_hint': categoryHint,
      };
}

class TemplateCache {
  TemplateCache(this._prefs);

  static const _templatesKey = 'notification_templates_v1';
  static const _learnedKey = 'notification_templates_learned_v1';
  static const _maxPerPackage = 12;
  final SharedPreferences _prefs;

  static Future<TemplateCache> create() async {
    return TemplateCache(await SharedPreferences.getInstance());
  }

  List<NotificationTemplateModel> load() {
    final raw = _prefs.getString(_templatesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => NotificationTemplateModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<NotificationTemplateModel> templates) async {
    final encoded = jsonEncode(
      templates
          .map(
            (t) => {
              'id': t.id,
              'package_name': t.packageName,
              'regex_pattern': t.regexPattern,
              'template_type': t.templateType,
              'version': t.version,
            },
          )
          .toList(),
    );
    await _prefs.setString(_templatesKey, encoded);
  }

  List<LearnedNotificationPattern> loadLearned() {
    final raw = _prefs.getString(_learnedKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => LearnedNotificationPattern.fromJson(e as Map<String, dynamic>))
        .where((e) => e.packageName.isNotEmpty && e.regexPattern.isNotEmpty)
        .toList();
  }

  Future<void> saveLearned(List<LearnedNotificationPattern> patterns) async {
    await _prefs.setString(
      _learnedKey,
      jsonEncode(patterns.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> upsertLearned(LearnedNotificationPattern pattern) async {
    final all = loadLearned();
    all.removeWhere(
      (p) =>
          p.packageName == pattern.packageName &&
          p.regexPattern == pattern.regexPattern,
    );
    all.insert(0, pattern);

    final trimmed = <LearnedNotificationPattern>[];
    final perPackageCount = <String, int>{};
    for (final p in all) {
      final current = perPackageCount[p.packageName] ?? 0;
      if (current >= _maxPerPackage) continue;
      perPackageCount[p.packageName] = current + 1;
      trimmed.add(p);
    }
    await saveLearned(trimmed);
  }
}
