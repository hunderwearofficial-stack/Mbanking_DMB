import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/network/api_client.dart';
import 'core/security/secure_storage_service.dart';
import 'core/security/security_hardening_service.dart';
import 'core/security/session_inactivity_detector.dart';
import 'core/services/fcm_service.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/account_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'presentation/blocs/account/account_cubit.dart';
import 'presentation/blocs/auth/auth_cubit.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/splash/splash_screen.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Security Hardening Initialization (FLAG_SECURE Active by Default)
  await SecurityHardeningService.setFlagSecure(true);

  // 2. Core Services Initialization
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

  // 2. Data Repositories
  final authRepository = AuthRepository(apiClient: apiClient, secureStorage: secureStorage);
  final accountRepository = AccountRepository(apiClient: apiClient);

  // 3. Real-Time Push Notification (Firebase Cloud Messaging)
  await FCMService().initialize(apiClient: apiClient);

  runApp(
    MBankingBPRApp(
      authRepository: authRepository,
      accountRepository: accountRepository,
    ),
  );
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
          builder: (context, child) => SessionInactivityDetector(child: child ?? const SizedBox.shrink()),
          home: const SplashScreen(),
        ),
      ),
    );
  }
}

