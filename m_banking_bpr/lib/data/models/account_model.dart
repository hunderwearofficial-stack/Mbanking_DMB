class AccountModel {
  final String accountNumber;
  final String holderName;
  final String productCode;
  final String accountType;
  final double balance;
  final double minimumBalance;
  final double blockedBalance;
  final double effectiveBalance;
  final String status;
  final String? cbsRefId;
  final String? updatedAt;

  AccountModel({
    required this.accountNumber,
    this.holderName = '',
    this.productCode = '',
    required this.accountType,
    required this.balance,
    this.minimumBalance = 0.0,
    this.blockedBalance = 0.0,
    this.effectiveBalance = 0.0,
    required this.status,
    this.cbsRefId,
    this.updatedAt,
  });

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    final bal = (json['balance'] is num) ? (json['balance'] as num).toDouble() : 0.0;
    return AccountModel(
      accountNumber: json['account_number'] ?? '',
      holderName: json['holder_name'] ?? '',
      productCode: json['product_code'] ?? '',
      accountType: json['account_type'] ?? 'Tabungan Mandiri DMB',
      balance: bal,
      minimumBalance: (json['minimum_balance'] is num) ? (json['minimum_balance'] as num).toDouble() : 0.0,
      blockedBalance: (json['blocked_balance'] is num) ? (json['blocked_balance'] as num).toDouble() : 0.0,
      effectiveBalance: (json['effective_balance'] is num) ? (json['effective_balance'] as num).toDouble() : bal,
      status: json['status'] ?? 'Active',
      cbsRefId: json['cbs_ref_id'],
      updatedAt: json['updated_at'],
    );
  }

  Map<String, dynamic> toJson() => {
        'account_number': accountNumber,
        'holder_name': holderName,
        'product_code': productCode,
        'account_type': accountType,
        'balance': balance,
        'minimum_balance': minimumBalance,
        'blocked_balance': blockedBalance,
        'effective_balance': effectiveBalance,
        'status': status,
        'cbs_ref_id': cbsRefId,
        'updated_at': updatedAt,
      };
}

