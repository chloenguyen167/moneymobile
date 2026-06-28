#!/usr/bin/env bash
# Đồng bộ Team ID từ Xcode (ưu tiên) hoặc Keychain → Signing.xcconfig
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING="$ROOT/ios/Flutter/Signing.xcconfig"

detect_xcode_team() {
  (cd "$ROOT/ios" && xcodebuild -workspace Runner.xcworkspace -scheme Runner \
    -configuration Release -destination 'generic/platform=iOS' \
    -showBuildSettings 2>/dev/null | sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM = //p' | head -1) || true
}

detect_keychain_team() {
  security find-identity -v -p codesigning 2>/dev/null | \
    grep "Apple Development" | head -1 | \
    sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' || true
}

XCODE_TEAM="$(detect_xcode_team)"
KEYCHAIN_TEAM="$(detect_keychain_team)"
TEAM="${XCODE_TEAM:-$KEYCHAIN_TEAM}"

CERT_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Development' | head -1 || true)"
CERT_EMAIL="$(echo "$CERT_LINE" | sed -n 's/.*Apple Development: \([^)]*\) ([A-Z0-9]*).*/\1/p')"

if [[ -z "$TEAM" ]]; then
  echo "❌ Không tìm thấy Team ID."
  echo "   open ios/Runner.xcworkspace > Runner > Signing > chọn Personal Team"
  open "$ROOT/ios/Runner.xcworkspace" 2>/dev/null || true
  exit 1
fi

if [[ -n "$XCODE_TEAM" && -n "$KEYCHAIN_TEAM" && "$XCODE_TEAM" != "$KEYCHAIN_TEAM" ]]; then
  echo "⚠ Team lệch: Xcode=$XCODE_TEAM, Keychain=$KEYCHAIN_TEAM"
  echo "  → Dùng Team từ Xcode: $XCODE_TEAM"
  TEAM="$XCODE_TEAM"
fi

echo "✓ Team ID: $TEAM"
[[ -n "$CERT_EMAIL" ]] && echo "✓ Apple ID: $CERT_EMAIL"
echo ""

BUNDLE="${BUNDLE_ID:-com.tuchi.tuchi}"
cat > "$SIGNING" <<EOF
// Auto-sync — $(date +%Y-%m-%d)
DEVELOPMENT_TEAM = $TEAM
PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE
CODE_SIGN_STYLE = Automatic
EOF

echo "✓ Đã ghi ios/Flutter/Signing.xcconfig"
echo "→ Cắm iPad, Run (⌘R) trong Xcode một lần nếu chưa có profile"
echo "→ Chạy: ./scripts/build_ipa_ac.sh"
