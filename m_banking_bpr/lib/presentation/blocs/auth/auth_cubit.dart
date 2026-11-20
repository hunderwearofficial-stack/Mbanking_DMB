import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/services/fcm_service.dart';
import 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final AuthRepository authRepository;

  AuthCubit({required this.authRepository}) : super(AuthInitial());

  Future<void> checkAuthStatus() async {
    try {
      final isLoggedIn = await authRepository.isLoggedIn();
      if (isLoggedIn) {
        try {
          final refreshed = await authRepository.refreshSession();
          if (refreshed != null) {
            emit(AuthAuthenticated(refreshed.user));
            FCMService().syncStoredTokenIfLoggedIn(apiClient: authRepository.apiClient);
            return;
          }
        } catch (_) {
          // Do not bypass authentication into HomeScreen when token refresh fails
        }
        await authRepository.secureStorage.clearSessionTokens();
        emit(AuthUnauthenticated());
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
  }) async {
    emit(AuthLoading());
    try {
      final authResponse = await authRepository.login(
        identifier: identifier,
        password: password,
      );
      emit(AuthAuthenticated(authResponse.user));
      FCMService().syncStoredTokenIfLoggedIn(apiClient: authRepository.apiClient);
    } on ApiException catch (e) {
      emit(AuthError(ApiException.humanize(e), code: e.responseCode));
    } catch (e) {
      emit(AuthError(ApiException.humanize(
        e,
        fallback: 'Login belum dapat diproses. Periksa kembali koneksi internet Anda.',
      )));
    }
  }

  Future<void> loginWithBiometric() async {
    emit(AuthLoading());
    try {
      final user = await authRepository.loginWithBiometric();
      emit(AuthAuthenticated(user));
      FCMService().syncStoredTokenIfLoggedIn(apiClient: authRepository.apiClient);
    } on ApiException catch (e) {
      emit(AuthError(ApiException.humanize(e), code: e.responseCode));
    } catch (e) {
      emit(AuthError(ApiException.humanize(
        e,
        fallback: 'Autentikasi biometrik belum dapat diproses. Silakan masuk menggunakan kata sandi.',
      )));
    }
  }

  Future<void> logout() async {
    await authRepository.logout();
    FCMService().onLoggedOut();
    emit(AuthUnauthenticated());
  }

  Future<void> lockSession() async {
    await authRepository.lockSession();
    emit(AuthUnauthenticated());
  }
}
