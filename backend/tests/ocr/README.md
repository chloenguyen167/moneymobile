# Test OCR hóa đơn tiếng Việt

Thư mục này dùng để test OCR **độc lập**, không cần mobile app hay database.

## Cấu trúc

```
tests/ocr/
├── images/      ← đặt ảnh hóa đơn vào đây
├── expected/    ← (tuỳ chọn) JSON kỳ vọng để so sánh
└── output/      ← kết quả OCR tự động lưu
```

## Chuẩn bị

```bash
cd backend
pip install -r requirements.txt
pip install -r requirements-ocr.txt   # transformers, torch, pillow, easyocr
```

Lần đầu chạy Vintern sẽ tải model **~3.7GB** từ HuggingFace.

## Chạy test

```bash
cd backend

# Vintern — Transformers pipeline (khuyến nghị)
python3 scripts/ocr_test.py tests/ocr/images/hoa_don_share_tea.jpg --track vintern

# Tất cả ảnh, auto routing
python3 scripts/ocr_test.py --all

# Các track khác
python3 scripts/ocr_test.py --all --track smart     # Vintern → Gemini → OpenAI
python3 scripts/ocr_test.py --all --track local     # EasyOCR + regex
python3 scripts/ocr_test.py --all --compare         # so với expected/*.json
```

## Vintern — AutoModel.chat()

`pipeline("image-text-to-text")` **không hỗ trợ** Vintern (`InternVLChatConfig`).
Tuchi dùng `AutoModel` + `model.chat()` — cách chính thức của Vintern:

```python
from transformers import AutoModel, AutoTokenizer

model = AutoModel.from_pretrained(
    "5CD-AI/Vintern-1B-v3_5", trust_remote_code=True
).eval()
tokenizer = AutoTokenizer.from_pretrained(
    "5CD-AI/Vintern-1B-v3_5", trust_remote_code=True
)
response, _ = model.chat(tokenizer, pixel_values, prompt, generation_config)
```

Code: `app/services/ocr/vintern_pipeline.py`

## Expected JSON (tuỳ chọn)

```json
{
  "merchant": "Sharetea",
  "total_amount": 69300,
  "transaction_date": "2017-03-29"
}
```
