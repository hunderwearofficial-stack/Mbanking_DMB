import 'package:equatable/equatable.dart';
import '../../../data/models/account_model.dart';
import '../../../data/models/mutation_model.dart';

abstract class AccountState extends Equatable {
  const AccountState();

  @override
  List<Object?> get props => [];
}

class AccountInitial extends AccountState {}

class AccountLoading extends AccountState {}

class AccountLoaded extends AccountState {
  final AccountModel account;
  final List<MutationModel> mutations;
  final bool isBalanceVisible;

  const AccountLoaded({
    required this.account,
    required this.mutations,
    this.isBalanceVisible = true,
  });

  AccountLoaded copyWith({
    AccountModel? account,
    List<MutationModel>? mutations,
    bool? isBalanceVisible,
  }) {
    return AccountLoaded(
      account: account ?? this.account,
      mutations: mutations ?? this.mutations,
      isBalanceVisible: isBalanceVisible ?? this.isBalanceVisible,
    );
  }

  @override
  List<Object?> get props => [account, mutations, isBalanceVisible];
}

class AccountError extends AccountState {
  final String message;
  const AccountError(this.message);

  @override
  List<Object?> get props => [message];
}

