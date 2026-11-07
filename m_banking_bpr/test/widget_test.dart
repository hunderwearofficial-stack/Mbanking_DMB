import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/core/network/api_client.dart';
import 'package:m_banking_bpr/core/security/secure_storage_service.dart';
import 'package:m_banking_bpr/data/repositories/account_repository.dart';
import 'package:m_banking_bpr/data/repositories/auth_repository.dart';
import 'package:m_banking_bpr/data/repositories/transaction_repository.dart';
import 'package:m_banking_bpr/main.dart';

void main() {
  testWidgets('MBanking BPR App Smoke Test', (WidgetTester tester) async {
    final storage = SecureStorageService();
    final apiClient = ApiClient(secureStorage: storage);
    final authRepo = AuthRepository(apiClient: apiClient, secureStorage: storage);
    final accRepo = AccountRepository(apiClient: apiClient);
    final txRepo = TransactionRepository(apiClient: apiClient);

    await tester.pumpWidget(
      MBankingBPRApp(
        authRepository: authRepo,
        accountRepository: accRepo,
        transactionRepository: txRepo,
      ),
    );

    // Verify app widget boots cleanly
    expect(find.byType(MBankingBPRApp), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
  });
}
