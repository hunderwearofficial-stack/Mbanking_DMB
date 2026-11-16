import '../config/app_environment.dart';

class ApiEndpoints {
  // The backend URL comes ONLY from the build configuration (AppEnvironment):
  // no hardcoded default server and no localhost fallback.
  static String get baseUrl => AppEnvironment.apiBaseUrl;

  /// True when the configured endpoint uses TLS.
  static bool get isSecure => baseUrl.toLowerCase().startsWith('https://');

  // API Paths
  static const String login = '/api/v1/auth/login';
  static const String logout = '/api/v1/auth/logout';
  static const String refresh = '/api/v1/auth/refresh';
  static const String activateVerify = '/api/v1/auth/activate/verify';
  static const String activateOtp = '/api/v1/auth/activate/otp';
  static const String activateSetup = '/api/v1/auth/activate/setup';
  static const String forgotPasswordRequest = '/api/v1/auth/forgot-password/request';
  static const String forgotPasswordOtp = '/api/v1/auth/forgot-password/otp';
  static const String forgotPasswordReset = '/api/v1/auth/forgot-password/reset';
  static const String changePassword = '/api/v1/auth/change-password';
  static const String changePin = '/api/v1/auth/change-pin';
  static const String beneficiaries = '/api/v1/beneficiaries';
  static const String applications = '/api/v1/applications';
  static const String appConfig = '/api/v1/config';
  static const String appContent = '/api/v1/content';
  static const String notifications = '/api/v1/notifications';
  static const String notificationsRead = '/api/v1/notifications/read';
  static const String notificationsFcmToken = '/api/v1/notifications/fcm-token';
  static const String balance = '/api/v1/account/balance';
  static const String mutations = '/api/v1/account/mutations';
  static const String accountInquiry = '/api/v1/account/inquiry';
  static const String accountProfile = '/api/v1/account/profile';
  static const String accountList = '/api/v1/account/list';
  static const String loans = '/api/v1/account/loans';
  static const String loanDetail = '/api/v1/account/loans/';
  static const String deposits = '/api/v1/account/deposits';
  static const String depositDetail = '/api/v1/account/deposits/';
  static const String products = '/api/v1/account/products';
  static const String transfer = '/api/v1/transaction/transfer';
  static const String health = '/health';

  // Syarat dan Ketentuan (versi terbit, PDF, persetujuan sebelum login)
  static const String termsActive = '/api/v1/terms/active';
  static const String termsAcceptances = '/api/v1/terms/acceptances';
  static const String termsStatus = '/api/v1/terms/status';
  static String termsPdf(String versionId) => '/api/v1/terms/versions/${Uri.encodeComponent(versionId)}/pdf';
}
