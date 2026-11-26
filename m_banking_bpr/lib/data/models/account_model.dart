import '../../core/money/money.dart';

class AccountModel {
  final String accountNumber;
  final String holderName;
  final String productCode;
  final String accountType;
  final Money balance;
  final Money? minimumBalance;
  final Money? blockedBalance;
  final Money? effectiveBalance;
  final String status;
  final String openedDate;
  final String? cbsRefId;
  final String? updatedAt;

  AccountModel({
    required this.accountNumber,
    this.holderName = '',
    this.productCode = '',
    required this.accountType,
    required this.balance,
    this.minimumBalance,
    this.blockedBalance,
    this.effectiveBalance,
    required this.status,
    this.openedDate = '',
    this.cbsRefId,
    this.updatedAt,
  });

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    if (json['balance'] == null) throw const FormatException('saldo tidak tersedia');
    return AccountModel(
      accountNumber: (json['account_number'] ?? '').toString(),
      holderName: (json['holder_name'] ?? '').toString(),
      productCode: (json['product_code'] ?? '').toString(),
      accountType: (json['account_type'] ?? '-').toString(),
      balance: Money.parse(json['balance']),
      minimumBalance: Money.tryParse(json['minimum_balance']),
      blockedBalance: Money.tryParse(json['blocked_balance']),
      effectiveBalance: Money.tryParse(json['effective_balance']),
      status: (json['status'] ?? '').toString(),
      openedDate: (json['opened_date'] ?? '').toString(),
      cbsRefId: json['cbs_ref_id']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }
}
