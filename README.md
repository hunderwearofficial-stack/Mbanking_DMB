# MBanking BPR — PT BPR Dana Mandiri Bogor

| Komponen | Teknologi | Lokasi |
|---|---|---|
| Backend API | Go 1.25, Gin, GORM, PostgreSQL 16, Redis 7 | `cmd/`, `config/`, `internal/`, `pkg/` |
| Aplikasi nasabah | Flutter 3.35 (Android) | `m_banking_bpr/` |
| Konsol petugas | HTML/JS statis (disajikan backend di `/admin`) | `web/admin/` |
| Integrasi Core Banking | CBS OpenAPI Bank DMB | `internal/cbsprovider/`, kontrak `api/cbs/` |

> **Status (13 November 2026):** siap untuk **pengujian local** (Windows + HP Android). **Belum
> siap production** dan belum pernah di-deploy — prasyarat:
> [docs/DEPLOYMENT_AND_CICD.md](docs/DEPLOYMENT_AND_CICD.md) §6.

## Dokumentasi

| Dokumen | Untuk |
|---|---|
| [USER_MANUAL.md](docs/USER_MANUAL.md) | Buku panduan nasabah (draf) |
| [SYSTEM_ARCHITECTURE.md](docs/SYSTEM_ARCHITECTURE.md) | Arsitektur, API, alur login/saldo/mutasi/transfer, CBS, database |
| [SECURITY_AND_OJK.md](docs/SECURITY_AND_OJK.md) | Kontrol keamanan, matriks bukti, dan bahan pemeriksaan OJK |
| [LOCAL_SETUP.md](docs/LOCAL_SETUP.md) | Instalasi dan pengujian local (Windows + HP Android) |
| [ENVIRONMENT_SETUP.md](docs/ENVIRONMENT_SETUP.md) | Local/development/staging/production dan seluruh variabel konfigurasi |
| [DEPLOYMENT_AND_CICD.md](docs/DEPLOYMENT_AND_CICD.md) | Instalasi server, rilis aplikasi, CI/CD, rollback |
| [OPERATIONS_AND_BACKUP.md](docs/OPERATIONS_AND_BACKUP.md) | Monitoring, log, backup/restore, DR, insiden |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Masalah umum dan solusinya |

## Mulai cepat (local, PowerShell)

```powershell
Copy-Item .env.example .env            # lalu isi nilai yang kosong (docs/LOCAL_SETUP.md §3)
go run ./cmd/api -check-config         # periksa konfigurasi
.\scripts\local\start-db.ps1           # PostgreSQL local (Docker, 127.0.0.1:5433)
.\scripts\local\migrate.ps1            # migrasi skema
.\scripts\local\create-test-customer.ps1 -Cif 990000000001 -Phone 081200000001 -Account 9900000000001 -Name "Nasabah Uji Satu" -Balance 1000000
.\scripts\local\run-api.ps1            # backend di port 8080
.\scripts\local\run-flutter.ps1        # aplikasi di HP Android (IP LAN otomatis)
```

Konfigurasi: satu template [`.env.example`](.env.example); `.env` hanya untuk local dan tidak masuk
Git. Server memakai environment server atau secret manager.

## Struktur

```
cmd/              api · migrate · localfixture · auditverify · rekey
config/           loader konfigurasi
internal/         app · module/{auth,account,transaction,customer,admin} · cbsprovider · ownership
                  otp · notification · audit · session · rekey · domain · model
pkg/              database (+migrations) · money · security · crypto · middleware · logger · redis · response · reqctx
test/integration/ integration test
m_banking_bpr/    aplikasi Flutter
web/admin/        konsol petugas
api/cbs/          spesifikasi OpenAPI dan koleksi Postman CBS
deploy/           nginx · systemd · sql · docker · skrip backup/restore
scripts/local/    skrip PowerShell pengujian local
docs/             dokumentasi (8 dokumen di atas)
```

## Pengujian

```powershell
go build ./... ; go vet ./... ; go test ./...
cd m_banking_bpr; flutter analyze; flutter test --dart-define=APP_FLAVOR=local --dart-define=API_BASE_URL=http://192.168.1.20:8080
```

Integration test dan race test: [docs/LOCAL_SETUP.md](docs/LOCAL_SETUP.md) §14.
