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

ParsedNotification? parseNotificationText(
  String text,
  String regexPattern, {
  String? packageName,
}) {
  try {
    final reg = RegExp(regexPattern, caseSensitive: false, dotAll: true);
    final match = reg.firstMatch(text);
    if (match == null) return null;

    final amountStr = match.namedGroup('amount')?.replaceAll(',', '').replaceAll('.', '') ?? '';
    final amount = double.tryParse(amountStr);
    if (amount == null) return null;

    return ParsedNotification(
      amount: amount,
      merchant: match.namedGroup('merchant')?.trim(),
      sign: match.namedGroup('sign') ?? '-',
      time: match.namedGroup('time'),
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
    final amountStr = match.namedGroup('amount')?.replaceAll(',', '').replaceAll('.', '') ?? '';
    final amount = double.tryParse(amountStr);
    if (amount != null && amount > 0) {
      return ParsedNotification(
        amount: amount,
        sign: match.namedGroup('sign') ?? '-',
        packageName: packageName,
      );
    }
  }
  return null;
}
