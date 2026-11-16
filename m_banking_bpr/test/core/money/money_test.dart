import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/money/money.dart';
import 'package:m_banking_bpr/core/utils/currency_formatter.dart';

/// Exact money handling on the client (audit DMB-015).
void main() {
  test('parses API values exactly (int, double, string)', () {
    expect(Money.parse(15000).sen, 1500000);
    expect(Money.parse(15000.5).sen, 1500050);
    expect(Money.parse('15000.50').sen, 1500050);
    expect(Money.parse(0.1).sen + Money.parse(0.2).sen, Money.parse(0.3).sen); // no float drift
    expect(Money.parse(1797507397).sen, 179750739700);
  });

  test('rejects malformed or over-precise values', () {
    for (final bad in ['abc', '1.001', '12,5', double.nan, double.infinity, null]) {
      expect(() => Money.parse(bad), throwsFormatException, reason: '$bad');
    }
    expect(Money.tryParse(null), isNull);
    expect(Money.tryParse('x'), isNull);
  });

  test('API string is exact and round-trips', () {
    expect(Money.rupiah(150000).toApiString(), '150000');
    expect(const Money.sen(1500050).toApiString(), '15000.5');
    expect(Money.parse(Money.parse('2500.75').toApiString()).sen, 250075);
  });

  test('formatting never invents a zero for a missing amount', () {
    expect(CurrencyFormatter.formatRupiah(Money.rupiah(1500000)), 'Rp 1.500.000');
    expect(CurrencyFormatter.formatRupiah(const Money.sen(1500050)), 'Rp 15.000,50');
    expect(CurrencyFormatter.formatRupiah(null), '-');
  });
}
