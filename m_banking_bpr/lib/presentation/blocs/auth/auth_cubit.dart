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

  Future<void> loginOfflineDemo() async {
    emit(AuthLoading());
    try {
      final demoUser = UserModel(
        id: 'usr-demo-001',
        cif: 'CIF998877',
        fullName: 'Budi Santoso (Demo)',
        phoneNumber: '081234567890',
        email: 'budi.santoso@email.com',
        deviceId: 'DEVICE-DEMO-001',
        primaryAccount: '1001002003',
        isActive: true,
      );

      await authRepository.secureStorage.saveAuthData(
        accessToken: 'demo_offline_access_token',
        refreshToken: 'demo_offline_refresh_token',
        phoneNumber: demoUser.phoneNumber,
        cif: demoUser.cif,
        fullName: demoUser.fullName,
        primaryAccount: demoUser.primaryAccount,
      );

      emit(AuthAuthenticated(demoUser));
    } catch (e) {
      emit(AuthError('Gagal masuk mode demo: $e'));
    }
  }

  Future<void> logout() async {
    await authRepository.logout();
    emit(AuthUnauthenticated());
  }
}
