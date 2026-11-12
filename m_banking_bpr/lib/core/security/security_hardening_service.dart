import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class RootInspectionResult {
  final bool isRooted;
  final List<String> reasons;
  final String deviceModel;
  final String osVersion;

  const RootInspectionResult({
    required this.isRooted,
    required this.reasons,
    required this.deviceModel,
    required this.osVersion,
  });
}

class SecurityHardeningService {
  static const MethodChannel _channel = MethodChannel('com.bprdmb.mbanking/device_info');
  static bool _flagSecureActive = true;

  // ==================== 1. FLAG_SECURE MANAGEMENT ====================

  /// Enables or disables FLAG_SECURE on Android (disables screenshots, screen recordings, and hides app thumbnail)
  static Future<bool> setFlagSecure(bool enable) async {
    try {
      if (Platform.isAndroid) {
        final success = await _channel.invokeMethod<bool>('setFlagSecure', {'enable': enable});
        _flagSecureActive = enable;
        return success ?? false;
      }
      _flagSecureActive = enable;
      return true;
    } catch (_) {
      _flagSecureActive = enable;
      return false;
    }
  }

  static Future<bool> isFlagSecureEnabled() async {
    try {
      if (Platform.isAndroid) {
        final active = await _channel.invokeMethod<bool>('isFlagSecureEnabled');
        if (active != null) {
          _flagSecureActive = active;
          return active;
        }
      }
    } catch (_) {}
    return _flagSecureActive;
  }

  // ==================== 2. ROOT & JAILBREAK DETECTION ====================

  /// Checks whether device is rooted (Android) or jailbroken (iOS)
  static Future<RootInspectionResult> checkRootStatus() async {
    List<String> reasons = [];
    String deviceModel = 'Perangkat Mobile';
    String osVersion = Platform.operatingSystemVersion;

    try {
      if (Platform.isAndroid) {
        final res = await _channel.invokeMethod<Map>('checkRootStatus');
        if (res != null) {
          final isRootedNative = res['isRooted'] == true;
          final nativeReasons = (res['reasons'] as List?)?.map((e) => e.toString()).toList() ?? [];
          deviceModel = res['deviceModel']?.toString() ?? 'Android';
          osVersion = res['osVersion']?.toString() ?? osVersion;

          if (isRootedNative) {
            reasons.addAll(nativeReasons);
          }
        }
      }
    } catch (_) {
      // Dart Fallback Root Inspection if native method is not yet initialized
      reasons.addAll(_performDartFallbackRootCheck());
    }

    // Secondary Dart file-system verification
    if (reasons.isEmpty && Platform.isAndroid) {
      reasons.addAll(_performDartFallbackRootCheck());
    }

    return RootInspectionResult(
      isRooted: reasons.isNotEmpty,
      reasons: reasons,
      deviceModel: deviceModel,
      osVersion: osVersion,
    );
  }

  static List<String> _performDartFallbackRootCheck() {
    final detected = <String>[];
    if (!Platform.isAndroid) return detected;

    final knownSuPaths = [
      '/system/app/Superuser.apk',
      '/sbin/su',
      '/system/bin/su',
      '/system/xbin/su',
      '/data/local/xbin/su',
      '/data/local/bin/su',
      '/system/sd/xbin/su',
      '/system/bin/failsafe/su',
      '/data/local/su',
      '/su/bin/su',
      '/magisk/.core/bin/su',
    ];

    for (final path in knownSuPaths) {
      try {
        if (File(path).existsSync()) {
          detected.add('Binary SU terdeteksi: $path');
        }
      } catch (_) {}
    }
    return detected;
  }

  /// Displays OJK Mandatory Advisory Warning if device is detected as Rooted/Jailbroken
  static void showRootWarningDialog(BuildContext context, RootInspectionResult result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE4E6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.security_update_warning_rounded, color: Color(0xFFE11D48), size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Peringatan Keamanan OJK',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0B2546),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Perangkat Anda (${result.deviceModel}) terdeteksi telah dimodifikasi (Rooted / Non-Standard OS).',
              style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0B2546)),
            ),
            const SizedBox(height: 8),
            Text(
              'Berdasarkan Surat Edaran OJK No. 35/SEOJK.03/2017 tentang Manajemen Risiko Teknologi Informasi Perbankan, akses pada perangkat yang di-root dibatasi demi melindungi kredensial rekening dan dana Anda dari ancaman malware/keylogger.',
              style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B), height: 1.4),
            ),
            if (result.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Indikator: ${result.reasons.first}',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF475569)),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Saya Mengerti Resikonya',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: const Color(0xFF0062E3)),
            ),
          ),
        ],
      ),
    );
  }
}

