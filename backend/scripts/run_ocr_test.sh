#!/usr/bin/env bash
# Wrapper: chạy OCR test từ thư mục backend
set -euo pipefail
cd "$(dirname "$0")/.."
exec python scripts/ocr_test.py "$@"
