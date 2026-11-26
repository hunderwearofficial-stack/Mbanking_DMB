import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_exception.dart';
import '../../../data/repositories/account_repository.dart';
import 'account_state.dart';

class AccountCubit extends Cubit<AccountState> {
  static const String primaryAccountPrefKey = 'primary_account_number';

  final AccountRepository accountRepository;
  bool _isBalanceVisible = false;

  bool get isBalanceVisible => _isBalanceVisible;

  AccountCubit({required this.accountRepository}) : super(AccountInitial());

  Future<String?> _getSavedPrimaryAccount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(primaryAccountPrefKey)?.trim();
      return (saved != null && saved.isNotEmpty) ? saved : null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> setPrimaryAccount(String accountNumber) async {
    final trimmed = accountNumber.trim();
    if (trimmed.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(primaryAccountPrefKey, trimmed);
    } catch (_) {}
    return loadDashboardData(accountNumber: trimmed, isSilentRefresh: true);
  }

  Future<String?> loadDashboardData({String? accountNumber, bool isSilentRefresh = false}) async {
    final bool keepVisible = (state is AccountLoaded) ? (state as AccountLoaded).isBalanceVisible : _isBalanceVisible;
    _isBalanceVisible = keepVisible;
    if (!isSilentRefresh) {
      emit(AccountLoading());
    }
    try {
      final targetAccount = (accountNumber != null && accountNumber.trim().isNotEmpty)
          ? accountNumber.trim()
          : await _getSavedPrimaryAccount();

      dynamic account;
      dynamic mutations;
      try {
        final results = await Future.wait([
          accountRepository.getBalance(accountNumber: targetAccount),
          accountRepository.getMutations(limit: 10, accountNumber: targetAccount),
          accountRepository.getCustomerProfile().catchError((_) => <String, dynamic>{}),
          accountRepository.getSavingsAccounts().catchError((_) => <Map<String, dynamic>>[]),
        ]);
        account = results[0];
        mutations = results[1];
      } catch (e) {
        // If a saved primary account is no longer valid (e.g. different user logged in),
        // clear it and retry with the default primary account.
        if (targetAccount != null && accountNumber == null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove(primaryAccountPrefKey);
          } catch (_) {}
          final fallback = await Future.wait([
            accountRepository.getBalance(),
            accountRepository.getMutations(limit: 10),
          ]);
          account = fallback[0];
          mutations = fallback[1];
        } else {
          rethrow;
        }
      }

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
