import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/models/transfer_model.dart';
import '../../../data/repositories/transaction_repository.dart';
import 'transfer_state.dart';

class TransferCubit extends Cubit<TransferState> {
  final TransactionRepository transactionRepository;

  TransferCubit({required this.transactionRepository}) : super(TransferInitial());

  Future<void> submitTransfer({
    required String fromAccount,
    required String toBankCode,
    required String toAccount,
    required String toAccountName,
    required double amount,
    required String note,
    required String pin,
  }) async {
    emit(TransferLoading());
    try {
      final request = TransferRequestModel(
        fromAccount: fromAccount,
        toBankCode: toBankCode,
        toAccount: toAccount,
        toAccountName: toAccountName,
        amount: amount,
        note: note,
        pin: pin,
      );

      final response = await transactionRepository.transfer(request);
      emit(TransferSuccess(response));
    } catch (e) {
      emit(TransferError(e.toString()));
    }
  }

  void reset() {
    emit(TransferInitial());
  }
}
