import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/constants/api_endpoints.dart';

/// The mobile client must call the same paths the backend router exposes (cmd/api/app.go).
void main() {
  test('session and transaction endpoints match the backend contract', () {
    expect(ApiEndpoints.logout, '/api/v1/auth/logout');
    expect(ApiEndpoints.transfer, '/api/v1/transaction/transfer');
  });
}
