# Aplikasi Mobile MBanking BPR (Flutter)

Panduan menjalankan: [../docs/LOCAL_SETUP.md](../docs/LOCAL_SETUP.md) · konfigurasi flavor:
[../docs/ENVIRONMENT_SETUP.md](../docs/ENVIRONMENT_SETUP.md) §4 · arsitektur:
[../docs/SYSTEM_ARCHITECTURE.md](../docs/SYSTEM_ARCHITECTURE.md) §10 · fitur nasabah:
[../docs/USER_MANUAL.md](../docs/USER_MANUAL.md).

## Struktur

```
lib/
├── main.dart                 validasi konfigurasi build → aplikasi / layar kesalahan konfigurasi
├── core/   config (flavor) · constants · money · network (ApiClient) · security · services (FCM) · theme · utils
├── data/   models · repositories (meneruskan error; tanpa data dummy)
└── presentation/  blocs (AuthCubit, AccountCubit) · screens
config/     local.json · development.json · staging.json · production.json (tanpa secret)
test/       core · data · presentation · helpers
```

## Menjalankan di HP Android (local)

```powershell
..\scripts\local\run-flutter.ps1     # dari root repository: .\scripts\local\run-flutter.ps1
```

## Pengujian

```powershell
flutter analyze
flutter test --dart-define=APP_FLAVOR=local --dart-define=API_BASE_URL=http://192.168.1.20:8080
```

## Perlu dikonfirmasi bank sebelum rilis

Kontak layanan (`lib/core/constants/bank_contact.dart`) · suku bunga ilustrasi
(`lib/core/constants/product_rates.dart`) · proyek Firebase resmi · `applicationId` & keystore
rilis · domain & pin sertifikat per environment (`config/*.json`) · temuan tampilan di
[../docs/USER_MANUAL.md](../docs/USER_MANUAL.md) bagian 13.
