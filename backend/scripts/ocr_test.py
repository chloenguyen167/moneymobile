#!/usr/bin/env python3
"""
OCR test CLI — chạy OCR trên ảnh hóa đơn tiếng Việt mà không cần mobile app hay DB.

Usage:
  cd backend
  python scripts/ocr_test.py --all
  python scripts/ocr_test.py tests/ocr/images/hoa_don_1.jpg
  python scripts/ocr_test.py --all --track smart
  python scripts/ocr_test.py --all --track local   # cần pip install -r requirements-ocr.txt
  python scripts/ocr_test.py --all --compare       # so với expected/*.json nếu có
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from datetime import date
from pathlib import Path

# Allow running from backend/ without installing package
BACKEND_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_ROOT))

from app.config import settings  # noqa: E402
from app.services.ocr.local_ocr import is_local_ocr_available  # noqa: E402
from app.services.ocr.runner import run_ocr_standalone  # noqa: E402
from app.services.ocr.vintern import is_vintern_available  # noqa: E402
from app.services.ocr.vintern_pipeline import is_vintern_pipeline_available  # noqa: E402

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
DEFAULT_IMAGES_DIR = BACKEND_ROOT / "tests" / "ocr" / "images"
DEFAULT_OUTPUT_DIR = BACKEND_ROOT / "tests" / "ocr" / "output"
DEFAULT_EXPECTED_DIR = BACKEND_ROOT / "tests" / "ocr" / "expected"


def _json_default(obj):
    if isinstance(obj, date):
        return obj.isoformat()
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")


def _result_to_dict(result) -> dict:
    return json.loads(result.model_dump_json())


def _load_expected(path: Path) -> dict | None:
    expected_path = DEFAULT_EXPECTED_DIR / f"{path.stem}.json"
    if not expected_path.exists():
        return None
    return json.loads(expected_path.read_text(encoding="utf-8"))


def _compare_fields(result: dict, expected: dict) -> list[str]:
    diffs: list[str] = []
    for key in ("merchant", "total_amount", "transaction_date"):
        exp = expected.get(key)
        got = result.get(key)
        if exp is None:
            continue
        if key == "total_amount" and exp and got:
            if abs(float(got) - float(exp)) > max(float(exp) * 0.02, 1000):
                diffs.append(f"{key}: expected {exp}, got {got}")
        elif str(exp) != str(got):
            diffs.append(f"{key}: expected {exp}, got {got}")
    return diffs


def _print_result(name: str, result: dict, *, compare: bool = False, source: Path | None = None) -> bool:
    ok = True
    print(f"\n{'=' * 60}")
    print(f"📄 {name}")
    print(f"   track: {result.get('ocr_track_used')} | confidence: {result.get('ocr_confidence')}")
    print(f"   merchant: {result.get('merchant')}")
    print(f"   total:    {result.get('total_amount')}")
    print(f"   date:     {result.get('transaction_date')}")
    items = result.get("items") or []
    if items:
        print(f"   items ({len(items)}):")
        for item in items[:5]:
            print(f"     - {item.get('name')}: {item.get('price')} x{item.get('qty', 1)}")
        if len(items) > 5:
            print(f"     ... +{len(items) - 5} more")
    if result.get("raw_text"):
        preview = result["raw_text"][:200].replace("\n", " | ")
        print(f"   raw_text: {preview}{'...' if len(result['raw_text']) > 200 else ''}")

    if compare and source:
        expected = _load_expected(source)
        if expected:
            diffs = _compare_fields(result, expected)
            if diffs:
                ok = False
                print("   ❌ MISMATCH:")
                for d in diffs:
                    print(f"      - {d}")
            else:
                print("   ✅ Khớp expected")
        else:
            print(f"   ⚠️  Chưa có expected/{source.stem}.json")

    return ok


def _list_images(images_dir: Path) -> list[Path]:
    if not images_dir.exists():
        return []
    return sorted(
        p for p in images_dir.iterdir()
        if p.is_file() and p.suffix.lower() in IMAGE_EXTS and not p.name.startswith(".")
    )


def _print_env_status():
    import transformers

    tf_version = transformers.__version__
    tf_ok = int(tf_version.split(".")[0]) < 5
    print("OCR engines:")
    print(f"  EasyOCR (fast):    {'✅' if is_local_ocr_available() else '❌  pip install -r requirements-ocr.txt'}")
    if is_vintern_pipeline_available():
        print(f"  Vintern (local):   ✅ {settings.vintern_model_id} (transformers {tf_version})")
    elif not tf_ok:
        print(f"  Vintern (local):   ❌  transformers {tf_version} — cần pip install transformers==4.46.3")
    else:
        print("  Vintern (local):   ❌  pip install -r requirements-ocr.txt")
    if settings.vintern_api_url:
        print(f"  Vintern (HTTP):    ✅ {settings.vintern_api_url}")
    print(f"  Gemini:            {'✅' if settings.gemini_api_key else '❌  set GEMINI_API_KEY'}")
    print(f"  OpenAI:            {'✅' if settings.openai_api_key else '❌  set OPENAI_API_KEY'}")


async def _process_image(
    path: Path,
    *,
    track: str | None,
    skip_preprocess: bool,
    compare: bool,
    save_output: bool,
) -> bool:
    image_bytes = path.read_bytes()
    result = await run_ocr_standalone(
        image_bytes,
        skip_preprocess=skip_preprocess,
        force_track=track,
    )
    data = _result_to_dict(result)

    if save_output:
        DEFAULT_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        out_path = DEFAULT_OUTPUT_DIR / f"{path.stem}.json"
        out_path.write_text(json.dumps(data, ensure_ascii=False, indent=2, default=_json_default), encoding="utf-8")
        print(f"   💾 Saved → {out_path.relative_to(BACKEND_ROOT)}")

    return _print_result(path.name, data, compare=compare, source=path)


async def main() -> int:
    parser = argparse.ArgumentParser(description="Test OCR trên ảnh hóa đơn tiếng Việt")
    parser.add_argument("image", nargs="?", help="Đường dẫn ảnh (hoặc dùng --all)")
    parser.add_argument("--all", action="store_true", help=f"Chạy tất cả ảnh trong {DEFAULT_IMAGES_DIR.relative_to(BACKEND_ROOT)}")
    parser.add_argument(
        "--track",
        choices=["auto", "fast", "smart", "local", "vintern", "gemini", "openai"],
        default="auto",
        help="Buộc track OCR (mặc định: auto = CR-OCR routing)",
    )
    parser.add_argument("--no-preprocess", action="store_true", help="Bỏ qua tiền xử lý ảnh OpenCV")
    parser.add_argument("--compare", action="store_true", help="So sánh với tests/ocr/expected/*.json")
    parser.add_argument("--no-save", action="store_true", help="Không lưu kết quả vào tests/ocr/output/")
    parser.add_argument("--images-dir", type=Path, default=DEFAULT_IMAGES_DIR, help="Thư mục chứa ảnh test")
    args = parser.parse_args()

    _print_env_status()

    if args.all:
        images = _list_images(args.images_dir)
        if not images:
            print(f"\n⚠️  Không có ảnh trong {args.images_dir}")
            print("   Đặt ảnh hóa đơn .jpg/.png vào thư mục đó rồi chạy lại.")
            return 1
    elif args.image:
        images = [Path(args.image)]
        if not images[0].exists():
            print(f"❌ Không tìm thấy file: {args.image}")
            return 1
    else:
        parser.print_help()
        return 1

    track = None if args.track == "auto" else args.track
    all_ok = True

    print(f"\nXử lý {len(images)} ảnh (track={args.track})...")
    for img in images:
        ok = await _process_image(
            img,
            track=track,
            skip_preprocess=args.no_preprocess,
            compare=args.compare,
            save_output=not args.no_save,
        )
        all_ok = all_ok and ok

    print(f"\n{'=' * 60}")
    print("✅ Hoàn tất" if all_ok else "⚠️  Có kết quả chưa khớp expected hoặc thiếu dữ liệu")
    return 0 if all_ok else 2


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
