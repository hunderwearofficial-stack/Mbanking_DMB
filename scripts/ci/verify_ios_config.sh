#!/usr/bin/env bash
# CI security gate for the iOS project configuration (run before an App Store build).
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)/m_banking_bpr/ios"
fail=0
err() { echo "GATE FAIL: $*" >&2; fail=1; }
plist="$root/Runner/Info.plist"
grep -A1 'NSAllowsArbitraryLoads' "$plist" | grep -q '<true/>' && err "NSAllowsArbitraryLoads=true (HTTP diizinkan)"
grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.example' "$root/Runner.xcodeproj/project.pbxproj" && err "bundle ID template com.example — NEEDS BANK INPUT"
grep -q 'appattest-environment' "$root/Runner/Runner.entitlements" || err "entitlement App Attest tidak ada"
grep -A1 'appattest-environment' "$root/Runner/Runner.entitlements" | grep -q '<string>production</string>' || err "App Attest environment bukan production"
[ "$(grep -c 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;' "$root/Runner.xcodeproj/project.pbxproj")" -ge 3 ] || err "entitlements tidak terpasang di semua konfigurasi Runner"
[ "$fail" -eq 0 ] && echo "GATE PASS: konfigurasi iOS"
exit "$fail"
