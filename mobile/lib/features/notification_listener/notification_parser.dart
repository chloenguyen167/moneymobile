/// On-device notification parser — templates from backend cache.
library;

class ParsedNotification {
  ParsedNotification({
    required this.amount,
    this.merchant,
    this.sign = '-',
    this.time,
    this.packageName,
  });

  final double amount;
  final String? merchant;
  final String sign;
  final String? time;
  final String? packageName;
}

/// Normalize template signs (`+/-`, `chi`/`nhan`, etc.) to `+` or `-`.
String normalizeNotificationSign(String? raw) {
  if (raw == null || raw.isEmpty) return '-';
  final s = raw.trim().toLowerCase();
  if (s == '+' || s == 'nhan' || s == 'nhận' || s == 'credit' || s == 'in') {
    return '+';
  }
  return '-';
}

String? _namedGroup(RegExpMatch match, String name) {
  try {
    return match.namedGroup(name);
  } catch (_) {
    return null;
  }
}

ParsedNotification? parseNotificationText(
  String text,
  String regexPattern, {
  String? packageName,
}) {
  try {
    final reg = RegExp(regexPattern, caseSensitive: false, dotAll: true);
    final match = reg.firstMatch(text);
    if (match == null) return null;

    final amountStr = _namedGroup(match, 'amount')?.replaceAll(',', '').replaceAll('.', '') ?? '';
    final amount = double.tryParse(amountStr);
    if (amount == null) return null;

    return ParsedNotification(
      amount: amount,
      merchant: _namedGroup(match, 'merchant')?.trim(),
      sign: normalizeNotificationSign(_namedGroup(match, 'sign')),
      time: _namedGroup(match, 'time'),
      packageName: packageName,
    );
  } catch (_) {
    return null;
  }
}

/// Generic fallback for unmatched bank/wallet notifications.
ParsedNotification? parseGenericAmount(String text, {String? packageName}) {
  final patterns = [
    RegExp(r'(?<sign>[+-])?\s*(?<amount>[\d.,]+)\s*(?:VND|đ|vnđ)', caseSensitive: false),
    RegExp(r'(?:chi|thanh toán|payment).*?(?<amount>[\d.,]+)', caseSensitive: false),
  ];
  for (final reg in patterns) {
    final match = reg.firstMatch(text);
    if (match == null) continue;
    final amountStr = _namedGroup(match, 'amount')?.replaceAll(',', '').replaceAll('.', '') ?? '';
    final amount = double.tryParse(amountStr);
    if (amount != null && amount > 0) {
      return ParsedNotification(
        amount: amount,
        sign: normalizeNotificationSign(_namedGroup(match, 'sign')),
        packageName: packageName,
      );
    }
  }
  return null;
}
