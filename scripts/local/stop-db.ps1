# Menghentikan PostgreSQL LOCAL. Data TETAP tersimpan di volume Docker.
# Menghapus data local memerlukan perintah manual yang disengaja (lihat docs/LOCAL_SETUP.md);
# skrip ini sengaja tidak menyediakannya.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\..")
docker compose --env-file .env -f docker-compose.local.yml down
