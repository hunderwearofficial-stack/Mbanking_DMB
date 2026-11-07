import 'package:intl/intl.dart';

class CurrencyFormatter {
  static final NumberFormat _rupiahFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  static String formatRupiah(num? amount) {
    if (amount == null) return 'Rp 0';
    return _rupiahFormat.format(amount);
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

    return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(parsed) + ' WIB';
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

