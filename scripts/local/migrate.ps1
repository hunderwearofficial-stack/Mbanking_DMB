# Menerapkan migrasi skema ke database LOCAL sebagai pemilik skema (MIGRATION_DB_USER di .env).
# Pemakaian:  .\scripts\local\migrate.ps1           (terapkan migrasi)
#             .\scripts\local\migrate.ps1 status    (lihat status)
param([ValidateSet("up", "status", "grants")][string]$Command = "up")
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\..")
go run ./cmd/migrate $Command
if ($LASTEXITCODE -ne 0) { throw "migrasi gagal" }
