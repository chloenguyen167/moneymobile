import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/models.dart';

class TemplateCache {
  TemplateCache(this._prefs);

  static const _key = 'notification_templates_v1';
  final SharedPreferences _prefs;

  static Future<TemplateCache> create() async {
    return TemplateCache(await SharedPreferences.getInstance());
  }

  List<NotificationTemplateModel> load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => NotificationTemplateModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> save(List<NotificationTemplateModel> templates) async {
    final encoded = jsonEncode(templates.map((t) => {
          'id': t.id,
          'package_name': t.packageName,
          'regex_pattern': t.regexPattern,
          'template_type': t.templateType,
          'version': t.version,
        }).toList());
    await _prefs.setString(_key, encoded);
  }
}
