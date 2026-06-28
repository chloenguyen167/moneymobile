#!/usr/bin/env bash
# Cài Tuchi.ipa lên iPad qua USB (tin cậy hơn Apple Configurator cho dev signing).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPA="${1:-$HOME/Desktop/Tuchi.ipa}"

if [[ ! -f "$IPA" ]]; then
  echo "❌ Không tìm thấy IPA: $IPA"
  echo "   Chạy trước: ./scripts/build_ipa_ac.sh"
  exit 1
fi

echo "→ Tìm iPad đang cắm USB..."
# Format: "iPad (18.x) (00008020-001A...) (Connected)"
DEVICE_LINE="$(xcrun xctrace list devices 2>/dev/null | grep -iE 'iPad.*\([0-9A-F-]{36}\)' | grep -vi Simulator | head -1 || true)"

if [[ -z "$DEVICE_LINE" ]]; then
  echo "❌ Không thấy iPad. Cắm USB, unlock, Trust This Computer."
  exit 1
fi

UDID="$(echo "$DEVICE_LINE" | sed -n 's/.*(\([0-9A-F-]\{36\}\)).*/\1/p' | tail -1)"
echo "✓ iPad: $DEVICE_LINE"
echo "  UDID: $UDID"
echo ""

echo "→ Cài $IPA ..."
if xcrun devicectl device install app --device "$UDID" "$IPA" 2>/dev/null; then
  echo "✓ Cài xong qua devicectl"
else
  echo "⚠ devicectl thất bại — thử ideviceinstaller..."
  if command -v ideviceinstaller >/dev/null; then
    ideviceinstaller -u "$UDID" -i "$IPA"
  else
    echo "❌ Cài thủ công: Apple Configurator > Add > Apps > $IPA"
    exit 1
  fi
fi

cat <<'EOF'

── Trên iPad (BẮT BUỘC, theo thứ tự) ──

1. Chế độ nhà phát triển (iOS 16+):
   Cài đặt > Quyền riêng tư & Bảo mật > Chế độ nhà phát triển > BẬT
   → Khởi động lại iPad → xác nhận Bật

2. Tin cậy developer:
   Cài đặt > Cài đặt chung > Quản lý VPN & Thiết bị
   → mục "ỨNG DỤNG DEVELOPER" > chọn Apple ID > Tin cậy

3. Cần Wi‑Fi + đúng giờ để Apple xác minh chứng chỉ lần đầu

4. Xóa app cũ nếu vẫn lỗi, build lại IPA khi iPad đang cắm USB:
   ./scripts/build_ipa_ac.sh && ./scripts/install_ipad.sh

EOF
