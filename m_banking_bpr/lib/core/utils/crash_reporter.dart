import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A sanitized error record: the error type and the top stack frames only, never the
/// message (it may contain customer data such as names or account numbers).
class CrashRecord {
  final DateTime at;
  final String type;
  final String stack;
  final bool fatal;

  const CrashRecord({required this.at, required this.type, required this.stack, required this.fatal});
}

/// Destination for crash records (for example a Crashlytics/Sentry adapter). The bank
/// selects and configures the service; until then records are kept in memory only.
typedef CrashSink = FutureOr<void> Function(CrashRecord record);

/// Global error capture (audit MA-04): uncaught framework, platform and zone errors are
/// recorded instead of disappearing, and a release build shows a neutral fallback widget
/// rather than a red/grey error screen.
class CrashReporter {
  CrashReporter._();

  static const int _maxRecords = 20;
  static final List<CrashRecord> _records = <CrashRecord>[];
  static CrashSink? sink;

  static List<CrashRecord> get recent => List.unmodifiable(_records);

  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      record(details.exception, details.stack, fatal: false);
      if (kDebugMode) {
        (previous ?? FlutterError.presentError)(details);
      }
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      record(error, stack, fatal: true);
      return true;
    };
    if (kReleaseMode) {
      ErrorWidget.builder = (FlutterErrorDetails _) => const _ReleaseErrorWidget();
    }
  }

  static void record(Object error, StackTrace? stack, {required bool fatal}) {
    final frames = (stack?.toString() ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(8).join('\n');
    final rec = CrashRecord(at: DateTime.now().toUtc(), type: error.runtimeType.toString(), stack: frames, fatal: fatal);
    _records.add(rec);
    if (_records.length > _maxRecords) _records.removeAt(0);
    if (kDebugMode) {
      debugPrint('[CrashReporter] ${rec.type}${fatal ? ' (fatal)' : ''}\n$error\n${rec.stack}');
    }
    final s = sink;
    if (s != null) {
      try {
        final r = s(rec);
        if (r is Future) r.catchError((Object _) {});
      } catch (_) {
        // Reporting must never crash the app.
      }
    }
  }
}

class _ReleaseErrorWidget extends StatelessWidget {
  const _ReleaseErrorWidget();

  @override
  Widget build(BuildContext context) {
    return const Material(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Tampilan ini belum dapat dimuat. Silakan kembali dan coba lagi.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF475569)),
          ),
        ),
      ),
    );
  }
}
