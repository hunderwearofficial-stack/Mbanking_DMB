# Menjalankan backend Go LOCAL (membaca .env, APP_ENV=local).
# Kode OTP mode SANDBOX tampil di jendela ini (baris "[SANDBOX OTP ...]").
# Pemakaian:  .\scripts\local\run-api.ps1
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\..")
go run ./cmd/api -check-config
if ($LASTEXITCODE -ne 0) { throw "Perbaiki .env sesuai pesan di atas (lihat docs/ENVIRONMENT_SETUP.md)." }
go run ./cmd/api
