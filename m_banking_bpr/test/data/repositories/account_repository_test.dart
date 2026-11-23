import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/network/api_exception.dart';
import 'package:m_banking_bpr/data/repositories/account_repository.dart';

import '../../helpers/fake_api_client.dart';

/// Consumer protection (audit DMB-026 / DMB-035): when the backend or Core Banking
/// is unavailable the failure must reach the screen (retry message). It must never be
/// turned into fabricated data nor into an "empty portfolio".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = AccountRepository(apiClient: FailingApiClient());
  final isOutage = throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 503));

  test('loans: outage is propagated, not shown as empty/dummy', () {
    expect(repo.getLoans(cifNumber: '000000000001'), isOutage);
    expect(repo.getLoanDetail('0000000001', cifNumber: '000000000001'), isOutage);
  });

  test('deposits: outage is propagated, not shown as empty/dummy', () {
    expect(repo.getDeposits(cifNumber: '000000000001'), isOutage);
    expect(repo.getDepositDetail('0000000001', cifNumber: '000000000001'), isOutage);
  });

  test('product catalogue: outage is propagated', () {
    expect(repo.getProductsCatalog(), isOutage);
  });

  test('balance: outage is propagated', () {
    expect(repo.getBalance(), isOutage);
  });
}
