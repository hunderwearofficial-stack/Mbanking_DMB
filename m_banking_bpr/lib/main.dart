import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/network/api_client.dart';
import 'core/security/secure_storage_service.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/account_repository.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/transaction_repository.dart';
import 'presentation/blocs/account/account_cubit.dart';
import 'presentation/blocs/auth/auth_cubit.dart';
import 'presentation/blocs/transfer/transfer_cubit.dart';
import 'presentation/screens/home/home_screen.dart';
import 'presentation/screens/splash/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Core Services Initialization
  final secureStorage = SecureStorageService();
  final apiClient = ApiClient(secureStorage: secureStorage);

  // 2. Data Repositories
  final authRepository = AuthRepository(apiClient: apiClient, secureStorage: secureStorage);
  final accountRepository = AccountRepository(apiClient: apiClient);
  final transactionRepository = TransactionRepository(apiClient: apiClient);

  runApp(
    MBankingBPRApp(
      authRepository: authRepository,
      accountRepository: accountRepository,
      transactionRepository: transactionRepository,
    ),
  );
}

class MBankingBPRApp extends StatelessWidget {
  final AuthRepository authRepository;
  final AccountRepository accountRepository;
  final TransactionRepository transactionRepository;

  const MBankingBPRApp({
    super.key,
    required this.authRepository,
    required this.accountRepository,
    required this.transactionRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: authRepository),
        RepositoryProvider<AccountRepository>.value(value: accountRepository),
        RepositoryProvider<TransactionRepository>.value(value: transactionRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthCubit>(
            create: (_) => AuthCubit(authRepository: authRepository),
          ),
          BlocProvider<AccountCubit>(
            create: (_) => AccountCubit(accountRepository: accountRepository),
          ),
          BlocProvider<TransferCubit>(
            create: (_) => TransferCubit(transactionRepository: transactionRepository),
          ),
        ],
        child: MaterialApp(
          title: 'Mobile BPR',
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
          home: const SplashScreen(),
        ),
      ),
    );
  }
}

