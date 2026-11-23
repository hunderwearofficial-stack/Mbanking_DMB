import 'package:intl/intl.dart';

import '../money/money.dart';

class CurrencyFormatter {
  static final NumberFormat _thousands = NumberFormat.decimalPattern('id_ID');

  static String formatRupiah(Money? amount) {
    if (amount == null) return '-';
    final abs = amount.sen.abs();
    var s = 'Rp ${_thousands.format(abs ~/ 100)}';
    final frac = abs % 100;
    if (frac != 0) s += ',${frac.toString().padLeft(2, '0')}';
    return amount.isNegative ? '-$s' : s;
  }

  /// Bank transactions are shown in the bank's timezone (WIB, UTC+7) regardless of the
  /// device timezone (audit MA-01). A timestamp with an offset/Z is converted; one without
  /// an offset is already bank wall-clock time and is shown unchanged.
  static const Duration _wibOffset = Duration(hours: 7);

  static DateTime? toWib(dynamic date) {
    if (date == null) return null;
    if (date is DateTime) {
      return date.toUtc().add(_wibOffset);
    }
    if (date is String) {
      final parsed = DateTime.tryParse(date.trim());
      if (parsed == null) return null;
      return parsed.isUtc ? parsed.add(_wibOffset) : parsed;
    }
    return null;
  }

  static String formatDate(dynamic date) {
    if (date == null) return '-';
    final wib = toWib(date);
    if (wib == null) return date.toString();
    return '${DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(wib)} WIB';
  }

  static String formatDateFull(dynamic date) {
    return formatDate(date);
  }

  static String formatDateShort(dynamic date) {
    if (date == null) return '-';
    final wib = toWib(date);
    if (wib == null) return date.toString();
    return DateFormat('dd MMM yyyy', 'id_ID').format(wib);
  }
}

