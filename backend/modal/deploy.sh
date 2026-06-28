#!/usr/bin/env bash
# Deploy Vintern-1B on Modal and print env vars for Tuchi backend.
set -euo pipefail
cd "$(dirname "$0")"

echo "==> Deploying Vintern on Modal (first run downloads ~3.7GB model, ~10-20 min)..."
modal deploy vintern_serve.py

echo ""
echo "==> Fetch deployed web URL..."
URL=$(modal app list 2>/dev/null | awk '/tuchi-vintern/ {found=1} found && /web/ {print; exit}' || true)

# Modal prints URL on deploy; also try app show
if [[ -z "${URL:-}" ]]; then
  modal app show tuchi-vintern 2>/dev/null || true
fi

echo ""
echo "=== Cấu hình .env (thay URL bên dưới nếu khác) ==="
echo "VINTERN_API_URL=https://pio711galaxy--tuchi-vintern-vinternserver-web.modal.run/v1"
echo "VINTERN_MODEL_NAME=vintern-1b"
echo ""
echo "Sau đó: docker compose up -d api"
