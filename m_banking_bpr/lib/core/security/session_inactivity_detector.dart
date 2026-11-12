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

  /// Timeout in seconds (Default 180s = 3 minutes standard perbankan OJK)
  static int timeoutSeconds = 180;
  static bool isEnabled = true;
  static DateTime lastActive = DateTime.now();

  static void recordActivity() {
    lastActive = DateTime.now();
  }

  /// Sets quick test timeout (e.g. 10 or 15 seconds) for real-time device testing
  static void setQuickTestTimeout(int seconds) {
    timeoutSeconds = seconds;
    recordActivity();
  }

  /// Resets to standard 3-minute banking timeout
  static void resetToStandardTimeout() {
    timeoutSeconds = 180;
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
    // Check every 2 seconds
    _checkTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!SessionInactivityDetector.isEnabled) return;

      final elapsed = DateTime.now().difference(SessionInactivityDetector.lastActive).inSeconds;
      if (elapsed >= SessionInactivityDetector.timeoutSeconds) {
        _triggerSessionTimeout();
      }
    });
  }

  void _triggerSessionTimeout() {
    // Reset timer and reset timeout to standard 180 seconds immediately so 10s test never persists
    SessionInactivityDetector.resetToStandardTimeout();

    // Check if user is currently authenticated
    final nav = appNavigatorKey.currentState;
    final ctx = appNavigatorKey.currentContext;

    if (ctx != null) {
      final authState = ctx.read<AuthCubit>().state;
      if (authState is AuthAuthenticated) {
        // 1. Perform background logout
        ctx.read<AuthCubit>().logout();

        // 2. Redirect to Login Screen
        nav?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );

        // 3. Show Banking Inactivity Security Alert
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.timer_off_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Sesi Anda telah berakhir secara otomatis demi keamanan karena tidak ada aktivitas selama ${SessionInactivityDetector.timeoutSeconds} detik.',
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

