# Membuat nasabah UJI di ledger local (hanya APP_ENV=local + ENABLE_MOCK_CBS=true).
# Data ini fixture pengujian yang tercatat di audit trail, BUKAN data nasabah.
# Contoh:
#   .\scripts\local\create-test-customer.ps1 -Cif 990000000001 -Phone 081200000001 -Account 9900000000001 -Name "Nasabah Uji Satu" -Balance 1000000
param(
    [Parameter(Mandatory = $true)][string]$Cif,
    [Parameter(Mandatory = $true)][string]$Phone,
    [Parameter(Mandatory = $true)][string]$Account,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][long]$Balance
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\..")
go run ./cmd/localfixture -cif $Cif -phone $Phone -account $Account -name $Name -balance $Balance
if ($LASTEXITCODE -ne 0) { throw "gagal membuat nasabah uji" }
