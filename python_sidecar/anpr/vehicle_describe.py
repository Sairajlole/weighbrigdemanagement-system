"""
Vehicle brand/model/color identification.

Uses SigLIP zero-shot classification (no training needed) as primary recognizer.
Falls back to DINOv2 linear probe when trained model is available.
Color detection via HSV histogram (no ML).

Auto-captures vehicle crops for future labeling/training.
"""

import json
import logging
import time
import uuid
from pathlib import Path

import cv2
import numpy as np

logger = logging.getLogger(__name__)

CLASSES_FILE = Path(__file__).parent / "vehicle_classes.json"
CAPTURES_DIR = Path.home() / ".weighbridge" / "vehicle_captures"
LABELS_FILE = CAPTURES_DIR / "labels.jsonl"
DINOV2_MODEL_PATH = Path(__file__).parent.parent / "models" / "vehicle" / "dinov2_head.pt"

# HSV hue ranges → color names
COLOR_RANGES: list[tuple[tuple[int, int], tuple[int, int], str]] = [
    ((0, 10), (50, 255), "Red"),
    ((170, 180), (50, 255), "Red"),
    ((10, 25), (50, 255), "Orange"),
    ((25, 35), (50, 255), "Yellow"),
    ((35, 80), (50, 255), "Green"),
    ((80, 130), (50, 255), "Blue"),
    ((130, 170), (50, 255), "Purple"),
]
ACHROMATIC_THRESHOLD = 50


def _detect_color(crop: np.ndarray) -> str:
    """Detect dominant color of a vehicle crop using HSV histogram."""
    if crop.size == 0:
        return "Unknown"

    hsv = cv2.cvtColor(crop, cv2.COLOR_RGB2HSV)
    h, w = hsv.shape[:2]

    y_start = int(h * 0.2)
    y_end = int(h * 0.85)
    roi = hsv[y_start:y_end, :]

    if roi.size == 0:
        return "Unknown"

    saturation = roi[:, :, 1]
    value = roi[:, :, 2]

    achromatic_mask = saturation < ACHROMATIC_THRESHOLD
    achromatic_ratio = np.sum(achromatic_mask) / achromatic_mask.size

    if achromatic_ratio > 0.6:
        mean_value = np.mean(value[achromatic_mask])
        if mean_value > 200:
            return "White"
        elif mean_value > 140:
            return "Silver"
        elif mean_value > 70:
            return "Grey"
        else:
            return "Black"

    chromatic_mask = ~achromatic_mask
    if np.sum(chromatic_mask) == 0:
        return "Grey"

    hue_values = roi[:, :, 0][chromatic_mask]
    hist, _ = np.histogram(hue_values, bins=180, range=(0, 180))
    peak_hue = int(np.argmax(hist))

    for (h_low, h_high), (s_low, s_high), color_name in COLOR_RANGES:
        if h_low <= peak_hue <= h_high:
            return color_name

    return "Unknown"


class VehicleClassifier:
    """SigLIP zero-shot vehicle classifier with optional DINOv2 head."""

    def __init__(self):
        self._siglip_model = None
        self._siglip_preprocess = None
        self._siglip_text_features = None
        self._classes = []
        self._device = "cpu"
        self._dinov2_model = None
        self._dinov2_transform = None
        self._dinov2_head = None

    def load(self) -> bool:
        """Load SigLIP model and vehicle class prompts."""
        try:
            import ssl
            ssl._create_default_https_context = ssl._create_unverified_context

            import torch
            import open_clip

            self._device = "mps" if torch.backends.mps.is_available() else "cpu"

            self._siglip_model, _, self._siglip_preprocess = open_clip.create_model_and_transforms(
                "ViT-B-16-SigLIP", pretrained="webli"
            )
            self._siglip_model = self._siglip_model.eval().to(self._device)

            self._load_classes()
            self._precompute_text_features()

            logger.info(f"SigLIP loaded on {self._device} with {len(self._classes)} classes")

            self._try_load_dinov2()
            return True
        except Exception as e:
            logger.warning(f"Vehicle classifier load failed: {e}")
            return False

    def _load_classes(self):
        if CLASSES_FILE.exists():
            data = json.loads(CLASSES_FILE.read_text())
            self._classes = data.get("classes", [])
        else:
            self._classes = []

    def _precompute_text_features(self):
        """Pre-compute text embeddings for all classes (done once at startup)."""
        if not self._classes or self._siglip_model is None:
            return

        import torch
        import open_clip

        tokenizer = open_clip.get_tokenizer("ViT-B-16-SigLIP")
        prompts = [f"a photo of {c['prompt']}" for c in self._classes]
        tokens = tokenizer(prompts).to(self._device)

        with torch.no_grad():
            self._siglip_text_features = self._siglip_model.encode_text(tokens)
            self._siglip_text_features /= self._siglip_text_features.norm(dim=-1, keepdim=True)

    def _try_load_dinov2(self):
        """Load DINOv2 + trained linear head if available."""
        if not DINOV2_MODEL_PATH.exists():
            return

        try:
            import torch

            self._dinov2_model = torch.hub.load("facebookresearch/dinov2", "dinov2_vitb14", pretrained=True)
            self._dinov2_model = self._dinov2_model.eval().to(self._device)

            head_data = torch.load(DINOV2_MODEL_PATH, map_location=self._device, weights_only=True)
            num_classes = head_data["weight"].shape[0]
            self._dinov2_head = torch.nn.Linear(768, num_classes)
            self._dinov2_head.load_state_dict(head_data)
            self._dinov2_head = self._dinov2_head.eval().to(self._device)

            from torchvision import transforms as T
            self._dinov2_transform = T.Compose([
                T.Resize(224, T.InterpolationMode.BICUBIC),
                T.CenterCrop(224),
                T.ToTensor(),
                T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
            ])

            logger.info("DINOv2 + trained head loaded")
        except Exception as e:
            logger.debug(f"DINOv2 not loaded: {e}")
            self._dinov2_model = None
            self._dinov2_head = None

    @property
    def is_loaded(self) -> bool:
        return self._siglip_model is not None

    @property
    def num_classes(self) -> int:
        return len(self._classes)

    @property
    def classes(self) -> list[dict]:
        return self._classes

    def classify(self, vehicle_crop: np.ndarray) -> dict:
        """
        Classify a vehicle crop. Returns top-3 predictions.
        Uses DINOv2 if available and confident, otherwise SigLIP zero-shot.
        """
        if not self.is_loaded or vehicle_crop.size == 0:
            return {"predictions": [], "confidence": 0.0, "source": "none"}

        import torch
        from PIL import Image

        pil_img = Image.fromarray(vehicle_crop).convert("RGB")

        # Try DINOv2 first (if trained head exists)
        if self._dinov2_model is not None and self._dinov2_head is not None:
            dino_result = self._classify_dinov2(pil_img)
            if dino_result and dino_result["confidence"] > 0.8:
                return dino_result

        # SigLIP zero-shot
        img_tensor = self._siglip_preprocess(pil_img).unsqueeze(0).to(self._device)

        with torch.no_grad():
            img_features = self._siglip_model.encode_image(img_tensor)
            img_features /= img_features.norm(dim=-1, keepdim=True)
            similarities = (img_features @ self._siglip_text_features.T).squeeze(0)

        scores = similarities.cpu().numpy()
        top_indices = scores.argsort()[::-1][:3]

        predictions = []
        for idx in top_indices:
            cls = self._classes[idx]
            predictions.append({
                "id": cls["id"],
                "brand": cls["brand"],
                "model": cls["model"],
                "type": cls["type"],
                "confidence": round(float(scores[idx]), 3),
            })

        return {
            "predictions": predictions,
            "confidence": predictions[0]["confidence"] if predictions else 0.0,
            "source": "siglip",
        }

    def _classify_dinov2(self, pil_img) -> dict | None:
        import torch

        try:
            tensor = self._dinov2_transform(pil_img).unsqueeze(0).to(self._device)
            with torch.no_grad():
                features = self._dinov2_model(tensor)
                logits = self._dinov2_head(features)
                probs = torch.softmax(logits, dim=-1).squeeze(0)

            top_indices = probs.argsort(descending=True)[:3]
            predictions = []
            for idx in top_indices:
                idx_val = int(idx)
                if idx_val < len(self._classes):
                    cls = self._classes[idx_val]
                    predictions.append({
                        "id": cls["id"],
                        "brand": cls["brand"],
                        "model": cls["model"],
                        "type": cls["type"],
                        "confidence": round(float(probs[idx_val]), 3),
                    })

            if predictions:
                return {
                    "predictions": predictions,
                    "confidence": predictions[0]["confidence"],
                    "source": "dinov2",
                }
        except Exception:
            pass
        return None

    def add_class(self, class_id: str, brand: str, model: str, vehicle_type: str, prompt: str):
        """Add a new vehicle class dynamically. Recomputes text features."""
        new_class = {
            "id": class_id,
            "brand": brand,
            "model": model,
            "type": vehicle_type,
            "prompt": prompt,
        }
        self._classes.append(new_class)
        self._save_classes()
        self._precompute_text_features()

    def _save_classes(self):
        data = {"version": 1, "classes": self._classes}
        CLASSES_FILE.write_text(json.dumps(data, indent=2))


class VehicleCaptureStore:
    """Auto-captures and stores vehicle crops for future labeling."""

    def __init__(self):
        CAPTURES_DIR.mkdir(parents=True, exist_ok=True)

    def capture(self, vehicle_crop: np.ndarray, metadata: dict | None = None) -> str:
        """Save a vehicle crop for future labeling. Returns capture ID."""
        capture_id = uuid.uuid4().hex[:12]
        img_path = CAPTURES_DIR / f"{capture_id}.jpg"

        bgr = cv2.cvtColor(vehicle_crop, cv2.COLOR_RGB2BGR)
        cv2.imwrite(str(img_path), bgr, [cv2.IMWRITE_JPEG_QUALITY, 85])

        record = {
            "id": capture_id,
            "timestamp": time.time(),
            "labeled": False,
            "label": None,
            **(metadata or {}),
        }

        with open(LABELS_FILE, "a") as f:
            f.write(json.dumps(record) + "\n")

        return capture_id

    def label(self, capture_id: str, class_id: str) -> bool:
        """Label a previously captured image."""
        if not LABELS_FILE.exists():
            return False

        lines = LABELS_FILE.read_text().strip().split("\n")
        updated = False
        new_lines = []
        for line in lines:
            if not line:
                continue
            record = json.loads(line)
            if record["id"] == capture_id:
                record["labeled"] = True
                record["label"] = class_id
                record["labeled_at"] = time.time()
                updated = True
            new_lines.append(json.dumps(record))

        if updated:
            LABELS_FILE.write_text("\n".join(new_lines) + "\n")
        return updated

    def get_unlabeled(self, limit: int = 50) -> list[dict]:
        """Get unlabeled captures for the labeling UI."""
        if not LABELS_FILE.exists():
            return []

        results = []
        for line in LABELS_FILE.read_text().strip().split("\n"):
            if not line:
                continue
            record = json.loads(line)
            if not record.get("labeled"):
                img_path = CAPTURES_DIR / f"{record['id']}.jpg"
                if img_path.exists():
                    record["path"] = str(img_path)
                    results.append(record)
            if len(results) >= limit:
                break
        return results

    def get_labeled(self) -> list[dict]:
        """Get all labeled captures for training."""
        if not LABELS_FILE.exists():
            return []

        results = []
        for line in LABELS_FILE.read_text().strip().split("\n"):
            if not line:
                continue
            record = json.loads(line)
            if record.get("labeled"):
                img_path = CAPTURES_DIR / f"{record['id']}.jpg"
                if img_path.exists():
                    record["path"] = str(img_path)
                    results.append(record)
        return results

    def get_stats(self) -> dict:
        """Get labeling statistics."""
        if not LABELS_FILE.exists():
            return {"total": 0, "labeled": 0, "unlabeled": 0, "classes": {}}

        total = 0
        labeled = 0
        class_counts: dict[str, int] = {}

        for line in LABELS_FILE.read_text().strip().split("\n"):
            if not line:
                continue
            record = json.loads(line)
            total += 1
            if record.get("labeled"):
                labeled += 1
                cls = record.get("label", "unknown")
                class_counts[cls] = class_counts.get(cls, 0) + 1

        return {
            "total": total,
            "labeled": labeled,
            "unlabeled": total - labeled,
            "classes": class_counts,
        }


# Module-level instances
_classifier: VehicleClassifier | None = None
_capture_store: VehicleCaptureStore | None = None


def get_classifier() -> VehicleClassifier:
    global _classifier
    if _classifier is None:
        _classifier = VehicleClassifier()
    return _classifier


def get_capture_store() -> VehicleCaptureStore:
    global _capture_store
    if _capture_store is None:
        _capture_store = VehicleCaptureStore()
    return _capture_store


def _detect_color_kmeans(crop: np.ndarray) -> str:
    """Detect dominant vehicle color using k-means clustering on the central region."""
    if crop.size == 0:
        return "Unknown"

    h, w = crop.shape[:2]
    # Use central 60% of the image (avoids road/sky edges)
    y1, y2 = int(h * 0.2), int(h * 0.8)
    x1, x2 = int(w * 0.2), int(w * 0.8)
    roi = crop[y1:y2, x1:x2]

    if roi.size == 0:
        return "Unknown"

    # Downsample for speed
    roi_small = cv2.resize(roi, (64, 64))
    pixels = roi_small.reshape(-1, 3).astype(np.float32)

    # K-means with 3 clusters
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 10, 1.0)
    _, labels, centers = cv2.kmeans(pixels, 3, None, criteria, 3, cv2.KMEANS_PP_CENTERS)

    # Pick cluster with most pixels
    counts = np.bincount(labels.flatten(), minlength=3)
    dominant = centers[np.argmax(counts)].astype(int)
    r, g, b = int(dominant[0]), int(dominant[1]), int(dominant[2])

    # Map RGB to color name
    brightness = (r + g + b) / 3
    saturation = max(r, g, b) - min(r, g, b)

    if saturation < 30:
        if brightness > 200:
            return "White"
        elif brightness > 140:
            return "Silver"
        elif brightness > 70:
            return "Grey"
        else:
            return "Black"

    # Chromatic — find dominant hue
    max_ch = max(r, g, b)
    if max_ch == r and r > g and r > b:
        if g > 100:
            return "Orange" if r > 180 else "Brown"
        return "Red"
    elif max_ch == g and g > r and g > b:
        return "Green"
    elif max_ch == b and b > r and b > g:
        return "Blue"
    elif r > 180 and g > 180 and b < 100:
        return "Yellow"
    elif r > 150 and g < 100 and b > 150:
        return "Purple"

    return "Grey"


def describe_vehicle_lite(img: np.ndarray, detector=None) -> dict:
    """
    Lightweight vehicle description: color (k-means) + type from plate detector bbox.
    No ML classifier needed — saves ~400MB RAM.
    """
    vehicle_crop = img
    vehicle_bbox = None
    vehicle_type = "Vehicle"

    # The plate detector also detects vehicles in some configurations
    # Use the full image as the crop since we don't have a dedicated vehicle detector loaded
    if img.size == 0:
        return {
            "vehicle_type": "Vehicle",
            "brand": "Unknown",
            "model": "",
            "color": "Unknown",
            "descriptor": "Vehicle",
            "confidence": 0.0,
            "bbox": None,
            "top_3": [],
            "source": "lite",
        }

    color = _detect_color_kmeans(vehicle_crop)
    descriptor = f"{color} {vehicle_type}" if color != "Unknown" else vehicle_type

    return {
        "vehicle_type": vehicle_type,
        "brand": "Unknown",
        "model": "",
        "color": color,
        "descriptor": descriptor,
        "confidence": 0.0,
        "bbox": vehicle_bbox,
        "top_3": [],
        "source": "lite",
    }
