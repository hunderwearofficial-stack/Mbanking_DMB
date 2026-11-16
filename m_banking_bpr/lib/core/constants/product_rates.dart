/// Suku bunga ILUSTRASI untuk simulator produk (bukan penawaran).
///
/// PERHATIAN (OPEN QUESTION, lihat docs/USER_MANUAL.md bagian 13):
/// CBS OpenAPI (/api/products) tidak menyediakan suku bunga. Nilai di bawah belum
/// dikonfirmasi bank dan hanya dipakai untuk menghitung estimasi simulasi; UI wajib
/// menandainya sebagai "Ilustrasi". Suku bunga resmi harus berasal dari bank
/// (mis. konfigurasi backend) sebelum rilis. Ubah hanya di file ini.
///
/// Suku bunga dinyatakan dalam basis poin per tahun (1 bp = 0,01%) agar seluruh
/// perhitungan nominal memakai bilangan bulat (tanpa floating point).
class ProductRates {
  ProductRates._();

  /// Deposito: 6,25% per tahun.
  static const int depositoAnnualBps = 625;
  static const String depositoLabel = '6.25% p.a. (ilustrasi)';

  /// Kredit: bunga flat 1,25% per bulan = 15% per tahun.
  static const int kreditAnnualBps = 1500;
  static const String kreditLabel = '1.25% flat/bln (ilustrasi)';
}
