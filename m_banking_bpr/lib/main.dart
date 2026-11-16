import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'core/config/app_environment.dart';
import 'core/network/api_client.dart';
import 'core/utils/app_logger.dart';
import 'core/security/secure_storage_service.dart';
import 'core/security/security_hardening_service.dart';
import 'core/security/session_inactivity_detector.dart';
import 'core/services/fcm_service.dart';
import 'core/services/dynamic_config_service.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/account_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'presentation/blocs/account/account_cubit.dart';
import 'core/content/app_content.dart';
import 'presentation/blocs/auth/auth_cubit.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/splash/splash_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 0. Build configuration (flavor + API endpoint). Invalid configuration shows an
  //    error screen instead of silently talking to another server.
  final configError = AppEnvironment.validate();
  if (configError != null) {
    runApp(ConfigurationErrorApp(message: configError));
    return;
  }

  // Initialize Firebase native bindings before any services run
  try {
    final firebaseOpts = DefaultFirebaseOptions.currentPlatform;
    if (firebaseOpts != null && Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: firebaseOpts,
      );
    }
  } catch (e) {
    logDebug('Firebase.initializeApp error: $e');
  }

  // 1. Core Services Initialization
  final secureStorage = SecureStorageService();
  final apiClient = ApiClient(
    secureStorage: secureStorage,
    onUnauthorized: () {
      final nav = appNavigatorKey.currentState;
      if (nav != null) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        final ctx = appNavigatorKey.currentContext;
        if (ctx != null) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(
              content: Text('Sesi berakhir atau akun Anda telah login di perangkat lain.'),
              backgroundColor: Color(0xFFE11D48),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    },
  );

  // Load persistent branding & config from local disk cache immediately
  await DynamicConfigService().initialize(apiClient: apiClient);

  // 2. Data Repositories
  final authRepository = AuthRepository(apiClient: apiClient, secureStorage: secureStorage);
  final accountRepository = AccountRepository(apiClient: apiClient);

  // 3. Launch UI immediately so the app opens instantly with zero blank screen
  runApp(
    MBankingBPRApp(
      authRepository: authRepository,
      accountRepository: accountRepository,
    ),
  );

  // 4. Initialize background services asynchronously AFTER UI is rendered
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await SecurityHardeningService.setFlagSecure(true);
    } catch (_) {}

    try {
      await FCMService().initialize(apiClient: apiClient);
    } catch (e) {
      logDebug('FCM init error: $e');
    }
  });
}

class MBankingBPRApp extends StatelessWidget {
  final AuthRepository authRepository;
  final AccountRepository accountRepository;

  const MBankingBPRApp({
    super.key,
    required this.authRepository,
    required this.accountRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: authRepository),
        RepositoryProvider<AccountRepository>.value(value: accountRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthCubit>(
            create: (_) => AuthCubit(authRepository: authRepository),
          ),
          BlocProvider<AccountCubit>(
            create: (_) => AccountCubit(accountRepository: accountRepository),
          ),
        ],
        child: MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'Mobile DMB',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('id', 'ID'),
            Locale('en', 'US'),
          ],
          locale: const Locale('id', 'ID'),
          builder: (context, child) => ContentRefreshScope(child: SessionInactivityDetector(child: child ?? const SizedBox.shrink())),
          home: const SplashScreen(),
        ),
      ),
    );
  }
}


/// Shown when the app was built without a valid environment configuration.
class ConfigurationErrorApp extends StatelessWidget {
  final String message;
  const ConfigurationErrorApp({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.settings_suggest_rounded, size: 48, color: Color(0xFFB91C1C)),
                const SizedBox(height: 16),
                const Text('Konfigurasi aplikasi tidak valid',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(message, key: const Key('config_error_message')),
                const SizedBox(height: 12),
                const Text('Bangun ulang aplikasi sesuai docs/LOCAL_SETUP.md.',
                    style: TextStyle(color: Color(0xFF64748B))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
