/// Holds, for the current app session only, the id of the consent the backend recorded
/// for this device (POST /api/v1/terms/acceptances). It is sent with login/activation so
/// the backend can link the consent to the customer.
///
/// This is NOT the consent status: the backend is the source of truth and decides at
/// login/refresh whether the Terms in force were accepted. Nothing is persisted on the
/// device.
class TermsConsentStore {
  TermsConsentStore._();
  static final TermsConsentStore instance = TermsConsentStore._();

  String? _acceptanceId;
  String? _versionId;

  String? get acceptanceId => _acceptanceId;
  String? get versionId => _versionId;

  void record({required String acceptanceId, required String versionId}) {
    _acceptanceId = acceptanceId;
    _versionId = versionId;
  }

  void clear() {
    _acceptanceId = null;
    _versionId = null;
  }
}
