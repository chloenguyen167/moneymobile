"""
Deploy Vintern-1B-v3.5 on Modal — OpenAI-compatible /v1/chat/completions for Tuchi OCR.

  cd backend/modal && modal deploy vintern_serve.py

.env:
  VINTERN_API_URL=https://<workspace>--tuchi-vintern-serve.modal.run/v1
  VINTERN_MODEL_NAME=vintern-1b
"""

from __future__ import annotations

import modal

MODEL_ID = "5CD-AI/Vintern-1B-v3_5"
SERVED_MODEL = "vintern-1b"
MINUTES = 60

vintern_image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("libgl1", "libglib2.0-0", "libsm6", "libxext6", "libxrender1")
    .pip_install(
        "torch==2.4.1",
        "torchvision==0.19.1",
        "transformers==4.46.3",
        "accelerate==1.1.1",
        "einops",
        "timm",
        "pillow",
        "fastapi[standard]==0.115.6",
        "huggingface_hub[hf_transfer]==0.26.2",
    )
    .env({"HF_HUB_ENABLE_HF_TRANSFER": "1"})
)

app = modal.App("tuchi-vintern", image=vintern_image)


def _load_image_tensor(image_path: str):
    import torch
    import torchvision.transforms as T
    from PIL import Image
    from torchvision.transforms.functional import InterpolationMode

    IMAGENET_MEAN = (0.485, 0.456, 0.406)
    IMAGENET_STD = (0.229, 0.224, 0.225)

    def build_transform(input_size):
        return T.Compose(
            [
                T.Lambda(lambda img: img.convert("RGB") if img.mode != "RGB" else img),
                T.Resize((input_size, input_size), interpolation=InterpolationMode.BICUBIC),
                T.ToTensor(),
                T.Normalize(mean=IMAGENET_MEAN, std=IMAGENET_STD),
            ]
        )

    def find_closest_aspect_ratio(aspect_ratio, target_ratios, width, height, image_size):
        best_ratio_diff = float("inf")
        best_ratio = (1, 1)
        area = width * height
        for ratio in target_ratios:
            target_aspect_ratio = ratio[0] / ratio[1]
            ratio_diff = abs(aspect_ratio - target_aspect_ratio)
            if ratio_diff < best_ratio_diff:
                best_ratio_diff = ratio_diff
                best_ratio = ratio
            elif ratio_diff == best_ratio_diff:
                if area > 0.5 * image_size * image_size * ratio[0] * ratio[1]:
                    best_ratio = ratio
        return best_ratio

    def dynamic_preprocess(image, min_num=1, max_num=12, image_size=448, use_thumbnail=False):
        orig_width, orig_height = image.size
        aspect_ratio = orig_width / orig_height
        target_ratios = sorted(
            {
                (i, j)
                for n in range(min_num, max_num + 1)
                for i in range(1, n + 1)
                for j in range(1, n + 1)
                if min_num <= i * j <= max_num
            },
            key=lambda x: x[0] * x[1],
        )
        target_aspect_ratio = find_closest_aspect_ratio(
            aspect_ratio, target_ratios, orig_width, orig_height, image_size
        )
        target_width = image_size * target_aspect_ratio[0]
        target_height = image_size * target_aspect_ratio[1]
        blocks = target_aspect_ratio[0] * target_aspect_ratio[1]
        resized_img = image.resize((target_width, target_height))
        processed_images = []
        for i in range(blocks):
            box = (
                (i % (target_width // image_size)) * image_size,
                (i // (target_width // image_size)) * image_size,
                ((i % (target_width // image_size)) + 1) * image_size,
                ((i // (target_width // image_size)) + 1) * image_size,
            )
            processed_images.append(resized_img.crop(box))
        if use_thumbnail and len(processed_images) != 1:
            processed_images.append(image.resize((image_size, image_size)))
        return processed_images

    image = Image.open(image_path).convert("RGB")
    transform = build_transform(input_size=448)
    images = dynamic_preprocess(image, image_size=448, use_thumbnail=True, max_num=6)
    return torch.stack([transform(im) for im in images])


@app.function(
    gpu="T4",
    timeout=30 * MINUTES,
    scaledown_window=10 * MINUTES,
)
@modal.concurrent(max_inputs=4)
@modal.asgi_app()
def serve():
    import base64
    import io
    import tempfile
    import uuid

    import torch
    from fastapi import FastAPI
    from fastapi.responses import JSONResponse
    from PIL import Image
    from transformers import AutoModel, AutoTokenizer

    model = (
        AutoModel.from_pretrained(
            MODEL_ID,
            torch_dtype=torch.bfloat16,
            low_cpu_mem_usage=True,
            trust_remote_code=True,
        )
        .eval()
        .cuda()
    )
    tokenizer = AutoTokenizer.from_pretrained(MODEL_ID, trust_remote_code=True, use_fast=False)

    web = FastAPI(title="Tuchi Vintern OCR")

    @web.get("/health")
    def health():
        return {"status": "ok", "model": MODEL_ID}

    @web.post("/v1/chat/completions")
    def chat_completions(body: dict):
        prompt_parts: list[str] = []
        image_b64: str | None = None

        for msg in body.get("messages", []):
            content = msg.get("content")
            if isinstance(content, str):
                prompt_parts.append(content)
            elif isinstance(content, list):
                for part in content:
                    if part.get("type") == "text":
                        prompt_parts.append(part.get("text", ""))
                    elif part.get("type") == "image_url":
                        url = part.get("image_url", {}).get("url", "")
                        if url.startswith("data:") and "base64," in url:
                            image_b64 = url.split("base64,", 1)[1]

        if not image_b64:
            return JSONResponse(
                status_code=400,
                content={"error": "image_url required in messages.content"},
            )

        question = "\n\n".join(p for p in prompt_parts if p).strip()
        if not question:
            question = (
                "Bạn là hệ thống OCR hóa đơn Việt Nam. Chỉ đọc tờ hóa đơn giấy trong ảnh. "
                "Trả JSON: merchant, items[{name,price,qty}], total_amount, transaction_date, confidence."
            )
        pil = Image.open(io.BytesIO(base64.b64decode(image_b64))).convert("RGB")

        with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as tmp:
            pil.save(tmp.name, format="JPEG")
            tmp_path = tmp.name

        pixel_values = _load_image_tensor(tmp_path).to(torch.bfloat16).cuda()
        generation_config = dict(
            max_new_tokens=body.get("max_tokens", 1024),
            do_sample=False,
            num_beams=3,
            repetition_penalty=2.5,
        )
        response, _ = model.chat(
            tokenizer,
            pixel_values,
            question,
            generation_config,
            history=None,
            return_history=True,
        )

        return {
            "id": f"chatcmpl-{uuid.uuid4().hex[:12]}",
            "object": "chat.completion",
            "model": body.get("model", SERVED_MODEL),
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": response},
                    "finish_reason": "stop",
                }
            ],
        }

    return web


@app.local_entrypoint()
def main():
    print("Run: modal deploy vintern_serve.py")
