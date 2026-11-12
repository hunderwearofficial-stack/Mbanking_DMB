import 'dart:developer';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'secure_storage_service.dart';

class BiometricCapability {
  final bool isSupported;
  final bool canCheckBiometrics;
  final List<BiometricType> availableBiometrics;
  final bool hasFingerprint;
  final bool hasFace;
  final String label;

  const BiometricCapability({
    required this.isSupported,
    required this.canCheckBiometrics,
    required this.availableBiometrics,
    required this.hasFingerprint,
    required this.hasFace,
    required this.label,
  });

  bool get canAuthenticate => isSupported && canCheckBiometrics && availableBiometrics.isNotEmpty;
}

class BiometricAuthResult {
  final bool success;
  final String? errorMessage;
  final bool isLockedOut;

  const BiometricAuthResult({
    required this.success,
    this.errorMessage,
    this.isLockedOut = false,
  });
}

class BiometricAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Inspects device hardware and enrolled biometric sensors (Fingerprint / Face ID)
  static Future<BiometricCapability> checkCapability() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final available = await _auth.getAvailableBiometrics();

      final hasFingerprint = available.contains(BiometricType.fingerprint) ||
          available.contains(BiometricType.strong) ||
          available.contains(BiometricType.weak);
      final hasFace = available.contains(BiometricType.face);

      String label = 'Biometrik';
      if (hasFace && hasFingerprint) {
        label = 'Sidik Jari & Wajah';
      } else if (hasFace) {
        label = 'Wajah (Face ID)';
      } else if (hasFingerprint) {
        label = 'Sidik Jari';
      }

      return BiometricCapability(
        isSupported: isSupported,
        canCheckBiometrics: canCheck,
        availableBiometrics: available,
        hasFingerprint: hasFingerprint,
        hasFace: hasFace,
        label: label,
      );
    } catch (e) {
      log('[BIOMETRIC ERROR] Gagal memeriksa kapabilitas biometrik: $e');
      return const BiometricCapability(
        isSupported: false,
        canCheckBiometrics: false,
        availableBiometrics: [],
        hasFingerprint: false,
        hasFace: false,
        label: 'Tidak Tersedia',
      );
    }
  }

  /// Prompts native Android / iOS biometric authentication dialog
  static Future<BiometricAuthResult> authenticate({
    String reason = 'Pindai sidik jari atau Face ID Anda untuk masuk ke Mobile DMB',
    String cancelButton = 'Gunakan Password',
  }) async {
    try {
      final canAuth = await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
      if (!canAuth) {
        return const BiometricAuthResult(
          success: false,
          errorMessage: 'Perangkat Anda tidak mendukung sensor biometrik atau belum didaftarkan.',
        );
      }

      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        authMessages: <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'Autentikasi Biometrik Mobile DMB',
            biometricHint: 'Sentuh sensor sidik jari untuk verifikasi identitas',
            cancelButton: cancelButton,
          ),
        ],
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
          useErrorDialogs: true,
        ),
      );

      return BiometricAuthResult(success: authenticated);
    } on PlatformException catch (e) {
      log('[BIOMETRIC EXCEPTION] Code: ${e.code}, Message: ${e.message}');
      String message = 'Autentikasi biometrik dibatalkan.';

      if (e.code == 'NotAvailable') {
        message = 'Sensor biometrik tidak tersedia saat ini.';
      } else if (e.code == 'NotEnrolled') {
        message = 'Belum ada sidik jari/Face ID yang didaftarkan di pengaturan perangkat ponsel Anda.';
      } else if (e.code == 'LockedOut') {
        return const BiometricAuthResult(
          success: false,
          errorMessage: 'Terlalu banyak percobaan gagal. Sensor biometrik terkunci sementara (30 detik).',
          isLockedOut: true,
        );
      } else if (e.code == 'PermanentlyLockedOut') {
        return const BiometricAuthResult(
          success: false,
          errorMessage: 'Sensor biometrik terkunci permanen. Buka kunci menggunakan PIN/pola ponsel Anda terlebih dahulu.',
          isLockedOut: true,
        );
      } else if (e.code == 'no_fragment_activity') {
        message = 'Sistem Android memerlukan FragmentActivity untuk biometrik.';
      }

      return BiometricAuthResult(success: false, errorMessage: message);
    } catch (e) {
      return BiometricAuthResult(
        success: false,
        errorMessage: 'Terjadi kesalahan pada sistem biometrik: $e',
      );
    }
  }

  /// Checks if the user has previously enabled biometric login in settings
  static Future<bool> isBiometricLoginEnabled(SecureStorageService storage) async {
    return await storage.isBiometricEnabled();
  }
}

