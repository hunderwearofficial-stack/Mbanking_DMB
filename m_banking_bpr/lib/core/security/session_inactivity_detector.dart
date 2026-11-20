import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../main.dart';
import '../../presentation/blocs/auth/auth_cubit.dart';
import '../../presentation/blocs/auth/auth_state.dart';
import '../../presentation/screens/auth/login_screen.dart';

class SessionInactivityDetector extends StatefulWidget {
  final Widget child;

  const SessionInactivityDetector({super.key, required this.child});

  /// Batas tidak aktif sebelum sesi dikunci. Nilai dapat disesuaikan saat build
  /// melalui `--dart-define=SESSION_IDLE_TIMEOUT_SECONDS=...` (minimal 60 detik).
  static const int standardTimeoutSeconds = _configuredTimeout < 60 ? 60 : _configuredTimeout;
  static const int _configuredTimeout = int.fromEnvironment('SESSION_IDLE_TIMEOUT_SECONDS', defaultValue: 180);

  static int timeoutSeconds = standardTimeoutSeconds;
  static bool isEnabled = true;
  static DateTime lastActive = DateTime.now();

  static void recordActivity() {
    lastActive = DateTime.now();
  }

  static void resetToStandardTimeout() {
    timeoutSeconds = standardTimeoutSeconds;
    recordActivity();
  }

  @override
  State<SessionInactivityDetector> createState() => _SessionInactivityDetectorState();
}

class _SessionInactivityDetectorState extends State<SessionInactivityDetector> {
  Timer? _checkTimer;

  @override
  void initState() {
    super.initState();
    SessionInactivityDetector.recordActivity();
    _startInactivityChecker();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    super.dispose();
  }

  void _startInactivityChecker() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!SessionInactivityDetector.isEnabled) return;

      final elapsed = DateTime.now().difference(SessionInactivityDetector.lastActive).inSeconds;
      if (elapsed >= SessionInactivityDetector.timeoutSeconds) {
        _triggerSessionTimeout();
      }
    });
  }

  void _triggerSessionTimeout() {
    SessionInactivityDetector.resetToStandardTimeout();

    final nav = appNavigatorKey.currentState;
    final ctx = appNavigatorKey.currentContext;

    if (ctx != null) {
      final authState = ctx.read<AuthCubit>().state;
      if (authState is AuthAuthenticated) {
        ctx.read<AuthCubit>().lockSession();

        nav?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );

        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.timer_off_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Demi keamanan, sesi Anda berakhir karena tidak ada aktivitas selama ${SessionInactivityDetector.timeoutSeconds ~/ 60} menit. Silakan masuk kembali.',
                    style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF0B356D),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => SessionInactivityDetector.recordActivity(),
      onPointerMove: (_) => SessionInactivityDetector.recordActivity(),
      onPointerUp: (_) => SessionInactivityDetector.recordActivity(),
      child: widget.child,
    );
  }
}

