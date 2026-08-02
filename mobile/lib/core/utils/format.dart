import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

String formatVnd(num amount) {
  final s = amount.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return '${buf.toString()} đ';
}

/// User-facing label for transaction source (no technical jargon).
String sourceLabel(String source) {
  switch (source) {
    case 'ocr':
      return 'Từ ảnh';
    case 'notification':
      return 'Từ thông báo';
    case 'email':
      return 'Từ email';
    case 'manual':
      return 'Nhập tay';
    default:
      return 'Khác';
  }
}

const incomeCategoryNames = {
  'Lương',
  'Thưởng',
  'Hoàn tiền',
  'Chuyển khoản đến',
  'Thu khác',
};

IconData categoryIconFor(String? name) {
  final n = (name ?? '').toLowerCase();
  if (n.contains('ăn') || n.contains('food') || n.contains('uống')) {
    return Icons.restaurant_rounded;
  }
  if (n.contains('đi lại') || n.contains('xe') || n.contains('transport')) {
    return Icons.directions_car_rounded;
  }
  if (n.contains('mua sắm') || n.contains('shopping')) {
    return Icons.shopping_bag_rounded;
  }
  if (n.contains('hóa đơn') || n.contains('tiện ích') || n.contains('điện')) {
    return Icons.bolt_rounded;
  }
  if (n.contains('sức khỏe') || n.contains('y tế')) {
    return Icons.local_hospital_rounded;
  }
  if (n.contains('giải trí') || n.contains('vui chơi')) {
    return Icons.sports_esports_rounded;
  }
  if (n.contains('học') || n.contains('giáo dục')) {
    return Icons.school_rounded;
  }
  if (n.contains('nhà') || n.contains('thuê')) {
    return Icons.home_rounded;
  }
  return Icons.payments_rounded;
}

double? parseVndInput(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

String formatMonthYear(DateTime d) {
  const months = [
    'tháng 1',
    'tháng 2',
    'tháng 3',
    'tháng 4',
    'tháng 5',
    'tháng 6',
    'tháng 7',
    'tháng 8',
    'tháng 9',
    'tháng 10',
    'tháng 11',
    'tháng 12',
  ];
  return '${months[d.month - 1]} ${d.year}';
}

String formatWeekdayDate(DateTime d) {
  const weekdays = [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  return '${weekdays[d.weekday - 1]}, ${DateFormat('dd/MM').format(d)}';
}

String formatFullDate(DateTime d) {
  const weekdays = [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  return '${weekdays[d.weekday - 1]}, ${DateFormat('dd/MM/yyyy').format(d)}';
}
