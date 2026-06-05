"""
OCR orchestration for Indian number plates.
Supports PARSeq (primary) and PaddleOCR (secondary).
Multi-engine consensus: runs both engines and picks the best validated result.
"""

import logging
import re
from pathlib import Path

import numpy as np

from .preprocess import preprocess_plate
from .validators import validate_and_correct, PlateValidationResult

logger = logging.getLogger(__name__)


class ParseqOCR:
    """PARSeq scene text recognition — optimized for short alphanumeric strings."""

    def __init__(self):
        self._model = None
        self._transform = None
        self._device = None

    def load(self) -> bool:
        try:
            import ssl
            import sys

            import torch
            from torchvision import transforms as T

            ssl._create_default_https_context = ssl._create_unverified_context

            self._device = "mps" if torch.backends.mps.is_available() else "cpu"

            # Load base model architecture
            local_parseq = Path(__file__).parent.parent / "models" / "parseq"
            if local_parseq.exists() and (local_parseq / "hubconf.py").exists():
                sys.path.insert(0, str(local_parseq))
                self._model = torch.hub.load(
                    str(local_parseq), "parseq", pretrained=True,
                    source="local", trust_repo=True
                )
            else:
                self._model = torch.hub.load(
                    "baudm/parseq", "parseq", pretrained=True, trust_repo=True
                )

            # Load fine-tuned weights if available (overrides pretrained)
            finetuned_path = Path(__file__).parent.parent / "models" / "parseq" / "parseq_indian.pt"
            if finetuned_path.exists():
                state_dict = torch.load(finetuned_path, map_location=self._device, weights_only=True)
                self._model.load_state_dict(state_dict)
                logger.info(f"PARSeq: loaded fine-tuned weights from {finetuned_path.name}")
            else:
                logger.info("PARSeq: using base pretrained weights (no fine-tuned model found)")

            self._model = self._model.eval().to(self._device)

            img_size = self._model.hparams.img_size  # [32, 128]
            self._transform = T.Compose([
                T.Resize(img_size, T.InterpolationMode.BICUBIC),
                T.ToTensor(),
                T.Normalize(0.5, 0.5),
            ])

            logger.info(f"PARSeq loaded on {self._device}")
            return True
        except Exception as e:
            logger.warning(f"PARSeq load failed: {e}")
            return False

    @property
    def is_loaded(self) -> bool:
        return self._model is not None

    def recognize(self, crop: np.ndarray) -> tuple[str, float]:
        """Recognize text in a plate crop. Returns (text, confidence)."""
        if self._model is None:
            return "", 0.0

        import torch
        from PIL import Image

        try:
            pil_img = Image.fromarray(crop).convert("RGB")
            tensor = self._transform(pil_img).unsqueeze(0).to(self._device)

            with torch.no_grad():
                logits = self._model(tensor)

            probs = logits.softmax(-1)
            preds, pred_scores = self._model.tokenizer.decode(probs)

            text = preds[0].upper().strip()
            conf = float(pred_scores[0].mean()) if hasattr(pred_scores[0], "mean") else float(pred_scores[0])
            return text, conf
        except Exception as e:
            logger.debug(f"PARSeq inference error: {e}")
            return "", 0.0

    def recognize_double_line(self, crop: np.ndarray) -> tuple[str, float]:
        """Split double-line plate at midpoint, recognize each half, concatenate."""
        h, w = crop.shape[:2]
        if h < 10:
            return self.recognize(crop)

        # Try single-pass first
        full_text, full_conf = self.recognize(crop)

        mid = h // 2
        top_half = crop[:mid, :]
        bottom_half = crop[mid:, :]

        top_text, top_conf = self.recognize(top_half)
        bottom_text, bottom_conf = self.recognize(bottom_half)

        if not top_text and not bottom_text:
            return full_text, full_conf

        merged = f"{top_text}{bottom_text}".strip()
        avg_conf = (top_conf + bottom_conf) / 2 if (top_text and bottom_text) else max(top_conf, bottom_conf)

        # If merged is too long, prefer single-pass or best half
        if len(merged.replace(" ", "")) > 13:
            if full_text and len(full_text.replace(" ", "")) <= 13:
                return full_text, full_conf
            if len(top_text) >= len(bottom_text) and top_text:
                return top_text, top_conf
            elif bottom_text:
                return bottom_text, bottom_conf
            return full_text, full_conf

        # Pick the result that validates better
        merged_result = validate_and_correct(merged)
        full_result = validate_and_correct(full_text) if full_text else None

        if full_result and full_result.is_valid_format and not merged_result.is_valid_format:
            return full_text, full_conf
        if merged_result.is_valid_format and (not full_result or not full_result.is_valid_format):
            return merged, avg_conf
        # Both valid or neither — prefer higher confidence
        if full_conf > avg_conf and full_text:
            return full_text, full_conf
        return merged, avg_conf


class PaddleOCREngine:
    """PaddleOCR wrapper — secondary OCR engine for consensus."""

    def __init__(self):
        self._engine = None

    def load(self) -> bool:
        try:
            from paddleocr import PaddleOCR
            self._engine = PaddleOCR(use_textline_orientation=True, lang="en")
            logger.info("PaddleOCR loaded")
            return True
        except (ImportError, Exception) as e:
            logger.warning(f"PaddleOCR load failed: {e}")
            return False

    @property
    def is_loaded(self) -> bool:
        return self._engine is not None

    def recognize(self, crop: np.ndarray) -> tuple[str, float]:
        """Run PaddleOCR and return merged text + confidence."""
        if self._engine is None:
            return "", 0.0

        try:
            ocr_results = self._engine.ocr(crop)
        except Exception:
            return "", 0.0

        lines = _parse_paddle_results(ocr_results)
        if not lines:
            return "", 0.0

        sorted_lines = sorted(lines, key=lambda l: l["x_center"])
        merged = " ".join(l["text"] for l in sorted_lines)
        avg_conf = sum(l["confidence"] for l in lines) / len(lines)
        return merged, avg_conf

    def recognize_double_line(self, crop: np.ndarray) -> tuple[str, float]:
        """PaddleOCR handles multi-line natively via bbox positions."""
        if self._engine is None:
            return "", 0.0

        try:
            ocr_results = self._engine.ocr(crop)
        except Exception:
            return "", 0.0

        lines = _parse_paddle_results(ocr_results)
        if not lines:
            return "", 0.0

        text, conf = _merge_double_line(lines)
        return text, conf


def _parse_paddle_results(ocr_results) -> list[dict]:
    """Parse PaddleOCR v4/v5 results into structured lines."""
    lines = []
    if not ocr_results:
        return lines

    # PaddleOCR v5 format: list of dicts with rec_texts, rec_scores, dt_polys/rec_polys
    if isinstance(ocr_results, list) and ocr_results and isinstance(ocr_results[0], dict):
        result = ocr_results[0]
        texts = result.get("rec_texts", [])
        scores = result.get("rec_scores", [])
        polys = result.get("rec_polys", result.get("dt_polys", []))

        for i, text in enumerate(texts):
            if not str(text).strip():
                continue
            conf = float(scores[i]) if i < len(scores) else 0.0
            bbox_points = polys[i] if i < len(polys) else None

            y_center = 0.0
            x_center = 0.0
            if bbox_points is not None:
                try:
                    pts = np.array(bbox_points)
                    if pts.ndim == 2 and pts.shape[1] >= 2:
                        y_center = float(pts[:, 1].mean())
                        x_center = float(pts[:, 0].mean())
                except (TypeError, IndexError, ValueError):
                    pass

            lines.append({
                "text": str(text).strip(),
                "confidence": conf,
                "y_center": y_center,
                "x_center": x_center,
            })
        return lines

    # PaddleOCR v4 format: [[[bbox_points], (text, conf)], ...]
    results = ocr_results[0] if ocr_results else None
    if not results:
        return lines

    for line in results:
        try:
            if isinstance(line, (list, tuple)) and len(line) == 2:
                bbox_points = line[0]
                text_part = line[1]
                text = ""
                conf = 0.0
                if isinstance(text_part, (list, tuple)) and len(text_part) >= 2:
                    text = str(text_part[0])
                    conf = float(text_part[1])
                elif isinstance(text_part, dict):
                    text = str(text_part.get("text", ""))
                    conf = float(text_part.get("score", 0))

                if not text.strip():
                    continue

                y_center = 0.0
                x_center = 0.0
                if bbox_points and len(bbox_points) >= 4:
                    ys = [p[1] for p in bbox_points]
                    xs = [p[0] for p in bbox_points]
                    y_center = sum(ys) / len(ys)
                    x_center = sum(xs) / len(xs)

                lines.append({
                    "text": text.strip(),
                    "confidence": conf,
                    "y_center": y_center,
                    "x_center": x_center,
                })
        except (TypeError, ValueError, IndexError):
            continue

    return lines


def _merge_double_line(lines: list[dict]) -> tuple[str, float]:
    """Merge OCR lines from a double-line plate into single text."""
    if not lines:
        return "", 0.0
    if len(lines) == 1:
        return lines[0]["text"], lines[0]["confidence"]

    sorted_lines = sorted(lines, key=lambda l: l["y_center"])
    total_height_range = sorted_lines[-1]["y_center"] - sorted_lines[0]["y_center"]

    if total_height_range < 5:
        sorted_lr = sorted(lines, key=lambda l: l["x_center"])
        merged = " ".join(l["text"] for l in sorted_lr)
        avg_conf = sum(l["confidence"] for l in lines) / len(lines)
        return merged, avg_conf

    mid_y = sorted_lines[0]["y_center"] + total_height_range / 2
    top_row = sorted([l for l in sorted_lines if l["y_center"] < mid_y], key=lambda l: l["x_center"])
    bottom_row = sorted([l for l in sorted_lines if l["y_center"] >= mid_y], key=lambda l: l["x_center"])

    top_text = " ".join(l["text"] for l in top_row)
    bottom_text = " ".join(l["text"] for l in bottom_row)
    merged = f"{top_text} {bottom_text}".strip()

    all_confs = [l["confidence"] for l in lines]
    avg_conf = sum(all_confs) / len(all_confs)
    return merged, avg_conf


def _is_double_line(crop: np.ndarray) -> bool:
    h, w = crop.shape[:2]
    if h == 0:
        return False
    return (w / h) < 3.0


def _run_single_engine(ocr_engine, crop: np.ndarray, is_double: bool, variants: list[np.ndarray]) -> tuple[str, float, str, bool]:
    """Run one OCR engine across all variants. Returns (text, conf, type, is_valid)."""
    best_text = ""
    best_conf = 0.0
    best_type = "unknown"
    best_valid = False

    for variant in variants:
        raw_text = ""
        avg_conf = 0.0

        if isinstance(ocr_engine, (ParseqOCR, PaddleOCREngine)):
            if is_double:
                raw_text, avg_conf = ocr_engine.recognize_double_line(variant)
            else:
                raw_text, avg_conf = ocr_engine.recognize(variant)
        else:
            try:
                ocr_results = ocr_engine.ocr(variant)
                lines = _parse_paddle_results(ocr_results)
                if lines:
                    if is_double:
                        raw_text, avg_conf = _merge_double_line(lines)
                    else:
                        sorted_lines = sorted(lines, key=lambda l: l["x_center"])
                        raw_text = " ".join(l["text"] for l in sorted_lines)
                        avg_conf = sum(l["confidence"] for l in lines) / len(lines)
            except Exception:
                continue

        if not raw_text:
            continue

        result = validate_and_correct(raw_text)
        effective_conf = avg_conf + result.confidence_boost

        if result.is_valid_format and not best_valid:
            best_text = result.text
            best_conf = effective_conf
            best_type = result.plate_type
            best_valid = True
        elif result.is_valid_format and effective_conf > best_conf:
            best_text = result.text
            best_conf = effective_conf
            best_type = result.plate_type
        elif not best_valid and effective_conf > best_conf:
            best_text = result.text
            best_conf = effective_conf
            best_type = result.plate_type

    return best_text, best_conf, best_type, best_valid


def run_ocr_on_crop(
    ocr_engine,
    crop: np.ndarray,
    max_variants: int = 3,
    secondary_engine=None,
) -> tuple[str, float, str]:
    """
    Run full OCR pipeline on a plate crop with multi-engine consensus.

    If secondary_engine is provided, runs both engines and picks the best
    validated result — if they agree, confidence is boosted.

    Returns: (plate_text, confidence, plate_type)
    """
    if crop.size == 0 or ocr_engine is None:
        return "", 0.0, "unknown"

    is_double = _is_double_line(crop)
    variants = preprocess_plate(crop)
    if not variants:
        variants = [crop]
    variants = variants[:max_variants]

    # Run primary engine
    pri_text, pri_conf, pri_type, pri_valid = _run_single_engine(
        ocr_engine, crop, is_double, variants
    )

    # No secondary engine — return primary result
    if secondary_engine is None or not getattr(secondary_engine, "is_loaded", False):
        return pri_text, min(pri_conf, 1.0), pri_type

    # Run secondary engine (only on best variant — CLAHE enhanced)
    sec_variants = variants[:1]  # Just CLAHE for speed
    sec_text, sec_conf, sec_type, sec_valid = _run_single_engine(
        secondary_engine, crop, is_double, sec_variants
    )

    # Multi-engine consensus logic
    if pri_valid and sec_valid:
        pri_cleaned = re.sub(r"[^A-Z0-9]", "", pri_text)
        sec_cleaned = re.sub(r"[^A-Z0-9]", "", sec_text)
        if pri_cleaned == sec_cleaned:
            # Both engines agree — high confidence
            return pri_text, min(pri_conf + 0.1, 1.0), pri_type
        else:
            # Disagree — pick higher confidence valid result
            if pri_conf >= sec_conf:
                return pri_text, min(pri_conf, 1.0), pri_type
            return sec_text, min(sec_conf, 1.0), sec_type

    if pri_valid:
        return pri_text, min(pri_conf, 1.0), pri_type
    if sec_valid:
        return sec_text, min(sec_conf, 1.0), sec_type

    # Neither valid — pick higher confidence
    if pri_conf >= sec_conf:
        return pri_text, min(pri_conf, 1.0), pri_type
    return sec_text, min(sec_conf, 1.0), sec_type
