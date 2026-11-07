class MutationModel {
  final String id;
  final String accountNumber;
  final String transactionType; // DEBIT / CREDIT
  final double amount;
  final double balanceAfter;
  final String description;
  final String referenceNumber;
  final String createdAt;

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

  factory MutationModel.fromJson(Map<String, dynamic> json) {
    return MutationModel(
      id: json['id'] ?? '',
      accountNumber: json['account_number'] ?? '',
      transactionType: json['transaction_type'] ?? json['type'] ?? 'DEBIT',
      amount: (json['amount'] is num) ? (json['amount'] as num).toDouble() : 0.0,
      balanceAfter: (json['balance_after'] is num) ? (json['balance_after'] as num).toDouble() : 0.0,
      description: json['description'] ?? '',
      referenceNumber: json['reference_number'] ?? json['reference_no'] ?? '',
      createdAt: json['created_at'] ?? json['transaction_date'] ?? DateTime.now().toIso8601String(),
    );
  }
}

