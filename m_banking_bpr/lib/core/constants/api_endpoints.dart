class ApiEndpoints {
  // Primary: Live Biznet Ubuntu VPS IP (port 8080).
  // Fallback: Localhost for local development over USB ('adb reverse tcp:8080 tcp:8080').
  static String baseUrl = 'http://103.93.134.64:8080';
  static String fallbackUrl = 'http://localhost:8080';

  // API Paths
  static const String login = '/api/v1/auth/login';
  static const String refresh = '/api/v1/auth/refresh';
  static const String activateVerify = '/api/v1/auth/activate/verify';
  static const String activateOtp = '/api/v1/auth/activate/otp';
  static const String activateSetup = '/api/v1/auth/activate/setup';
  static const String balance = '/api/v1/account/balance';
  static const String mutations = '/api/v1/account/mutations';
  static const String accountInquiry = '/api/v1/account/inquiry';
  static const String accountProfile = '/api/v1/account/profile';
  static const String accountList = '/api/v1/account/list';
  static const String transfer = '/api/v1/transaction/transfer';
  static const String cbsHealth = '/api/v1/cbs/health';
  static const String cbsRefreshToken = '/api/v1/cbs/refresh-token';
  static const String health = '/health';
}
