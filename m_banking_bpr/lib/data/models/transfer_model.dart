class TransferRequestModel {
  final String fromAccount;
  final String toBankCode;
  final String toAccount;
  final String toAccountName;
  final double amount;
  final String note;
  final String pin;

  TransferRequestModel({
    required this.fromAccount,
    required this.toBankCode,
    required this.toAccount,
    required this.toAccountName,
    required this.amount,
    required this.note,
    required this.pin,
  });

  Map<String, dynamic> toJson() => {
        'from_account': fromAccount,
        'to_bank_code': toBankCode,
        'to_account': toAccount,
        'to_account_name': toAccountName,
        'amount': amount,
        'note': note,
        'pin': pin,
      };
}

class TransferResponseModel {
  final String transactionId;
  final String referenceNo;
  final String fromAccount;
  final String toBankCode;
  final String toBankName;
  final String toAccount;
  final String toAccountName;
  final double amount;
  final double fee;
  final double totalAmount;
  final String note;
  final String status;
  final String timestamp;

  TransferResponseModel({
    required this.transactionId,
    required this.referenceNo,
    required this.fromAccount,
    required this.toBankCode,
    required this.toBankName,
    required this.toAccount,
    required this.toAccountName,
    required this.amount,
    required this.fee,
    required this.totalAmount,
    required this.note,
    required this.status,
    required this.timestamp,
  });

  factory TransferResponseModel.fromJson(Map<String, dynamic> json) {
    return TransferResponseModel(
      transactionId: json['transaction_id'] ?? '',
      referenceNo: json['reference_no'] ?? '',
      fromAccount: json['from_account'] ?? '',
      toBankCode: json['to_bank_code'] ?? 'BPR',
      toBankName: json['to_bank_name'] ?? 'BPR INTERNAL',
      toAccount: json['to_account'] ?? '',
      toAccountName: json['to_account_name'] ?? '',
      amount: (json['amount'] is num) ? (json['amount'] as num).toDouble() : 0.0,
      fee: (json['fee'] is num) ? (json['fee'] as num).toDouble() : 0.0,
      totalAmount: (json['total_amount'] is num) ? (json['total_amount'] as num).toDouble() : 0.0,
      note: json['note'] ?? '',
      status: json['status'] ?? 'SUCCESS',
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
    );
  }
}

