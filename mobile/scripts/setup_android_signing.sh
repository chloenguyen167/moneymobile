#!/usr/bin/env bash
# Tạo Android upload keystore + key.properties cho release signing.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ANDROID_DIR="$ROOT/android"
KEYSTORE="$ANDROID_DIR/upload-keystore.jks"
PROPS="$ANDROID_DIR/key.properties"
ALIAS="${KEY_ALIAS:-tuchi}"

echo "══ Setup Android release signing ══"
echo ""

if [[ -f "$PROPS" && -f "$KEYSTORE" ]]; then
  echo "✓ Đã có keystore và key.properties:"
  echo "  $KEYSTORE"
  echo "  $PROPS"
  echo ""
  echo "Xóa chúng trước nếu muốn tạo lại."
  exit 0
fi

if ! command -v keytool >/dev/null 2>&1; then
  echo "❌ Cần keytool (JDK). Cài JDK 17+ rồi chạy lại."
  exit 1
fi

read -r -s -p "Store password: " STORE_PASS
echo ""
if [[ -z "$STORE_PASS" ]]; then
  echo "❌ Store password không được để trống"
  exit 1
fi

read -r -s -p "Key password [giống store]: " KEY_PASS
echo ""
KEY_PASS="${KEY_PASS:-$STORE_PASS}"

read -r -p "Key alias [$ALIAS]: " INPUT_ALIAS
ALIAS="${INPUT_ALIAS:-$ALIAS}"

CN="${KEY_CN:-Tuchi}"
OU="${KEY_OU:-Mobile}"
O="${KEY_O:-Tuchi}"
L="${KEY_L:-Ho Chi Minh}"
ST="${KEY_ST:-Ho Chi Minh}"
C="${KEY_C:-VN}"

if [[ ! -f "$KEYSTORE" ]]; then
  echo ""
  echo "→ Tạo keystore: $KEYSTORE"
  keytool -genkeypair \
    -v \
    -keystore "$KEYSTORE" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -alias "$ALIAS" \
    -storepass "$STORE_PASS" \
    -keypass "$KEY_PASS" \
    -dname "CN=$CN, OU=$OU, O=$O, L=$L, ST=$ST, C=$C"
  echo "✓ Đã tạo keystore"
else
  echo "✓ Keystore đã tồn tại — chỉ ghi key.properties"
fi

cat > "$PROPS" <<EOF
storePassword=$STORE_PASS
keyPassword=$KEY_PASS
keyAlias=$ALIAS
storeFile=upload-keystore.jks
EOF

echo ""
echo "✓ Đã tạo: android/key.properties"
echo "  keyAlias = $ALIAS"
echo "  storeFile = upload-keystore.jks"
echo ""
echo "⚠ Không commit keystore / key.properties (đã gitignore)."
echo "→ Release build sẽ dùng signing config này khi file tồn tại."
