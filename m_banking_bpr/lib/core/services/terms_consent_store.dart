import 'package:shared_preferences/shared_preferences.dart';

class TermsConsentStore {
  TermsConsentStore._();
  static final TermsConsentStore instance = TermsConsentStore._();

  static const String _prefAcceptanceKey = 'dmb_terms_acceptance_id';
  static const String _prefVersionKey = 'dmb_terms_version_id';
  static const String _prefCompletedKey = 'dmb_terms_completed';

  String? _acceptanceId;
  String? _versionId;
  bool _completed = false;

  String? get acceptanceId => _acceptanceId;
  String? get versionId => _versionId;

  /// True once the user has accepted S&K on this device (even after one-time
  /// [acceptanceId] is consumed and cleared on login/activation).
  bool get hasAccepted =>
      _completed || (_acceptanceId != null && _acceptanceId!.isNotEmpty);

  void record({required String acceptanceId, required String versionId}) {
    _acceptanceId = acceptanceId;
    _versionId = versionId;
    _completed = true;
  }

  Future<void> persist({
    required String acceptanceId,
    required String versionId,
  }) async {
    record(acceptanceId: acceptanceId, versionId: versionId);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefAcceptanceKey, acceptanceId);
      await prefs.setString(_prefVersionKey, versionId);
      await prefs.setBool(_prefCompletedKey, true);
    } catch (_) {}
  }

  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _completed = prefs.getBool(_prefCompletedKey) ?? false;
      final acc = prefs.getString(_prefAcceptanceKey)?.trim();
      final ver = prefs.getString(_prefVersionKey)?.trim();
      if (acc != null && acc.isNotEmpty && ver != null && ver.isNotEmpty) {
        _acceptanceId = acc;
        _versionId = ver;
      }
    } catch (_) {}
  }

  /// Clears the one-time pre-login [acceptanceId] after it has been linked
  /// to a customer account on the backend, while keeping [_completed] so the
  /// user is not forced back through Onboarding / S&K on every login/restart.
  Future<void> clear() async {
    _acceptanceId = null;
    _versionId = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefAcceptanceKey);
      await prefs.remove(_prefVersionKey);
    } catch (_) {}
  }
}
