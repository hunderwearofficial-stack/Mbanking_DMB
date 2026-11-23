# Menjalankan PostgreSQL LOCAL (docker-compose.local.yml) memakai nilai dari .env.
# Database hanya mendengarkan di 127.0.0.1:<DB_PORT> (tidak terbuka ke HP / jaringan).
# Pemakaian (dari root repository):  .\scripts\local\start-db.ps1
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\..")
if (-not (Test-Path ".env")) {
    throw ".env belum ada. Jalankan: Copy-Item .env.example .env  lalu isi nilainya (lihat docs/LOCAL_SETUP.md)."
}
docker compose --env-file .env -f docker-compose.local.yml up -d --wait
if ($LASTEXITCODE -ne 0) { throw "PostgreSQL local gagal dijalankan. Pastikan Docker Desktop berjalan." }
Write-Host "PostgreSQL local siap."
