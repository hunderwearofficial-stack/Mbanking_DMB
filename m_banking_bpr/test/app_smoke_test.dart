import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/network/api_client.dart';
import 'package:m_banking_bpr/core/security/secure_storage_service.dart';
import 'package:m_banking_bpr/data/repositories/account_repository.dart';
import 'package:m_banking_bpr/data/repositories/auth_repository.dart';
import 'package:m_banking_bpr/main.dart';

void main() {
  testWidgets('app builds and shows the splash flow', (WidgetTester tester) async {
    final storage = SecureStorageService();
    final apiClient = ApiClient(secureStorage: storage);
    final authRepo = AuthRepository(apiClient: apiClient, secureStorage: storage);
    final accRepo = AccountRepository(apiClient: apiClient);

    await tester.pumpWidget(MBankingBPRApp(authRepository: authRepo, accountRepository: accRepo));
    expect(find.byType(MBankingBPRApp), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    // The splash screen schedules a 10 s safety timeout; tear down the tree and let it elapse.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 11));
  });
}
