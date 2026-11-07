import 'package:equatable/equatable.dart';
import '../../../data/models/transfer_model.dart';

abstract class TransferState extends Equatable {
  const TransferState();

  @override
  List<Object?> get props => [];
}

class TransferInitial extends TransferState {}

class TransferLoading extends TransferState {}

class TransferSuccess extends TransferState {
  final TransferResponseModel response;
  const TransferSuccess(this.response);

  @override
  List<Object?> get props => [response];
}

class TransferError extends TransferState {
  final String message;
  const TransferError(this.message);

  @override
  List<Object?> get props => [message];
}

