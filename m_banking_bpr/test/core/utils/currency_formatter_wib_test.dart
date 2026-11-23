import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:m_banking_bpr/core/utils/currency_formatter.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  test('a WIB timestamp from the server keeps its date and time (audit MA-01)', () {
    // Backend now sends the CBS wall-clock time with its offset.
    expect(CurrencyFormatter.formatDate('2026-11-20T21:30:00+07:00'), '20 Nov 2026, 21:30 WIB');
    expect(CurrencyFormatter.formatDateShort('2026-11-20T21:30:00+07:00'), '20 Nov 2026');
  });

  test('a UTC timestamp is shown in WIB whatever the device timezone', () {
    expect(CurrencyFormatter.formatDate('2026-11-20T14:30:00Z'), '20 Nov 2026, 21:30 WIB');
    expect(CurrencyFormatter.formatDate('2026-11-20T18:00:00Z'), '21 Nov 2026, 01:00 WIB');
  });

  test('a timestamp without offset is already bank time', () {
    expect(CurrencyFormatter.formatDate('2026-11-20 21:30:00'), '20 Nov 2026, 21:30 WIB');
  });

  test('unreadable values are shown as received', () {
    expect(CurrencyFormatter.formatDate(null), '-');
    expect(CurrencyFormatter.formatDate('bukan tanggal'), 'bukan tanggal');
  });
}
