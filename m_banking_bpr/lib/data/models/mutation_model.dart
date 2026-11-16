import '../../core/money/money.dart';

class MutationModel {
  final String id;
  final String accountNumber;
  final String transactionType; // DEBIT / CREDIT
  final Money amount;
  final Money? balanceAfter;
  final String description;
  final String referenceNumber;
  final String createdAt; // empty when the source did not provide a date

  MutationModel({
    required this.id,
    required this.accountNumber,
    required this.transactionType,
    required this.amount,
    required this.balanceAfter,
    required this.description,
    required this.referenceNumber,
    required this.createdAt,
  });

  bool get isCredit => transactionType.toUpperCase() == 'CREDIT' || transactionType.toUpperCase() == 'CR';

  /// Throws [FormatException] when the amount is missing or malformed.
  factory MutationModel.fromJson(Map<String, dynamic> json) {
    if (json['amount'] == null) throw const FormatException('nominal mutasi tidak tersedia');
    return MutationModel(
      id: (json['id'] ?? '').toString(),
      accountNumber: (json['account_number'] ?? '').toString(),
      transactionType: (json['transaction_type'] ?? json['type'] ?? '').toString(),
      amount: Money.parse(json['amount']),
      balanceAfter: Money.tryParse(json['balance_after']),
      description: (json['description'] ?? '').toString(),
      referenceNumber: (json['reference_number'] ?? json['reference_no'] ?? '').toString(),
      createdAt: (json['created_at'] ?? json['transaction_date'] ?? '').toString(),
    );
  }
}
