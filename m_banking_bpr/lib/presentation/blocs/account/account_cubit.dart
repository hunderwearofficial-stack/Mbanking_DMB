import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/account_repository.dart';
import 'account_state.dart';

class AccountCubit extends Cubit<AccountState> {
  final AccountRepository accountRepository;

  AccountCubit({required this.accountRepository}) : super(AccountInitial());

  /// Loads balance & mutations. Returns null on success, or a user-facing error
  /// message. On a silent refresh failure the previous state is kept and the
  /// caller must inform the user that the data could not be updated.
  Future<String?> loadDashboardData({String? accountNumber, bool isSilentRefresh = false}) async {
    final bool keepVisible = (state is AccountLoaded) ? (state as AccountLoaded).isBalanceVisible : false;
    if (!isSilentRefresh) {
      emit(AccountLoading());
    }
    try {
      // Hit all 3 CBS endpoints (/api/savings-account-balance, /api/nasabah, /api/savings-accounts) + Mutations in parallel
      final results = await Future.wait([
        accountRepository.getBalance(accountNumber: accountNumber),
        accountRepository.getMutations(limit: 10, accountNumber: accountNumber),
        accountRepository.getCustomerProfile().catchError((_) => <String, dynamic>{}),
        accountRepository.getSavingsAccounts().catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final account = results[0] as dynamic;
      final mutations = results[1] as dynamic;

      emit(AccountLoaded(
        account: account,
        mutations: mutations,
        isBalanceVisible: keepVisible,
      ));
      return null;
    } catch (e) {
      final message = e is ApiException ? e.message : 'Saldo belum dapat ditampilkan. Silakan coba kembali.';
      if (!isSilentRefresh) {
        emit(AccountError(message));
      }
      return message;
    }
  }

  void toggleBalanceVisibility() {
    if (state is AccountLoaded) {
      final currentState = state as AccountLoaded;
      emit(currentState.copyWith(
        isBalanceVisible: !currentState.isBalanceVisible,
      ));
    }
  }

  Future<void> filterMutations({
    required String startDate,
    required String endDate,
    String? accountNumber,
  }) async {
    if (state is AccountLoaded) {
      final currentState = state as AccountLoaded;
      final accNo = accountNumber ?? currentState.account.accountNumber;
      try {
        final mutations = await accountRepository.getMutations(
          limit: 50,
          accountNumber: accNo,
          startDate: startDate,
          endDate: endDate,
        );
        emit(currentState.copyWith(mutations: mutations));
      } catch (e) {
        // keep current state on error
      }
    }
  }

  /// Silent refresh; returns a user-facing error message when the data could not be updated.
  Future<String?> refresh() async {
    if (state is AccountLoaded) {
      final currentAccount = (state as AccountLoaded).account.accountNumber;
      return loadDashboardData(accountNumber: currentAccount, isSilentRefresh: true);
    }
    return loadDashboardData();
  }
}
