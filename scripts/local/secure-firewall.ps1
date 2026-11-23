# Mengamankan komputer pengembangan Windows untuk pengujian lokal MBanking BPR.
# JALANKAN di PowerShell "Run as Administrator":
#   powershell -ExecutionPolicy Bypass -File .\scripts\local\secure-firewall.ps1
#
# Yang dilakukan:
#   1. Memblokir koneksi MASUK ke PostgreSQL (TCP 5432 dan 5433) dari komputer lain.
#      (Koneksi dari komputer ini sendiri / localhost tetap berjalan.)
#   2. Mengizinkan backend Go (TCP 8080) HANYA dari subnet jaringan lokal (HP Android di Wi-Fi yang sama).
#   3. Mengaktifkan Windows Firewall untuk profil Domain, Private, dan Public.
# Tidak ada data, container, atau database yang diubah.
$ErrorActionPreference = "Stop"

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Jalankan skrip ini dari PowerShell 'Run as Administrator'."
}

function Set-Rule($name, [scriptblock]$create) {
    Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    & $create | Out-Null
    Write-Host "OK  $name"
}

Set-Rule "MBankingBPR - Blokir PostgreSQL dari jaringan" {
    New-NetFirewallRule -DisplayName "MBankingBPR - Blokir PostgreSQL dari jaringan" `
        -Direction Inbound -Protocol TCP -LocalPort 5432,5433 -Action Block -Profile Any
}

Set-Rule "MBankingBPR - Backend 8080 dari LAN" {
    New-NetFirewallRule -DisplayName "MBankingBPR - Backend 8080 dari LAN" `
        -Direction Inbound -Protocol TCP -LocalPort 8080 -RemoteAddress LocalSubnet -Action Allow -Profile Any
}

Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled True
Write-Host "OK  Windows Firewall aktif (Domain, Private, Public)"

Get-NetFirewallProfile | Format-Table Name, Enabled, DefaultInboundAction -AutoSize
