#!/usr/bin/env bash
# CI security gate for a production Android artifact (DB-H8, production configuration).
# Usage: scripts/ci/verify_android_release.sh path/to/app-release.apk
# Required: DMB_ANDROID_RELEASE_CERT_SHA256 = SHA-256 of the bank's release signing
#           certificate (hex, colons optional) — the same value as the server setting
#           DEVICE_ATTESTATION_ANDROID_CERT_SHA256. ANDROID_HOME (build-tools).
set -euo pipefail
apk="${1:?apk path}"
fail=0
err() { echo "GATE FAIL: $*" >&2; fail=1; }

bt="$(ls -d "${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"/build-tools/* 2>/dev/null | sort -V | tail -1)"
[ -n "$bt" ] || { echo "build-tools tidak ditemukan (ANDROID_HOME)" >&2; exit 2; }
apksigner="$bt/apksigner"; [ -x "$apksigner" ] || apksigner="$bt/apksigner.bat"
aapt2="$bt/aapt2"; [ -x "$aapt2" ] || aapt2="$bt/aapt2.exe"

expected="$(echo "${DMB_ANDROID_RELEASE_CERT_SHA256:-}" | tr -d ': ' | tr 'A-F' 'a-f')"
[ -n "$expected" ] || err "DMB_ANDROID_RELEASE_CERT_SHA256 belum diisi (NEEDS BANK INPUT)"

certs="$("$apksigner" verify --print-certs "$apk" 2>&1)" || err "tanda tangan APK tidak valid"
actual="$(echo "$certs" | grep -i 'certificate SHA-256 digest' | head -1 | awk -F': ' '{print $2}' | tr -d ': ' | tr 'A-F' 'a-f' || true)"
echo "$certs" | grep -qi 'CN=Android Debug' && err "APK ditandatangani debug key"
[ -n "$expected" ] && [ "$actual" != "$expected" ] && err "sertifikat signing ($actual) bukan sertifikat resmi"

manifest="$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk")"
pkg="$("$aapt2" dump packagename "$apk")"
echo "$manifest" | grep -qE 'debuggable\(0x0101000f\)=(true|\(type 0x12\)0xffffffff)' && err "APK debuggable"
echo "$manifest" | grep -qE 'usesCleartextTraffic\(0x010104ec\)=(true|\(type 0x12\)0xffffffff)' && err "usesCleartextTraffic=true (HTTP diizinkan)"
case "$pkg" in com.example.*) err "applicationId template ($pkg) — NEEDS BANK INPUT";; esac
[ -n "${DMB_ANDROID_PACKAGE:-}" ] && [ "$pkg" != "$DMB_ANDROID_PACKAGE" ] && err "applicationId $pkg bukan $DMB_ANDROID_PACKAGE"

# Build identity stamped by build.gradle.kts from the APP_FLAVOR / API_BASE_URL dart-defines.
meta() { echo "$manifest" | grep -A1 "\"$1\"" | grep -o "value(0x01010024)=[^ ]*" | head -1 | sed -e "s/^value(0x01010024)=//" -e "s/^\"//" -e "s/\"$//" || true; }
flavor="$(meta id.bprdmb.app_flavor)"
https="$(meta id.bprdmb.api_https)"
[ "$flavor" = "production" ] || err "flavor artefak '${flavor:-tidak ada}' bukan production (config/production.json)"
[ "$https" = "true" ] || err "API_BASE_URL artefak bukan https://"

[ "$fail" -eq 0 ] && echo "GATE PASS: $pkg, signer $actual"
exit "$fail"
