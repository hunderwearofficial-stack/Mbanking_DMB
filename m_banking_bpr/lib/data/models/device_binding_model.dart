class DeviceBindingStatusModel {
  final String mode; // off | dual | enforced
  final String attestationMode; // off | observe | enforce
  final bool enrolled;
  final String keyAlgorithm; // ES256 | APPATTEST
  final String securityLevel; // STRONGBOX | TEE | SECURE_ENCLAVE
  final String attestationStatus; // HARDWARE_VERIFIED | UNVERIFIED | FAILED (server-verified)
  final String enrollment; // ALLOWED | OTP_REQUIRED | NOT_NEEDED | NOT_AVAILABLE
  final String sessionDeviceId;

  const DeviceBindingStatusModel({
    this.mode = '',
    this.attestationMode = '',
    this.enrolled = false,
    this.keyAlgorithm = '',
    this.securityLevel = '',
    this.attestationStatus = '',
    this.enrollment = 'NOT_AVAILABLE',
    this.sessionDeviceId = '',
  });

  factory DeviceBindingStatusModel.fromJson(Map<String, dynamic> json) {
    String s(String k, [String d = '']) => (json[k] ?? d).toString();
    return DeviceBindingStatusModel(
      mode: s('mode'),
      attestationMode: s('attestation_mode'),
      enrolled: json['enrolled'] == true,
      keyAlgorithm: s('key_algorithm'),
      securityLevel: s('security_level'),
      attestationStatus: s('attestation_status'),
      enrollment: s('enrollment', 'NOT_AVAILABLE'),
      sessionDeviceId: s('session_device_id'),
    );
  }

  bool get isEnrollmentAllowed => enrollment == 'ALLOWED';
}

class DeviceChallengeResponseModel {
  final String challengeId;
  final String nonce;
  final String purpose;
  final DateTime? expiresAt;

  const DeviceChallengeResponseModel({required this.challengeId, required this.nonce, required this.purpose, this.expiresAt});

  factory DeviceChallengeResponseModel.fromJson(Map<String, dynamic> json) => DeviceChallengeResponseModel(
        challengeId: (json['challenge_id'] ?? '').toString(),
        nonce: (json['nonce'] ?? '').toString(),
        purpose: (json['purpose'] ?? '').toString(),
        expiresAt: json['expires_at'] == null ? null : DateTime.tryParse(json['expires_at'].toString()),
      );
}
