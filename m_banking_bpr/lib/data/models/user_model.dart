class UserModel {
  final String id;
  final String nik;
  final String cif;
  final String fullName;
  final String phoneNumber;
  final String email;
  final String alamat;
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
    this.nik = '',
    required this.cif,
    required this.fullName,
    required this.phoneNumber,
    required this.email,
    this.alamat = '',
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
      nik: json['nik'] ?? '',
      cif: json['cif'] ?? '',
      fullName: json['full_name'] ?? json['nama'] ?? '',
      phoneNumber: json['phone_number'] ?? json['nohp'] ?? '',
      email: json['email'] ?? '',
      alamat: json['alamat'] ?? '',
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
        'nik': nik,
        'cif': cif,
        'full_name': fullName,
        'phone_number': phoneNumber,
        'email': email,
        'alamat': alamat,
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
}

class AuthResponseModel {
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final UserModel user;

  AuthResponseModel({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
  });

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    return AuthResponseModel(
      accessToken: json['access_token'] ?? '',
      refreshToken: json['refresh_token'] ?? '',
      tokenType: json['token_type'] ?? 'Bearer',
      expiresIn: json['expires_in'] ?? 900,
      user: UserModel.fromJson(json['user'] ?? {}),
    );
  }
}

