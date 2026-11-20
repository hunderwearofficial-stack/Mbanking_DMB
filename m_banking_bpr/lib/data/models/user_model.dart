import 'device_binding_model.dart';

class UserModel {
  final String id;
  final String cif;
  final String fullName;
  final String username;
  final String phoneNumber;
  final String email;
  final String kodePos;
  final String jenisKelamin;
  final String agama;
  final String tglLahir;
  final String tempatLahir;
  final String namaIbuKandung;
  final String deviceId;
  final String primaryAccount;
  final bool isActive;

  UserModel({
    required this.id,
    required this.cif,
    required this.fullName,
    this.username = '',
    required this.phoneNumber,
    required this.email,
    this.kodePos = '',
    this.jenisKelamin = '',
    this.agama = '',
    this.tglLahir = '',
    this.tempatLahir = '',
    this.namaIbuKandung = '',
    required this.deviceId,
    required this.primaryAccount,
    required this.isActive,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      cif: json['cif'] ?? '',
      fullName: json['full_name'] ?? json['nama'] ?? '',
      username: json['username'] ?? '',
      phoneNumber: json['phone_number'] ?? json['nohp'] ?? '',
      email: json['email'] ?? '',
      kodePos: json['kode_pos'] ?? '',
      jenisKelamin: json['jenis_kelamin'] ?? '',
      agama: json['agama'] ?? '',
      tglLahir: json['tgl_lahir'] ?? '',
      tempatLahir: json['tempat_lahir'] ?? '',
      namaIbuKandung: json['nama_ibu_kandung'] ?? '',
      deviceId: json['device_id'] ?? '',
      primaryAccount: json['primary_account'] ?? '',
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'cif': cif,
        'full_name': fullName,
        'username': username,
        'phone_number': phoneNumber,
        'email': email,
        'kode_pos': kodePos,
        'jenis_kelamin': jenisKelamin,
        'agama': agama,
        'tgl_lahir': tglLahir,
        'tempat_lahir': tempatLahir,
        'nama_ibu_kandung': namaIbuKandung,
        'device_id': deviceId,
        'primary_account': primaryAccount,
        'is_active': isActive,
      };

  String get cifNumber => cif;
}

class AuthResponseModel {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final UserModel user;
  final DeviceBindingStatusModel? deviceBinding;

  AuthResponseModel({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
    this.deviceBinding,
  });

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    return AuthResponseModel(
      accessToken: json['access_token'] ?? '',
      refreshToken: json['refresh_token'] ?? '',
      tokenType: json['token_type'] ?? 'Bearer',
      expiresIn: json['expires_in'] ?? 900,
      user: UserModel.fromJson(json['user'] ?? {}),
      deviceBinding: json['device_binding'] is Map<String, dynamic>
          ? DeviceBindingStatusModel.fromJson(json['device_binding'] as Map<String, dynamic>)
          : null,
    );
  }
}

