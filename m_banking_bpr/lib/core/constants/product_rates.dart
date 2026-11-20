import '../content/app_content.dart';

class ProductRates {
  ProductRates._();

  static int get depositoAnnualBps => AppContent.intValue('product.deposito_rate_bps', 625);
  static String get depositoLabel => AppContent.text('product.deposito_rate_label').isNotEmpty
      ? AppContent.text('product.deposito_rate_label')
      : '6.25% p.a. (ilustrasi)';
  static int get depositoMinAmount => AppContent.intValue('product.deposito_min_amount', 1000000);
  static int get depositoMaxAmount => AppContent.intValue('product.deposito_max_amount', 2000000000);
  static int get depositoTaxThreshold => AppContent.intValue('product.deposito_tax_threshold', 7500000);
  static int get depositoTaxPercent => AppContent.intValue('product.deposito_tax_percent', 20);

  static int get kreditAnnualBps => AppContent.intValue('product.loan_rate_bps', 1500);
  static String get kreditLabel => AppContent.text('product.loan_rate_label').isNotEmpty
      ? AppContent.text('product.loan_rate_label')
      : '1.25% flat/bln (ilustrasi)';
  static int get kreditMinAmount => AppContent.intValue('product.loan_min_amount', 5000000);
  static int get kreditMaxAmount => AppContent.intValue('product.loan_max_amount', 500000000);
}
