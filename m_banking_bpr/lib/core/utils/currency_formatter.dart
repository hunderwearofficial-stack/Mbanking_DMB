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

  static String formatDate(dynamic date) {
    if (date == null) return '-';
    DateTime parsed;
    if (date is DateTime) {
      parsed = date;
    } else if (date is String) {
      try {
        parsed = DateTime.parse(date).toLocal();
      } catch (_) {
        return date;
      }
    } else {
      return date.toString();
    }

    return '${DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(parsed)} WIB';
  }

  static String formatDateFull(dynamic date) {
    return formatDate(date);
  }

  static String formatDateShort(dynamic date) {
    if (date == null) return '-';
    DateTime parsed;
    if (date is DateTime) {
      parsed = date;
    } else if (date is String) {
      try {
        parsed = DateTime.parse(date).toLocal();
      } catch (_) {
        return date;
      }
    } else {
      return date.toString();
    }

    return DateFormat('dd MMM yyyy', 'id_ID').format(parsed);
  }
}

