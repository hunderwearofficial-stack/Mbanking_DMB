import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/auth_repository.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository authRepository;

  AuthCubit({required this.authRepository}) : super(AuthInitial());

  Future<void> checkAuthStatus() async {
    try {
      final isLoggedIn = await authRepository.isLoggedIn();
      if (isLoggedIn) {
        // Attempt to refresh & validate session token with the server so expired tokens never get stuck on HomeScreen
        try {
          final refreshed = await authRepository.refreshSession();
          if (refreshed != null) {
            emit(AuthAuthenticated(refreshed.user));
            return;
          }
        } catch (e) {
          // If server explicitly rejected refresh token (401), require clean re-login
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('berakhir') ||
              errStr.contains('kadaluarsa') ||
              errStr.contains('tidak valid') ||
              errStr.contains('401')) {
            await authRepository.secureStorage.clearSessionTokens();
            emit(AuthUnauthenticated());
            return;
          }
        }

        final phone = await authRepository.secureStorage.getPhoneNumber() ?? '';
        final cif = await authRepository.secureStorage.getCIF() ?? '';
        final fullName = await authRepository.secureStorage.getFullName() ?? '';
        final primaryAccount = await authRepository.secureStorage.getPrimaryAccount() ?? '';
        final deviceId = await authRepository.secureStorage.getDeviceID();

        emit(AuthAuthenticated(UserModel(
          id: '',
          cif: cif,
          fullName: fullName.isNotEmpty ? fullName : 'Nasabah',
          phoneNumber: phone,
          email: '',
          deviceId: deviceId,
          primaryAccount: primaryAccount,
          isActive: true,
        )));
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (_) {
      emit(AuthUnauthenticated());
    }
  }

  Future<void> login({
    required String identifier,
    required String password,
    String? deviceId,
  }) async {
    emit(AuthLoading());
    try {
      final authResponse = await authRepository.login(
        identifier: identifier,
        password: password,
        deviceId: deviceId,
      );
      emit(AuthAuthenticated(authResponse.user));
    } catch (e) {
      emit(AuthError(e.toString()));
    }
  }

  Future<void> loginWithBiometric() async {
    emit(AuthLoading());
    try {
      final user = await authRepository.loginWithBiometric();
      emit(AuthAuthenticated(user));
    } catch (e) {
      emit(AuthError(e.toString().replaceAll('Exception: ', '')));
    }
  }

  Future<void> logout() async {
    await authRepository.logout();
    emit(AuthUnauthenticated());
  }
}
