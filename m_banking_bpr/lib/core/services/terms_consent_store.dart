import 'package:shared_preferences/shared_preferences.dart';

class TermsConsentStore {
  TermsConsentStore._();
  static final TermsConsentStore instance = TermsConsentStore._();

  static const String _prefAcceptanceKey = 'dmb_terms_acceptance_id';
  static const String _prefVersionKey = 'dmb_terms_version_id';

  String? _acceptanceId;
  String? _versionId;

  String? get acceptanceId => _acceptanceId;
  String? get versionId => _versionId;
  bool get hasAccepted => _acceptanceId != null && _acceptanceId!.isNotEmpty;

  void record({required String acceptanceId, required String versionId}) {
    _acceptanceId = acceptanceId;
    _versionId = versionId;
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
    } catch (_) {}
  }

  Future<void> restore() async {
    if (hasAccepted) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final acc = prefs.getString(_prefAcceptanceKey)?.trim();
      final ver = prefs.getString(_prefVersionKey)?.trim();
      if (acc != null && acc.isNotEmpty && ver != null && ver.isNotEmpty) {
        _acceptanceId = acc;
        _versionId = ver;
      }
    } catch (_) {}
  }

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
