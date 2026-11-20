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
