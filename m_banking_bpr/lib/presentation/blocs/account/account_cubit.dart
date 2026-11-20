import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/account_repository.dart';
import 'account_state.dart';

class AccountCubit extends Cubit<AccountState> {
  final AccountRepository accountRepository;
  bool _isBalanceVisible = false;

  bool get isBalanceVisible => _isBalanceVisible;

  AccountCubit({required this.accountRepository}) : super(AccountInitial());

  Future<String?> loadDashboardData({String? accountNumber, bool isSilentRefresh = false}) async {
    final bool keepVisible = (state is AccountLoaded) ? (state as AccountLoaded).isBalanceVisible : _isBalanceVisible;
    _isBalanceVisible = keepVisible;
    if (!isSilentRefresh) {
      emit(AccountLoading());
    }
    try {
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
        isBalanceVisible: _isBalanceVisible,
      ));
      return null;
    } catch (e) {
      final message = e is ApiException
          ? ApiException.humanize(e)
          : 'Saldo belum dapat ditampilkan. Silakan coba kembali.';
      if (!isSilentRefresh) {
        emit(AccountError(message));
      }
      return message;
    }
  }

  void toggleBalanceVisibility() {
    _isBalanceVisible = !_isBalanceVisible;
    if (state is AccountLoaded) {
      final currentState = state as AccountLoaded;
      emit(currentState.copyWith(
        isBalanceVisible: _isBalanceVisible,
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
      }
    }
  }

  Future<String?> refresh() async {
    if (state is AccountLoaded) {
      final currentAccount = (state as AccountLoaded).account.accountNumber;
      return loadDashboardData(accountNumber: currentAccount, isSilentRefresh: true);
    }
    return loadDashboardData();
  }
}
