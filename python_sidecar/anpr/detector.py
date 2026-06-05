"""
Plate detection wrapper.
Handles model loading priority (fine-tuned > pre-trained > generic YOLO)
and provides a unified interface for plate localization.

Enhancements for poor-quality feeds:
1. Pre-detection CLAHE + sharpening on full frame
2. Low confidence threshold (0.1) — OCR validation filters false positives
3. Larger inference size (1280px) for full-frame pass
4. Frame stacking (temporal averaging) for stationary vehicles
5. Super-resolution upscaling on plate crops before OCR
"""

from collections import deque
from pathlib import Path

import cv2
import numpy as np


MODEL_DIR = Path(__file__).parent.parent / "models" / "anpr"


# Priority order for plate detection models
# OpenVINO INT8 is preferred on Intel (2.5x faster), falls back to PyTorch .pt
MODEL_CANDIDATES_OPENVINO = [
    "plate_openvino_int8",  # INT8 quantized for Intel CPUs
]

MODEL_CANDIDATES_PT = [
    "plate_finetuned.pt",   # Site-specific fine-tuned model (best)
    "plate_pretrained.pt",  # Pre-trained on Indian plate dataset
]


def _openvino_available() -> bool:
    try:
        import openvino  # noqa: F401
        return True
    except ImportError:
        return False


def find_best_plate_model() -> Path | None:
    """Find the best available plate detection model by priority.
    Prefers OpenVINO INT8 on Intel/Linux (if openvino installed), falls back to PyTorch .pt."""
    import platform

    is_apple_silicon = platform.system() == "Darwin" and platform.machine() == "arm64"

    # On Intel (not Apple Silicon), prefer OpenVINO INT8 if runtime available
    if not is_apple_silicon and _openvino_available():
        for name in MODEL_CANDIDATES_OPENVINO:
            path = MODEL_DIR / name
            if path.is_dir() and (path / "best.xml").exists():
                return path

    for name in MODEL_CANDIDATES_PT:
        path = MODEL_DIR / name
        if path.exists():
            return path
    return None


def is_plate_like(img: np.ndarray, bbox: list[float]) -> bool:
    """
    Post-detection filter: reject false positives that look like plates
    by aspect ratio but aren't (signs, stickers, bumper strips, logos).

    Checks:
    1. Aspect ratio within plate range (1.5:1 to 7:1)
    2. Minimum size (not too tiny to be a plate)
    3. High horizontal edge density (plates have text = lots of vertical edges)
    4. Relatively uniform background (plates are mostly one color with text)
    """
    x1, y1, x2, y2 = [int(v) for v in bbox]
    h_img, w_img = img.shape[:2]

    # Clamp
    x1 = max(0, x1)
    y1 = max(0, y1)
    x2 = min(w_img, x2)
    y2 = min(h_img, y2)

    bw = x2 - x1
    bh = y2 - y1

    if bw < 10 or bh < 5:
        return False

    # Aspect ratio: Indian plates range from ~1.5 (double-line) to ~6.5 (single-line)
    aspect = bw / bh
    if aspect < 1.3 or aspect > 8.0:
        return False

    # Minimum plate area relative to frame (reject tiny detections)
    frame_area = h_img * w_img
    plate_area = bw * bh
    if plate_area < frame_area * 0.001:
        return False

    crop = img[y1:y2, x1:x2]
    if crop.size == 0:
        return False

    gray = cv2.cvtColor(crop, cv2.COLOR_RGB2GRAY) if len(crop.shape) == 3 else crop

    # Edge density check: plates have strong vertical edges (character strokes)
    sobel_x = cv2.Sobel(gray, cv2.CV_64F, 1, 0, ksize=3)
    edge_density = np.mean(np.abs(sobel_x)) / 255.0
    if edge_density < 0.04:
        return False

    # Contrast check: plates have high local contrast (dark text on light bg or vice versa)
    local_std = gray.std()
    if local_std < 20:
        return False

    # Reject if too many unique colors (natural scenes, complex textures)
    # Plates are mostly 2-3 colors (background + text + maybe border)
    if len(crop.shape) == 3:
        small = cv2.resize(crop, (30, 10))
        hsv = cv2.cvtColor(small, cv2.COLOR_RGB2HSV)
        # Count dominant hue clusters
        hue_std = hsv[:, :, 0].std()
        if hue_std > 50:
            return False

    return True


def enhance_frame(img: np.ndarray) -> np.ndarray:
    """Pre-detection enhancement: CLAHE + unsharp mask for blurry/low-contrast feeds."""
    # Convert to LAB for CLAHE on luminance
    lab = cv2.cvtColor(img, cv2.COLOR_RGB2LAB)
    clahe = cv2.createCLAHE(clipLimit=2.5, tileGridSize=(8, 8))
    lab[:, :, 0] = clahe.apply(lab[:, :, 0])
    enhanced = cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)

    # Unsharp mask for edge sharpening
    blurred = cv2.GaussianBlur(enhanced, (0, 0), 3)
    sharpened = cv2.addWeighted(enhanced, 1.5, blurred, -0.5, 0)

    return sharpened


class FrameStacker:
    """Temporal averaging of frames from the same camera to reduce noise/blur."""

    def __init__(self, max_frames: int = 3):
        self._buffers: dict[str, deque] = {}
        self._max = max_frames

    def add_and_average(self, camera_id: str, frame: np.ndarray) -> np.ndarray:
        if camera_id not in self._buffers:
            self._buffers[camera_id] = deque(maxlen=self._max)

        buf = self._buffers[camera_id]
        buf.append(frame.astype(np.float32))

        if len(buf) == 1:
            return frame

        stacked = np.mean(list(buf), axis=0).astype(np.uint8)
        return stacked

    def clear(self, camera_id: str | None = None):
        if camera_id:
            self._buffers.pop(camera_id, None)
        else:
            self._buffers.clear()


class PlateEnhancer:
    """Lossless plate crop enhancer: Lanczos4 upscale + CLAHE contrast.

    No neural-net SR — those hallucinate text details that confuse OCR and
    make the plate look wrong to the operator. This approach:
      - Lanczos4: sharpest classical interpolation, zero artifacts
      - CLAHE on L channel: recovers faded/washed-out text without ringing
      - No unsharp mask: avoids halo artifacts around characters
    """

    def __init__(self):
        self._clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(4, 2))

    @property
    def is_loaded(self) -> bool:
        return True

    @property
    def model_name(self) -> str:
        return "lanczos4_clahe"

    def load(self) -> bool:
        return True

    def upscale(self, crop: np.ndarray) -> np.ndarray:
        """Upscale plate crop 2x with Lanczos4 + CLAHE. No hallucination."""
        h, w = crop.shape[:2]
        upscaled = cv2.resize(crop, (w * 2, h * 2), interpolation=cv2.INTER_LANCZOS4)

        if len(upscaled.shape) == 2:
            return self._clahe.apply(upscaled)

        lab = cv2.cvtColor(upscaled, cv2.COLOR_RGB2LAB)
        lab[:, :, 0] = self._clahe.apply(lab[:, :, 0])
        return cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)


class PlateDetector:
    """Wraps YOLO plate detection with multi-scale inference for small/distant plates."""

    def __init__(self, model_path: Path | None = None, hw_tier: str = "mid"):
        self._model = None
        self._model_path = model_path or find_best_plate_model()
        self._model_mtime: float = 0
        self.frame_stacker = FrameStacker(max_frames=3)
        self.upscaler = PlateEnhancer()

    def load(self) -> bool:
        if self._model_path is None:
            return False
        try:
            from ultralytics import YOLO
            self._model = YOLO(str(self._model_path))
            self._model_mtime = self._model_path.stat().st_mtime
            return True
        except (ImportError, Exception):
            return False

    def reload_if_updated(self) -> bool:
        """Hot-reload model if the file has been updated on disk."""
        if self._model_path is None or not self._model_path.exists():
            return False
        current_mtime = self._model_path.stat().st_mtime
        if current_mtime > self._model_mtime:
            return self.load()
        return False

    @property
    def is_loaded(self) -> bool:
        return self._model is not None

    @property
    def model_name(self) -> str:
        if self._model_path:
            return self._model_path.name
        return "none"

    def detect(
        self,
        img: np.ndarray,
        conf_threshold: float = 0.1,
        max_results: int = 5,
        imgsz: int = 640,
    ) -> list[dict]:
        """
        Detect plates in an image.
        Returns list of {bbox, confidence, class_id} sorted by confidence.
        Post-filters detections to reject non-plate objects.
        """
        if self._model is None:
            return []

        results = self._model(img, verbose=False, conf=conf_threshold, imgsz=imgsz)

        detections = []
        for r in results:
            for box in r.boxes:
                conf = float(box.conf[0])
                bbox = box.xyxy[0].tolist()
                if not is_plate_like(img, bbox):
                    continue
                detections.append({
                    "bbox": bbox,
                    "confidence": conf,
                    "class_id": int(box.cls[0]),
                })

        detections.sort(key=lambda d: d["confidence"], reverse=True)
        return detections[:max_results]

    def detect_multiscale(
        self,
        img: np.ndarray,
        conf_threshold: float = 0.15,
        max_results: int = 5,
        camera_id: str = "",
    ) -> list[dict]:
        """
        Full detection pipeline:
        1. Enhance frame (CLAHE + sharpen)
        2. Frame stacking (temporal noise reduction)
        3. Full-frame pass at 1280px inference size
        4. Tiled detection (4 overlapping quadrants) at 640px
        5. NMS deduplication
        """
        # Pre-detection enhancement
        enhanced = enhance_frame(img)

        # Frame stacking for noise reduction
        if camera_id:
            enhanced = self.frame_stacker.add_and_average(camera_id, enhanced)

        h, w = enhanced.shape[:2]
        detections = []

        # Full frame at higher resolution (1280px) — catches medium plates
        detections.extend(self.detect(enhanced, conf_threshold, max_results, imgsz=1280))

        # 4 overlapping tiles at 640px — catches small/distant plates
        overlap = 0.2
        tile_h = int(h * (0.5 + overlap / 2))
        tile_w = int(w * (0.5 + overlap / 2))

        tiles = [
            (0, 0),                         # top-left
            (0, w - tile_w),                # top-right
            (h - tile_h, 0),                # bottom-left
            (h - tile_h, w - tile_w),       # bottom-right
        ]

        for y_off, x_off in tiles:
            tile = enhanced[y_off:y_off + tile_h, x_off:x_off + tile_w]
            tile_dets = self.detect(tile, conf_threshold, max_results=2, imgsz=640)

            for det in tile_dets:
                x1, y1, x2, y2 = det["bbox"]
                det["bbox"] = [x1 + x_off, y1 + y_off, x2 + x_off, y2 + y_off]
                det["confidence"] *= 0.95
                detections.append(det)

        # Deduplicate overlapping detections from tile overlaps
        detections = self._nms(detections, iou_threshold=0.45)
        detections.sort(key=lambda d: d["confidence"], reverse=True)
        return detections[:max_results]

    def enhance_crop(self, crop: np.ndarray) -> np.ndarray:
        """Super-resolution upscale a plate crop for better OCR."""
        if crop.size == 0:
            return crop
        h, w = crop.shape[:2]
        # Only upscale if crop is small (< 100px height)
        if h >= 100:
            return crop
        return self.upscaler.upscale(crop)

    @staticmethod
    def _nms(detections: list[dict], iou_threshold: float = 0.45) -> list[dict]:
        """Non-maximum suppression to remove duplicate detections from tile overlaps."""
        if len(detections) <= 1:
            return detections

        detections.sort(key=lambda d: d["confidence"], reverse=True)
        keep = []

        for det in detections:
            is_dup = False
            for kept in keep:
                if _iou(det["bbox"], kept["bbox"]) > iou_threshold:
                    is_dup = True
                    break
            if not is_dup:
                keep.append(det)

        return keep


def _iou(box_a: list[float], box_b: list[float]) -> float:
    x1 = max(box_a[0], box_b[0])
    y1 = max(box_a[1], box_b[1])
    x2 = min(box_a[2], box_b[2])
    y2 = min(box_a[3], box_b[3])

    inter = max(0, x2 - x1) * max(0, y2 - y1)
    if inter == 0:
        return 0.0

    area_a = (box_a[2] - box_a[0]) * (box_a[3] - box_a[1])
    area_b = (box_b[2] - box_b[0]) * (box_b[3] - box_b[1])
    return inter / (area_a + area_b - inter)
