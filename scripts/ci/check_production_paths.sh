#!/usr/bin/env bash
# Static gate: no test doubles, test CAs or fallback identifiers on production paths.
set -uo pipefail
cd "$(dirname "$0")/../.."
fail=0
err() { echo "GATE FAIL: $*" >&2; fail=1; }

# Go: the test attestation CA package may only be imported by _test.go files.
bad=$(grep -rl 'internal/devicebind/attesttest' --include='*.go' . | grep -v '_test.go$' | grep -v '^./internal/devicebind/attesttest/' || true)
[ -z "$bad" ] || err "attesttest diimpor dari kode produksi: $bad"
# Go: no certificate / private key material embedded in production sources.
bad=$(grep -rlE 'BEGIN (CERTIFICATE|PRIVATE KEY|EC PRIVATE KEY)' --include='*.go' internal pkg cmd config | grep -v '_test.go$' || true)
[ -z "$bad" ] || err "material kunci/sertifikat tertanam di kode produksi: $bad"
# Flutter: no fallback identifier generation, no in-memory secure storage, no test helpers.
grep -rnE "ANDROID-SM-|_memoryFallback|Random\.secure" m_banking_bpr/lib/core/security && err "fallback identitas/penyimpanan di lib/core/security"
grep -rn "test/helpers\|device_test_harness" m_banking_bpr/lib && err "helper test diimpor dari lib/"
# Native: no software-key fallback and no legacy identifier derivation.
grep -n "legacyIdentifier\|getHardwareDeviceId" m_banking_bpr/android/app/src/main/kotlin -r && err "turunan ID lama masih ada di Kotlin"
grep -n "kSecAttrTokenIDSecureEnclave" m_banking_bpr/ios/Runner/AppDelegate.swift >/dev/null || err "Secure Enclave tidak dipakai di iOS"
# Release signing: no debug-key fallback in Gradle.
grep -n 'signingConfigs.getByName("debug")' m_banking_bpr/android/app/build.gradle.kts && err "release memakai debug key"

# Network: the default (production) configuration never allows HTTP.
nsc=m_banking_bpr/android/app/src/main/res/xml/network_security_config.xml
grep -q 'cleartextTrafficPermitted="true"' "$nsc" && err "network_security_config.xml (production) mengizinkan HTTP"
grep -q 'android:usesCleartextTraffic="true"' m_banking_bpr/android/app/src/main/AndroidManifest.xml && err "manifest mengizinkan HTTP untuk semua build"
grep -q 'NSAllowsArbitraryLoads' m_banking_bpr/ios/Runner/Info.plist && err "Info.plist mengizinkan HTTP (NSAllowsArbitraryLoads)"
# Screenshot / screen-recording protection (FLAG_SECURE) must be on at start-up and must not be
# switchable off in release builds (temporary demo relaxations must not reach production).
ma=m_banking_bpr/android/app/src/main/kotlin/com/example/m_banking_bpr/MainActivity.kt
grep -A4 'override fun onCreate' "$ma" | grep -qE '^\s*window\.setFlags\(WindowManager\.LayoutParams\.FLAG_SECURE' || err "FLAG_SECURE tidak diaktifkan di MainActivity.onCreate"
grep -q 'FLAG_DEBUGGABLE' "$ma" || err "setFlagSecure dapat mematikan FLAG_SECURE di build release (guard debuggable hilang)"
grep -q 'setFlagSecure(false)' m_banking_bpr/lib/main.dart && err "main.dart mematikan FLAG_SECURE saat start"
# Release build only from a configured flavor; production flavor requires HTTPS.
grep -q 'APP_FLAVOR tidak diset' m_banking_bpr/android/app/build.gradle.kts || err "guard flavor release hilang dari build.gradle.kts"

[ "$fail" -eq 0 ] && echo "GATE PASS: jalur produksi bersih"
exit "$fail"
