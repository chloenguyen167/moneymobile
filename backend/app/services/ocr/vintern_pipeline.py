"""
Vintern-1B local inference via Transformers.

Note: pipeline("image-text-to-text") does NOT support Vintern (InternVLChatConfig).
Use AutoModel + model.chat() — same as official Vintern / Modal server.
"""

import io
import logging

logger = logging.getLogger(__name__)

_model = None
_tokenizer = None
_device: str | None = None
_dtype = None
_deps_checked = False
_deps_available = False


def is_vintern_pipeline_available() -> bool:
    """True when transformers + torch + torchvision are installed."""
    global _deps_checked, _deps_available
    if _deps_checked:
        return _deps_available

    _deps_checked = True
    try:
        import torch  # noqa: F401
        import torchvision  # noqa: F401
        import transformers

        version = transformers.__version__
        major = int(version.split(".")[0])
        if major >= 5:
            logger.warning(
                "transformers %s incompatible with Vintern — pin: pip install transformers==4.46.3",
                version,
            )
            _deps_available = False
            return False

        _deps_available = True
    except ImportError:
        _deps_available = False
        logger.debug("Vintern deps missing — pip install -r requirements-ocr.txt")
    return _deps_available


def _resolve_device_and_dtype():
    import torch

    if torch.cuda.is_available():
        return "cuda", torch.bfloat16
    if getattr(torch.backends, "mps", None) and torch.backends.mps.is_available():
        return "mps", torch.float16
    return "cpu", torch.float32


def _load_image_tensor(image_bytes: bytes):
    """Vintern dynamic_preprocess — ported from modal/vintern_serve.py."""
    import torch
    import torchvision.transforms as T
    from PIL import Image
    from torchvision.transforms.functional import InterpolationMode

    imagenet_mean = (0.485, 0.456, 0.406)
    imagenet_std = (0.229, 0.224, 0.225)

    def build_transform(input_size: int):
        return T.Compose(
            [
                T.Lambda(lambda img: img.convert("RGB") if img.mode != "RGB" else img),
                T.Resize((input_size, input_size), interpolation=InterpolationMode.BICUBIC),
                T.ToTensor(),
                T.Normalize(mean=imagenet_mean, std=imagenet_std),
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

    image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    transform = build_transform(input_size=448)
    images = dynamic_preprocess(image, image_size=448, use_thumbnail=True, max_num=4)
    return torch.stack([transform(im) for im in images])


def _get_model_and_tokenizer():
    global _model, _tokenizer, _device, _dtype
    if _model is not None and _tokenizer is not None:
        return _model, _tokenizer, _device, _dtype

    import torch
    from transformers import AutoModel, AutoTokenizer

    from app.config import settings

    _device, _dtype = _resolve_device_and_dtype()
    model_id = settings.vintern_model_id

    logger.info("Loading Vintern: model=%s device=%s dtype=%s", model_id, _device, _dtype)

    _tokenizer = AutoTokenizer.from_pretrained(model_id, trust_remote_code=True, use_fast=False)
    _model = (
        AutoModel.from_pretrained(
            model_id,
            torch_dtype=_dtype,
            low_cpu_mem_usage=True,
            trust_remote_code=True,
        )
        .eval()
        .to(_device)
    )
    return _model, _tokenizer, _device, _dtype


def run_vintern_pipeline(image_bytes: bytes, prompt: str) -> str:
    """
    Run Vintern model.chat() synchronously.
    Returns generated text (JSON or plain text).
    """
    import torch

    model, tokenizer, device, dtype = _get_model_and_tokenizer()
    pixel_values = _load_image_tensor(image_bytes).to(dtype).to(device)

    generation_config = {
        "max_new_tokens": 1024,
        "do_sample": False,
        "num_beams": 3,
        "repetition_penalty": 2.5,
    }

    with torch.inference_mode():
        response, _ = model.chat(
            tokenizer,
            pixel_values,
            prompt,
            generation_config,
            history=None,
            return_history=True,
        )

    return response
