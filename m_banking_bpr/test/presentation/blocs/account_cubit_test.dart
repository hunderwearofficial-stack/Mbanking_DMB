import 'package:flutter_test/flutter_test.dart';
import 'package:m_banking_bpr/data/repositories/account_repository.dart';
import 'package:m_banking_bpr/presentation/blocs/account/account_cubit.dart';
import 'package:m_banking_bpr/presentation/blocs/account/account_state.dart';

import '../../helpers/fake_api_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('balance outage yields AccountError with the server message, never a balance', () async {
    final cubit = AccountCubit(accountRepository: AccountRepository(apiClient: FailingApiClient()));
    final error = await cubit.loadDashboardData();
    expect(error, contains('belum dapat ditampilkan'));
    expect(cubit.state, isA<AccountError>());
    expect(cubit.state, isNot(isA<AccountLoaded>()));
    await cubit.close();
  });

  test('silent refresh failure is reported to the caller', () async {
    final cubit = AccountCubit(accountRepository: AccountRepository(apiClient: FailingApiClient()));
    final error = await cubit.refresh();
    expect(error, isNotNull);
    await cubit.close();
  });
}
