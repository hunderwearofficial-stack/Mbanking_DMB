import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_endpoints.dart';
import '../network/api_client.dart';
import '../utils/app_logger.dart';

/// Data model representing server-driven dynamic mobile branding & configuration.
class DynamicAppConfig {
  final String bankName;
  final String bankShortName;
  final String tagline;
  final String logoUrl;
  final String loginBgUrl;
  final String splashBgUrl;
  final String onboardingBgUrl;
  final String welcomeTitle;
  final String welcomeSubtitle;
  final String loginTitle;
  final String loginSubtitle;
  final String termsVersion;
  final String homeGreeting;
  final String announcementText;
  final String termsPdfUrl;
  final String privacyPdfUrl;
  final String quickMenuConfig;
  final String callCenter;
  final String whatsappCs;
  final String emailCs;
  final String websiteUrl;
  final String headOfficeAddress;
  final bool maintenanceMode;
  final String maintenanceMessage;

  /// Published mobile content revision (back office draft → publish); 0 = none yet.
  final int contentVersion;

  const DynamicAppConfig({
    required this.bankName,
    required this.bankShortName,
    required this.tagline,
    required this.logoUrl,
    required this.loginBgUrl,
    required this.splashBgUrl,
    required this.onboardingBgUrl,
    required this.welcomeTitle,
    required this.welcomeSubtitle,
    required this.loginTitle,
    required this.loginSubtitle,
    required this.termsVersion,
    required this.homeGreeting,
    required this.announcementText,
    required this.termsPdfUrl,
    required this.privacyPdfUrl,
    required this.quickMenuConfig,
    required this.callCenter,
    required this.whatsappCs,
    required this.emailCs,
    required this.websiteUrl,
    required this.headOfficeAddress,
    required this.maintenanceMode,
    required this.maintenanceMessage,
    this.contentVersion = 0,
  });

  /// Default baseline configuration.
  factory DynamicAppConfig.defaults() {
    return const DynamicAppConfig(
      bankName: 'PT BPR DANA MANDIRI BOGOR',
      bankShortName: 'Bank DMB',
      tagline: 'Mitra Terpercaya Menuju Sejahtera',
      logoUrl: '',
      loginBgUrl: '',
      splashBgUrl: '',
      onboardingBgUrl: '',
      welcomeTitle: 'Selamat Datang di DMB Mobile',
      welcomeSubtitle: 'Transaksi mudah, aman, dan tepercaya bersama BPR Dana Mandiri Bogor',
      loginTitle: 'Masuk ke Akun M-Banking',
      loginSubtitle: 'Silakan masukkan User ID dan Kata Sandi Anda',
      termsVersion: '',
      homeGreeting: 'Semoga harimu menyenangkan!',
      announcementText: '',
      termsPdfUrl: '',
      privacyPdfUrl: '',
      quickMenuConfig: '',
      // Contacts are never invented on the device: empty until the bank publishes them
      // (screens then use the single in-app source, BankContact).
      callCenter: '',
      whatsappCs: '',
      emailCs: '',
      websiteUrl: '',
      headOfficeAddress: '',
      maintenanceMode: false,
      maintenanceMessage: 'Sistem sedang dalam pemeliharaan berkala untuk peningkatan kualitas layanan.',
    );
  }

  factory DynamicAppConfig.fromJson(Map<String, dynamic> json) {
    return DynamicAppConfig(
      bankName: json['bank_name'] as String? ?? 'PT BPR DANA MANDIRI BOGOR',
      bankShortName: json['bank_short_name'] as String? ?? 'Bank DMB',
      tagline: json['tagline'] as String? ?? 'Mitra Terpercaya Menuju Sejahtera',
      logoUrl: json['logo_url'] as String? ?? '',
      loginBgUrl: json['login_bg_url'] as String? ?? '',
      splashBgUrl: json['splash_bg_url'] as String? ?? '',
      onboardingBgUrl: json['onboarding_bg_url'] as String? ?? '',
      welcomeTitle: json['welcome_title'] as String? ?? 'Selamat Datang di DMB Mobile',
      welcomeSubtitle: json['welcome_subtitle'] as String? ??
          'Transaksi mudah, aman, dan tepercaya bersama BPR Dana Mandiri Bogor',
      loginTitle: json['login_title'] as String? ?? 'Masuk ke Akun M-Banking',
      loginSubtitle: json['login_subtitle'] as String? ?? 'Silakan masukkan User ID dan Kata Sandi Anda',
      termsVersion: json['terms_version'] as String? ?? '',
      homeGreeting: json['home_greeting'] as String? ?? 'Semoga harimu menyenangkan!',
      announcementText: json['announcement_text'] as String? ?? '',
      termsPdfUrl: json['terms_pdf_url'] as String? ?? '',
      privacyPdfUrl: json['privacy_pdf_url'] as String? ?? '',
      quickMenuConfig: json['quick_menu_config'] as String? ?? '',
      callCenter: json['call_center'] as String? ?? '',
      whatsappCs: json['whatsapp_cs'] as String? ?? '',
      emailCs: json['email_cs'] as String? ?? '',
      websiteUrl: json['website_url'] as String? ?? '',
      headOfficeAddress: json['head_office_address'] as String? ?? '',
      contentVersion: (json['content_version'] as num?)?.toInt() ?? 0,
      maintenanceMode: json['maintenance_mode'] as bool? ?? false,
      maintenanceMessage: json['maintenance_message'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bank_name': bankName,
      'bank_short_name': bankShortName,
      'tagline': tagline,
      'logo_url': logoUrl,
      'login_bg_url': loginBgUrl,
      'splash_bg_url': splashBgUrl,
      'onboarding_bg_url': onboardingBgUrl,
      'welcome_title': welcomeTitle,
      'welcome_subtitle': welcomeSubtitle,
      'login_title': loginTitle,
      'login_subtitle': loginSubtitle,
      'terms_version': termsVersion,
      'home_greeting': homeGreeting,
      'announcement_text': announcementText,
      'terms_pdf_url': termsPdfUrl,
      'privacy_pdf_url': privacyPdfUrl,
      'quick_menu_config': quickMenuConfig,
      'call_center': callCenter,
      'whatsapp_cs': whatsappCs,
      'email_cs': emailCs,
      'website_url': websiteUrl,
      'head_office_address': headOfficeAddress,
      'content_version': contentVersion,
      'maintenance_mode': maintenanceMode,
      'maintenance_message': maintenanceMessage,
    };
  }

  /// Resolve relative upload URLs to full accessible backend URLs.
  String resolveUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return '';
    final url = rawUrl.trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    // Prepend API Base URL
    final base = ApiEndpoints.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final cleanPath = url.startsWith('/') ? url : '/$url';
    return '$base$cleanPath';
  }

  String get resolvedLogoUrl => resolveUrl(logoUrl);
  String get resolvedLoginBgUrl => resolveUrl(loginBgUrl);
  String get resolvedSplashBgUrl => resolveUrl(splashBgUrl);
  String get resolvedOnboardingBgUrl => resolveUrl(onboardingBgUrl);
  String get resolvedTermsPdfUrl => resolveUrl(termsPdfUrl);
  String get resolvedPrivacyPdfUrl => resolveUrl(privacyPdfUrl);
}

/// Central Singleton for Dynamic Server-Driven Branding & Configuration with Persistent Disk Cache.
/// Crucial requirement: When offline, the app NEVER reverts to bundled stock assets.
/// It retains and loads the latest saved configuration from disk cache.
class DynamicConfigService extends ChangeNotifier with WidgetsBindingObserver {
  static final DynamicConfigService _instance = DynamicConfigService._internal();
  factory DynamicConfigService() => _instance;
  DynamicConfigService._internal();

  static const String _storageKey = 'dmb_cached_app_config_v3'; // v3: content_version, no fabricated defaults
  static const String _storageTimeKey = 'dmb_cached_app_config_time';

  DynamicAppConfig _config = DynamicAppConfig.defaults();
  DynamicAppConfig get config => _config;

  /// Helper to resolve relative upload URLs to full backend URLs
  String resolveUrl(String? rawUrl) => _config.resolveUrl(rawUrl);

  bool _isServerConnected = true;
  bool get isServerConnected => _isServerConnected;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // ---- Managed content (GET /api/v1/content, see lib/core/content/app_content.dart) ----
  static const String _contentKey = 'dmb_app_content_v1';
  Map<String, String> _content = const {};
  int _contentVersion = -1;
  DateTime? _contentFetchedAt;
  ApiClient? _apiClient;

  /// Published content version applied in the app (-1 = none downloaded yet).
  int get contentVersion => _contentVersion;

  /// Applies a downloaded content payload (tests).
  @visibleForTesting
  void applyContentForTest(Map<String, dynamic> data) {
    _applyContent(data);
    notifyListeners();
  }

  /// Raw published value of a content element (validated by AppContent before use).
  String? contentItem(String key) => _content[key];

  void _applyContent(dynamic data) {
    if (data is! Map) return;
    final version = data['version'];
    final items = data['items'];
    if (version is! num || items is! Map) return;
    final parsed = <String, String>{};
    items.forEach((k, v) {
      if (k is String && v is String) parsed[k] = v;
    });
    _content = Map.unmodifiable(parsed);
    _contentVersion = version.toInt();
  }

  /// Downloads the published content; applied and cached only when the version changed.
  Future<bool> refreshContent({ApiClient? apiClient}) async {
    final client = apiClient ?? _apiClient;
    if (client == null) return false;
    try {
      final res = await client.get(ApiEndpoints.appContent);
      _contentFetchedAt = DateTime.now();
      if (res is Map && res['version'] is num && (res['version'] as num).toInt() != _contentVersion) {
        _applyContent(res);
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_contentKey, jsonEncode(res));
        } catch (e) {
          logDebug('DynamicConfigService: error persisting content cache: $e');
        }
        notifyListeners();
      }
      return true;
    } catch (e) {
      // Keep what is shown (cache or built-in values); never substitute other content.
      logDebug('DynamicConfigService: content not refreshed ($e)');
      return false;
    }
  }

  // Refresh when the app comes back to the foreground (no polling), at most once a minute.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _contentFetchedAt;
    if (last != null && DateTime.now().difference(last) < const Duration(minutes: 1)) return;
    refreshContent();
  }

  /// Initialize and load persistent cache from disk storage immediately.
  Future<void> initialize({ApiClient? apiClient}) async {
    if (_isInitialized) return;
    _apiClient = apiClient;
    WidgetsBinding.instance.addObserver(this);

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJsonStr = prefs.getString(_storageKey);

      if (cachedJsonStr != null && cachedJsonStr.trim().isNotEmpty) {
        final decoded = jsonDecode(cachedJsonStr) as Map<String, dynamic>;
        _config = DynamicAppConfig.fromJson(decoded);
        logDebug('DynamicConfigService: loaded cached dynamic branding from disk.');
      }
      final cachedContent = prefs.getString(_contentKey);
      if (cachedContent != null && cachedContent.isNotEmpty) {
        _applyContent(jsonDecode(cachedContent));
      }
    } catch (e) {
      logDebug('DynamicConfigService init cache read error: $e');
    }

    _isInitialized = true;
    notifyListeners();

    // Asynchronously fetch latest config from server
    refreshFromServer(apiClient: apiClient);
    refreshContent(apiClient: apiClient);
  }

  /// Fetch the latest configuration from the server and persist to disk.
  /// If offline or server unreachable, maintains disk cache and updates connectivity state.
  Future<bool> refreshFromServer({ApiClient? apiClient}) async {
    try {
      final client = apiClient;
      dynamic res;

      if (client != null) {
        res = await client.get(ApiEndpoints.appConfig);
      } else {
        // Fallback using direct Dio
        final tempClient = ApiClient.createSecureDio(baseUrl: ApiEndpoints.baseUrl);
        final raw = await tempClient.get(ApiEndpoints.appConfig);
        res = raw.data;
      }

      Map<String, dynamic>? dataMap;
      if (res is Map<String, dynamic>) {
        if (res.containsKey('data') && res['data'] is Map<String, dynamic>) {
          dataMap = res['data'] as Map<String, dynamic>;
        } else if (res.containsKey('bank_name')) {
          dataMap = res;
        }
      }

      if (dataMap != null) {
        _config = DynamicAppConfig.fromJson(dataMap);
        _isServerConnected = true;

        // Persist to disk cache
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_storageKey, jsonEncode(_config.toJson()));
          await prefs.setInt(_storageTimeKey, DateTime.now().millisecondsSinceEpoch);
        } catch (e) {
          logDebug('DynamicConfigService: error persisting cache: $e');
        }

        notifyListeners();
        return true;
      }
    } catch (e) {
      logDebug('DynamicConfigService: unable to reach server ($e), preserving disk cache.');
      _isServerConnected = false;
      notifyListeners();
    }
    return false;
  }

  /// Manually set connectivity status (e.g. from network interceptor or health probe).
  void setServerConnected(bool connected) {
    if (_isServerConnected != connected) {
      _isServerConnected = connected;
      notifyListeners();
    }
  }

  /// Actively test server health endpoint.
  Future<bool> checkHealth() async {
    try {
      final dio = ApiClient.createSecureDio(
        baseUrl: ApiEndpoints.baseUrl,
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
      );
      final res = await dio.get(ApiEndpoints.health);
      final healthy = res.statusCode == 200;
      setServerConnected(healthy);
      return healthy;
    } catch (_) {
      setServerConnected(false);
      return false;
    }
  }
}
