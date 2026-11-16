# Menjalankan aplikasi Flutter flavor LOCAL di HP Android fisik.
# API diarahkan ke IP LAN komputer Windows ini (bukan localhost), port backend dari .env (APP_PORT).
#
# Pemakaian (HP terhubung USB dengan USB debugging aktif, satu Wi-Fi dengan komputer):
#   .\scripts\local\run-flutter.ps1
#   .\scripts\local\run-flutter.ps1 -LanIp 192.168.1.20      (bila deteksi otomatis salah)
param([string]$LanIp = "", [int]$Port = 0)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\..")

if ($Port -eq 0) {
    $Port = 8080
    if (Test-Path ".env") {
        $line = Select-String -Path ".env" -Pattern '^\s*APP_PORT\s*=\s*(\d+)\s*$' | Select-Object -First 1
        if ($line) { $Port = [int]$line.Matches[0].Groups[1].Value }
    }
}

if (-not $LanIp) {
    # IPv4 privat dari adaptor Wi-Fi/Ethernet yang aktif dan punya default gateway.
    $LanIp = Get-NetIPConfiguration |
        Where-Object { $_.IPv4DefaultGateway -ne $null -and $_.NetAdapter.Status -eq 'Up' } |
        ForEach-Object { $_.IPv4Address.IPAddress } |
        Where-Object { $_ -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' } |
        Select-Object -First 1
}
if (-not $LanIp) { throw "IP LAN tidak terdeteksi. Jalankan ipconfig lalu ulangi dengan -LanIp <IP Wi-Fi komputer>." }

$api = "http://${LanIp}:${Port}"
Write-Host "Flavor local -> API $api"
Write-Host "Pastikan backend berjalan (scripts\local\run-api.ps1) dan bisa dibuka dari browser HP: $api/health"

Set-Location "m_banking_bpr"
flutter run --debug --dart-define-from-file=config/local.json --dart-define=API_BASE_URL=$api
