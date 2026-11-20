import '../config/app_environment.dart';

class ApiEndpoints {
  static String get baseUrl => AppEnvironment.apiBaseUrl;

  static bool get isSecure => baseUrl.toLowerCase().startsWith('https://');

  static const String login = '/api/v1/auth/login';
  static const String logout = '/api/v1/auth/logout';
  static const String refresh = '/api/v1/auth/refresh';
  static const String deviceChallenge = '/api/v1/auth/device-challenge';
  static const String deviceSessionChallenge = '/api/v1/device/challenge';
  static const String deviceEnroll = '/api/v1/device/enroll';
  static const String deviceStatus = '/api/v1/device/status';
  static const String deviceRotate = '/api/v1/device/keys/rotate';
  static const String activateVerify = '/api/v1/auth/activate/verify';
  static const String activateOtp = '/api/v1/auth/activate/otp';
  static const String activateSetup = '/api/v1/auth/activate/setup';
  static const String forgotPasswordRequest = '/api/v1/auth/forgot-password/request';
  static const String forgotPasswordOtp = '/api/v1/auth/forgot-password/otp';
  static const String forgotPasswordReset = '/api/v1/auth/forgot-password/reset';
  static const String changePassword = '/api/v1/auth/change-password';
  static const String changePin = '/api/v1/auth/change-pin';
  static const String applications = '/api/v1/applications';
  static const String appConfig = '/api/v1/config';
  static const String appContent = '/api/v1/content';
  static const String notifications = '/api/v1/notifications';
  static const String notificationsRead = '/api/v1/notifications/read';
  static const String notificationsFcmToken = '/api/v1/notifications/fcm-token';
  static const String notificationsOpened = '/api/v1/notifications/opened';
  static const String balance = '/api/v1/account/balance';
  static const String mutations = '/api/v1/account/mutations';
  static const String accountProfile = '/api/v1/account/profile';
  static const String accountProfileReveal = '/api/v1/account/profile/reveal';
  static const String accountList = '/api/v1/account/list';
  static const String loans = '/api/v1/account/loans';
  static const String loanDetail = '/api/v1/account/loans/';
  static const String deposits = '/api/v1/account/deposits';
  static const String depositDetail = '/api/v1/account/deposits/';
  static const String products = '/api/v1/account/products';
  static const String health = '/health';

  static const Set<String> preAuthPaths = {
    login,
    deviceChallenge,
    activateVerify,
    activateOtp,
    activateSetup,
    forgotPasswordRequest,
    forgotPasswordOtp,
    forgotPasswordReset,
    termsAcceptances,
  };

  static bool isPreAuth(String path) => preAuthPaths.any((p) => path.endsWith(p));

  static const String termsActive = '/api/v1/terms/active';
  static const String termsAcceptances = '/api/v1/terms/acceptances';
  static const String termsStatus = '/api/v1/terms/status';
  static String termsPdf(String versionId) => '/api/v1/terms/versions/${Uri.encodeComponent(versionId)}/pdf';
}
