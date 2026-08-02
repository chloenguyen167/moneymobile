__all__ = ["process_payment_screenshot"]


def __getattr__(name: str):
    if name == "process_payment_screenshot":
        from app.services.payment_screenshot.pipeline import process_payment_screenshot

        return process_payment_screenshot
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
