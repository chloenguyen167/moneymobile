#!/usr/bin/env bash
# Build signed .ipa for sideload (free Apple ID, ~7 ngày).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SIGNING="$ROOT/ios/Flutter/Signing.xcconfig"

detect_team() {
  security find-identity -v -p codesigning 2>/dev/null | \
    grep "Apple Development" | head -1 | \
    sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' || true
}

write_signing() {
  local team="$1" bundle="$2"
  cat > "$SIGNING" <<EOF
// Auto-generated — single source of truth for Team ID
DEVELOPMENT_TEAM = $team
PRODUCT_BUNDLE_IDENTIFIER = $bundle
CODE_SIGN_STYLE = Automatic
EOF
}

ensure_signing_config() {
  if [[ ! -f "$SIGNING" ]] || ! grep -q "DEVELOPMENT_TEAM = [A-Z0-9]\{10\}" "$SIGNING" 2>/dev/null; then
    echo "→ Chưa có Signing.xcconfig — chạy fix_xcode_signing.sh"
    "$ROOT/scripts/fix_xcode_signing.sh"
  fi
  TEAM="$(grep DEVELOPMENT_TEAM "$SIGNING" | sed 's/.*= //' | tr -d ' ')"
  echo "✓ Team ID: $TEAM"

  # Pre-flight: Xcode phải có account khớp Team ID
  BUILD_LOG="$(mktemp)"
  if (cd "$ROOT/ios" && xcodebuild -workspace Runner.xcworkspace -scheme Runner \
        -configuration Release -destination 'generic/platform=iOS' \
        -allowProvisioningUpdates \
        -showBuildSettings 2>"$BUILD_LOG" >/dev/null); then
    rm -f "$BUILD_LOG"
    return 0
  fi
  if grep -q "No Account for Team" "$BUILD_LOG" 2>/dev/null; then
    CERT_EMAIL="$(security find-identity -v -p codesigning 2>/dev/null | grep 'Apple Development' | head -1 | sed -n 's/.*Apple Development: \([^)]*\) ([A-Z0-9]*).*/\1/p')"
    echo ""
    echo "❌ Xcode chưa đăng nhập Apple ID cho Team $TEAM"
    echo "   → Xcode > Settings > Accounts > + > đăng nhập: ${CERT_EMAIL:-Apple ID của bạn}"
    echo "   → Sau đó: open ios/Runner.xcworkspace > Runner > Signing > chọn Team"
    echo "   → Cắm iPad, Run (⌘R) một lần, rồi chạy lại script này"
    echo ""
    open "$ROOT/ios/Runner.xcworkspace" 2>/dev/null || true
    rm -f "$BUILD_LOG"
    exit 1
  fi
  if grep -q "No profiles for" "$BUILD_LOG" 2>/dev/null; then
    echo ""
    echo "❌ Chưa có provisioning profile — mở Xcode, chọn Team, Run (⌘R) với iPad cắm USB"
    open "$ROOT/ios/Runner.xcworkspace" 2>/dev/null || true
    rm -f "$BUILD_LOG"
    exit 1
  fi
  rm -f "$BUILD_LOG"
}

ensure_certificate() {
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    echo "❌ Chưa có certificate. Mở Xcode > Accounts > Apple ID, rồi Runner > Signing > Team"
    open "$ROOT/ios/Runner.xcworkspace" 2>/dev/null || true
    exit 1
  fi
}

ensure_ipad_connected() {
  local line
  line="$(xcrun xctrace list devices 2>/dev/null | grep -iE 'iPad.*\([0-9A-F-]{36}\)' | grep -vi Simulator | head -1 || true)"
  if [[ -z "$line" ]]; then
    echo ""
    echo "❌ Cắm iPad USB (unlock + Trust) TRƯỚC KHI build IPA"
    echo "   IPA development chỉ chạy trên iPad có UDID trong provisioning profile."
    echo "   Build khi iPad không cắm → cài được nhưng không mở / không xác minh được."
    exit 1
  fi
  echo "✓ iPad đang cắm: $(echo "$line" | sed 's/ (.*//')"
}

if ! command -v flutter >/dev/null || ! xcodebuild -version >/dev/null 2>&1; then
  echo "❌ Cần flutter + Xcode"
  exit 1
fi

ensure_signing_config
ensure_certificate
ensure_ipad_connected

if [[ -z "${API_BASE_URL:-}" ]]; then
  IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)"
  if [[ -n "$IP" ]]; then
    API_BASE_URL="http://${IP}:8000/api/v1"
  else
    echo "❌ Set API_BASE_URL=http://<IP-Mac>:8000/api/v1"
    exit 1
  fi
fi
echo "→ API_BASE_URL: $API_BASE_URL"

echo ""
echo "→ Refresh provisioning (đăng ký UDID iPad)..."
open "$ROOT/ios/Runner.xcworkspace" >/dev/null 2>&1 || true
# Build release for device — cập nhật profile có UDID iPad
flutter build ios --release --no-codesign --dart-define=API_BASE_URL="$API_BASE_URL" 2>/dev/null || true

flutter clean
flutter pub get
(cd ios && pod install)

echo ""
echo "→ Build RELEASE IPA..."
flutter build ipa \
  --release \
  --export-options-plist=ios/ExportOptions-development.plist \
  --dart-define=API_BASE_URL="$API_BASE_URL"

IPA="$(find "$ROOT/build/ios/ipa" -name '*.ipa' -print -quit 2>/dev/null || true)"
DESKTOP_IPA="$HOME/Desktop/Tuchi.ipa"

if [[ -n "$IPA" ]]; then
  cp "$IPA" "$DESKTOP_IPA"
  echo ""
  echo "✅ IPA: $DESKTOP_IPA"
  ls -lh "$DESKTOP_IPA"
  echo ""
  read -r -p "Cài ngay lên iPad qua USB? [Y/n] " INSTALL
  if [[ "${INSTALL:-Y}" != "n" && "${INSTALL:-Y}" != "N" ]]; then
    "$ROOT/scripts/install_ipad.sh" "$DESKTOP_IPA"
  fi
fi

cat <<'EOF'

── Nếu vẫn không mở được ──
1. iPad: Cài đặt > Quyền riêng tư > Chế độ nhà phát triển → BẬT → khởi động lại
2. Cài đặt chung > Quản lý VPN & Thiết bị > Tin cậy Apple ID
3. Xóa app Tuchi → build lại khi iPad cắm USB
4. Bật Wi‑Fi (Apple cần xác minh chứng chỉ online)

EOF
