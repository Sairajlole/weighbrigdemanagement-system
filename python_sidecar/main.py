"""
Weighbridge AI Sidecar — FastAPI server for inference.
Runs on relay host device, accessible over LAN.
"""

import os

# Must be set before any torch/faiss/onnx import to avoid dual-libomp SIGSEGV on macOS ARM64
os.environ.setdefault("KMP_DUPLICATE_LIB_OK", "TRUE")
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("MKL_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("VECLIB_MAXIMUM_THREADS", "1")
os.environ.setdefault("NUMEXPR_NUM_THREADS", "1")
os.environ.setdefault("ORT_NUM_THREADS", "1")

import base64
import io
import time
from contextlib import asynccontextmanager
from pathlib import Path

import cv2
import numpy as np

try:
    import torch
    torch.set_num_threads(1)
    torch.set_num_interop_threads(1)
except Exception:
    pass
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image
from pydantic import BaseModel

from anpr.consensus import add_reading, create_session, delete_session, get_result
from anpr.detector import PlateDetector
from anpr.ocr import run_ocr_on_crop, ParseqOCR
from anpr.preprocess import compute_sharpness, deskew
from anpr.vehicle_describe import describe_vehicle_lite, get_capture_store
from face import FaceRecord, get_face_index, get_face_engine
from face.index import MAX_CENTROIDS

import asyncio
import threading
from concurrent.futures import ThreadPoolExecutor

MODEL_DIR = Path(__file__).parent / "models"
TRAINING_DIR = Path.home() / ".weighbridge" / "training_data"

_models: dict = {}
_inference_lock = threading.Lock()
_inference_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="inference")


async def _run_inference(fn, *args, **kwargs):
    """Run a blocking inference function in a single-threaded executor to prevent concurrency."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(_inference_executor, lambda: fn(*args, **kwargs))


def _load_models():
    global _models
    # Plate-specific detector (priority-based: finetuned > pretrained)
    plate_det = PlateDetector(hw_tier=_hw_tier)
    if plate_det.load():
        _models["plate_detector"] = plate_det

    # Material classifier: only load if site-specific trained model exists
    site_material_path = Path.home() / ".weighbridge" / "models" / "material_classifier.pt"
    if site_material_path.exists():
        try:
            from ultralytics import YOLO
            _models["material_classifier"] = YOLO(str(site_material_path))
            print(f"  [Models] Loaded site-trained material classifier: {site_material_path}")
        except ImportError:
            pass

    # OCR: PARSeq only (frame-consensus replaces need for secondary engine)
    parseq = ParseqOCR()
    if parseq.load():
        _models["ocr"] = parseq

    # Face: ArcFace GlintR100 + SCRFD
    face_engine = get_face_engine()
    if face_engine.load():
        _models["face"] = face_engine


def _log_gpu_status():
    """Log whether Intel GPU acceleration is available."""
    try:
        import onnxruntime as ort
        available = ort.get_available_providers()
        if "OpenVINOExecutionProvider" in available:
            print("[GPU] Intel OpenVINO GPU acceleration: ACTIVE")
        elif "DmlExecutionProvider" in available:
            print("[GPU] DirectML GPU acceleration: ACTIVE")
        else:
            print(f"[GPU] No GPU acceleration available (providers: {available})")
            print("[GPU] To enable: pip install onnxruntime-openvino && update Intel GPU driver")
    except Exception as e:
        print(f"[GPU] Check failed: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):
    _log_gpu_status()
    _load_models()
    yield


app = FastAPI(title="Weighbridge AI Sidecar", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

STATIC_DIR = Path(__file__).parent / "static"
if STATIC_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")


@app.get("/labeler")
async def labeler_ui():
    """Serve the vehicle labeling web UI."""
    return FileResponse(str(STATIC_DIR / "labeler.html"))


class HealthResponse(BaseModel):
    status: str
    models_loaded: list[str]
    uptime: float
    avg_inference_ms: float = 0.0
    hardware_tier: str = "unknown"
    platform: str = ""
    cpu_cores: int = 0
    ocr_variants: int = 3
    multiscale: bool = True
    sr_model: str = "lanczos4_clahe"


class AnprResult(BaseModel):
    plate_text: str
    confidence: float
    bbox: list[float]
    plate_type: str = "unknown"
    frame_quality: float = 0.0


class PersonDetection(BaseModel):
    count: int
    boxes: list[list[float]]
    confidences: list[float]


class MaterialResult(BaseModel):
    material: str
    confidence: float
    top_3: list[dict]


class FaceEmbedResult(BaseModel):
    embedding: list[float]
    bbox: list[float]
    confidence: float
    faces_found: int


class FaceCompareResult(BaseModel):
    similarity: float
    is_match: bool
    threshold: float


_start_time = time.time()
_inference_times: list[float] = []


def _record_inference_time(ms: float):
    _inference_times.append(ms)
    if len(_inference_times) > 50:
        _inference_times.pop(0)


def _detect_hardware_tier() -> tuple[str, str, int]:
    """Detect hardware tier for adaptive scan strategy.

    Tiers (high to low): apple_silicon, gpu, high, mid, low, budget
    Works for Intel, AMD, ARM, and any other CPU architecture.
    """
    import platform
    import multiprocessing

    plat = platform.system().lower()
    machine = platform.machine()
    cores = multiprocessing.cpu_count()

    # Check for Apple Silicon (MPS)
    try:
        import torch
        if torch.backends.mps.is_available():
            return "apple_silicon", f"{plat}/{machine}", cores
    except (ImportError, AttributeError):
        pass

    # Check for CUDA GPU (NVIDIA, AMD ROCm)
    try:
        import torch
        if torch.cuda.is_available():
            return "gpu", f"{plat}/cuda", cores
    except (ImportError, AttributeError):
        pass

    # CPU tier by core count — works for Intel, AMD, ARM, etc.
    if cores >= 12:
        tier = "high"
    elif cores >= 6:
        tier = "mid"
    elif cores >= 4:
        tier = "low"
    else:
        tier = "budget"

    return tier, f"{plat}/{machine}", cores


_hw_tier, _hw_platform, _hw_cores = _detect_hardware_tier()

_ocr_max_variants = {
    "apple_silicon": 3, "gpu": 3, "high": 3,
    "mid": 3, "low": 2, "budget": 1,
}.get(_hw_tier, 3)

_use_multiscale = _hw_tier not in ("budget", "low")



@app.get("/health", response_model=HealthResponse)
async def health():
    avg_ms = sum(_inference_times) / len(_inference_times) if _inference_times else 0.0
    sr_name = "bicubic"
    plate_det = _models.get("plate_detector")
    if isinstance(plate_det, PlateDetector) and plate_det.upscaler.is_loaded:
        sr_name = plate_det.upscaler.model_name
    return HealthResponse(
        status="ok",
        models_loaded=list(_models.keys()),
        uptime=time.time() - _start_time,
        avg_inference_ms=round(avg_ms, 1),
        hardware_tier=_hw_tier,
        platform=_hw_platform,
        cpu_cores=_hw_cores,
        ocr_variants=_ocr_max_variants,
        multiscale=_use_multiscale,
        sr_model=sr_name,
    )


async def _read_image(file: UploadFile) -> np.ndarray:
    data = await file.read()
    img = Image.open(io.BytesIO(data)).convert("RGB")
    return np.array(img)


_PLATE_TYPE_COLORS = {
    "commercial":  "#FFD600",  # yellow
    "government":  "#D32F2F",  # red
    "ev":          "#00C853",  # green
    "diplomatic":  "#1565C0",  # blue
    "defence":     "#1565C0",  # blue
    "rental":      "#212121",  # black
}


def _plate_color_from_type(plate_type: str) -> str:
    """Map validated plate type to its standard Indian plate background color."""
    return _PLATE_TYPE_COLORS.get(plate_type, "#FFFFFF")


def _detect_plate_candidates(img: np.ndarray, max_results: int = 5, camera_id: str = "") -> list[tuple[float, list[float]]]:
    """Detect plate candidates using PlateDetector. Returns [(confidence, bbox)]."""
    plate_det = _models.get("plate_detector")

    if not isinstance(plate_det, PlateDetector):
        return []

    if _use_multiscale:
        detections = plate_det.detect_multiscale(img, max_results=max_results, camera_id=camera_id)
    else:
        detections = plate_det.detect(img, max_results=max_results, imgsz=640)
    return [(d["confidence"], d["bbox"]) for d in detections]


@app.post("/anpr", response_model=AnprResult)
async def detect_plate(file: UploadFile = File(...)):
    t0 = time.time()
    img = await _read_image(file)

    plate_text = ""
    plate_type = "unknown"
    confidence = 0.0
    bbox = [0.0, 0.0, 0.0, 0.0]
    frame_quality = 0.0

    def _do_anpr_inference():
        candidates = _detect_plate_candidates(img, max_results=5)
        if not candidates and not _models.get("plate_detector"):
            return None, None, None, None, None
        ocr = _models.get("ocr")
        plate_det = _models.get("plate_detector")
        best_text = ""
        best_type = "unknown"
        best_confidence = 0.0
        _bbox = [0.0, 0.0, 0.0, 0.0]
        _fq = 0.0
        for det_conf, box_coords in candidates[:5]:
            x1, y1, x2, y2 = [int(v) for v in box_coords]
            h, w = img.shape[:2]
            pad_x = int((x2 - x1) * 0.08)
            pad_y = int((y2 - y1) * 0.12)
            x1 = max(0, x1 - pad_x)
            y1 = max(0, y1 - pad_y)
            x2 = min(w, x2 + pad_x)
            y2 = min(h, y2 + pad_y)
            plate_crop = img[y1:y2, x1:x2]
            if plate_crop.size == 0 or not ocr:
                continue
            text, conf, p_type = run_ocr_on_crop(ocr, plate_crop, max_variants=_ocr_max_variants)
            if not text:
                continue
            if p_type == "unknown" and conf < 0.7:
                continue
            if conf > best_confidence:
                best_confidence = conf
                best_text = text
                best_type = p_type
                _bbox = box_coords
                _fq = compute_sharpness(plate_crop)
            if p_type != "unknown":
                break
        return best_text, best_type, best_confidence, _bbox, _fq

    result = await _run_inference(_do_anpr_inference)
    if result[0] is None:
        raise HTTPException(503, "No plate detection model loaded")
    best_text, best_type, best_confidence, bbox, frame_quality = result

    if best_text:
        plate_text = best_text
        plate_type = best_type
        confidence = best_confidence

    _record_inference_time((time.time() - t0) * 1000)

    # Normalize bbox to 0-1 range
    h, w = img.shape[:2]
    norm_bbox = [bbox[0] / w, bbox[1] / h, bbox[2] / w, bbox[3] / h] if any(v > 0 for v in bbox) else bbox

    return AnprResult(
        plate_text=plate_text,
        confidence=round(confidence, 3),
        bbox=norm_bbox,
        plate_type=plate_type,
        frame_quality=round(frame_quality, 1),
    )


@app.post("/anpr/correct")
async def anpr_correct(file: UploadFile = File(...), correct_plate: str = Form(""), bbox: str = Form("")):
    """Save operator correction for fine-tuning. Stores frame + bbox + correct plate text."""
    if not correct_plate:
        raise HTTPException(400, "correct_plate required")

    img = await _read_image(file)
    h, w = img.shape[:2]

    # Parse bbox if provided (x1,y1,x2,y2 in pixels)
    bbox_coords = []
    if bbox:
        try:
            bbox_coords = [float(x) for x in bbox.split(",")]
        except ValueError:
            pass

    import json
    import uuid

    sample_id = uuid.uuid4().hex[:10]
    sample_dir = TRAINING_DIR / "anpr" / sample_id
    sample_dir.mkdir(parents=True, exist_ok=True)

    # Save frame
    frame_path = sample_dir / "frame.jpg"
    pil_img = Image.fromarray(img)
    pil_img.save(str(frame_path), quality=90)

    # Save metadata
    meta = {
        "correct_plate": correct_plate,
        "bbox": bbox_coords if bbox_coords else None,
        "img_width": w,
        "img_height": h,
        "timestamp": time.time(),
    }
    (sample_dir / "metadata.json").write_text(json.dumps(meta))

    # Also save in YOLO detection format for retrain script
    if bbox_coords and len(bbox_coords) == 4:
        corrections_dir = Path(__file__).parent / "data" / "corrections"
        corrections_dir.mkdir(parents=True, exist_ok=True)

        cv2.imwrite(str(corrections_dir / f"{sample_id}.jpg"), img)

        # YOLO format: class x_center y_center width height (all normalized 0-1)
        x1, y1, x2, y2 = bbox_coords
        x_center = ((x1 + x2) / 2) / w
        y_center = ((y1 + y2) / 2) / h
        bw = (x2 - x1) / w
        bh = (y2 - y1) / h
        label_line = f"0 {x_center:.6f} {y_center:.6f} {bw:.6f} {bh:.6f}\n"
        (corrections_dir / f"{sample_id}.txt").write_text(label_line)

    # Check if retrain threshold reached
    correction_count = sum(1 for _ in (TRAINING_DIR / "anpr").rglob("metadata.json")) if (TRAINING_DIR / "anpr").exists() else 0
    retrain_ready = correction_count >= 200 and correction_count % 50 == 0

    return {"status": "saved", "sample_id": sample_id, "correction_count": correction_count, "retrain_ready": retrain_ready}


@app.post("/anpr/session/start")
async def anpr_session_start(body: dict | None = None):
    """Start a new consensus session for multi-frame ANPR."""
    min_votes = 3
    max_frames = 15
    if body:
        min_votes = body.get("min_votes", 3)
        max_frames = body.get("max_frames", 15)
    session_id = create_session(min_votes=min_votes, max_frames=max_frames)
    return {"session_id": session_id}


@app.post("/anpr/session/{session_id}/frame")
async def anpr_session_frame(
    session_id: str,
    file: UploadFile = File(...),
    camera_id: str = Form(""),
    privacy_zones: str = Form(""),
):
    """Add a frame to the consensus session — detects plate and accumulates readings."""
    img = await _read_image(file)

    # Apply privacy zone masking — black out regions where ANPR should not scan
    if privacy_zones:
        try:
            import json as _json
            zones = _json.loads(privacy_zones)
            h, w = img.shape[:2]
            for zone in zones:
                if len(zone) == 4:
                    zx1 = int(zone[0] * w)
                    zy1 = int(zone[1] * h)
                    zx2 = int(zone[2] * w)
                    zy2 = int(zone[3] * h)
                    img[zy1:zy2, zx1:zx2] = 0
        except Exception:
            pass

    def _do_session_frame_inference():
        candidates = _detect_plate_candidates(img, max_results=3, camera_id=camera_id)
        if not candidates and not _models.get("plate_detector"):
            return None
        ocr = _models.get("ocr")
        plate_det = _models.get("plate_detector")
        _plate_text = ""
        _plate_type = "unknown"
        _confidence = 0.0
        _frame_quality = 0.0
        _bbox = [0.0, 0.0, 0.0, 0.0]
        _plate_crop_b64 = ""
        _plate_bg_color = "#FFFFFF"
        _sr_applied = False
        for det_conf, box_coords in candidates[:3]:
            x1, y1, x2, y2 = [int(v) for v in box_coords]
            h, w = img.shape[:2]
            pad_x = int((x2 - x1) * 0.08)
            pad_y = int((y2 - y1) * 0.12)
            x1 = max(0, x1 - pad_x)
            y1 = max(0, y1 - pad_y)
            x2 = min(w, x2 + pad_x)
            y2 = min(h, y2 + pad_y)
            plate_crop = img[y1:y2, x1:x2]
            if plate_crop.size == 0 or not ocr:
                continue
            text, conf, p_type = run_ocr_on_crop(ocr, plate_crop, max_variants=_ocr_max_variants)
            if text and (p_type != "unknown" or conf > 0.7):
                _plate_text = text
                _plate_type = p_type
                _confidence = conf
                _frame_quality = compute_sharpness(plate_crop)
                _bbox = box_coords
                display_crop = deskew(plate_crop)
                if isinstance(plate_det, PlateDetector):
                    pre_h = display_crop.shape[0]
                    display_crop = plate_det.enhance_crop(display_crop)
                    _sr_applied = display_crop.shape[0] > pre_h
                pil_crop = Image.fromarray(display_crop)
                buf = io.BytesIO()
                pil_crop.save(buf, format="JPEG", quality=85)
                _plate_crop_b64 = base64.b64encode(buf.getvalue()).decode("ascii")
                _plate_bg_color = _plate_color_from_type(p_type)
                break
        return _plate_text, _plate_type, _confidence, _frame_quality, _bbox, _plate_crop_b64, _plate_bg_color, _sr_applied

    result = await _run_inference(_do_session_frame_inference)
    if result is None:
        raise HTTPException(503, "No plate detection model loaded")
    plate_text, plate_type, confidence, frame_quality, bbox, plate_crop_b64, plate_bg_color, sr_applied = result

    # Add to consensus regardless (empty text = no detection this frame)
    voting_state = add_reading(
        session_id=session_id,
        plate_text=plate_text,
        plate_type=plate_type,
        confidence=confidence,
        camera_id=camera_id,
        frame_quality=frame_quality,
        plate_crop_b64=plate_crop_b64,
    )

    # Normalize bbox to 0-1 range for overlay rendering
    h, w = img.shape[:2]
    norm_bbox = [bbox[0] / w, bbox[1] / h, bbox[2] / w, bbox[3] / h] if any(v > 0 for v in bbox) else bbox

    # Include per-frame detection info for live overlay
    voting_state["frame_detection"] = {
        "plate_text": plate_text,
        "confidence": round(confidence, 3),
        "bbox": norm_bbox,
        "plate_type": plate_type,
        "sr_applied": sr_applied,
        "plate_crop_b64": plate_crop_b64,
        "plate_bg_color": plate_bg_color,
    }

    return voting_state


@app.get("/anpr/session/{session_id}/result")
async def anpr_session_result(session_id: str):
    """Get current consensus result for a session."""
    result = get_result(session_id)
    if "error" in result:
        raise HTTPException(404, result["error"])
    return result


@app.delete("/anpr/session/{session_id}")
async def anpr_session_delete(session_id: str):
    """Clean up a consensus session."""
    deleted = delete_session(session_id)
    return {"deleted": deleted}


@app.post("/vehicle/describe")
async def vehicle_describe(file: UploadFile = File(...)):
    """Describe vehicle type and color using lightweight detection (no ML classifier)."""
    img = await _read_image(file)
    detector = _models.get("plate_detector")
    result = await _run_inference(describe_vehicle_lite, img, detector)
    return result


# =============================================================================




@app.post("/persons", response_model=PersonDetection)
async def detect_persons(file: UploadFile = File(...)):
    img = await _read_image(file)

    detector = _models.get("person_detector")
    if detector is None:
        raise HTTPException(503, "No person detection model loaded")

    results = detector(img, classes=[0], verbose=False)
    boxes = []
    confidences = []
    for r in results:
        for box in r.boxes:
            boxes.append(box.xyxy[0].tolist())
            confidences.append(float(box.conf[0]))

    return PersonDetection(count=len(boxes), boxes=boxes, confidences=confidences)


@app.post("/material", response_model=MaterialResult)
async def classify_material(file: UploadFile = File(...)):
    img = await _read_image(file)

    classifier = _models.get("material_classifier")
    if classifier is None:
        raise HTTPException(503, "No material classifier loaded — needs training data")

    results = classifier(img, verbose=False)
    if results and results[0].probs is not None:
        probs = results[0].probs
        top_idx = int(probs.top1)
        top_conf = float(probs.top1conf)
        names = results[0].names

        top_3 = []
        top5_indices = probs.top5
        top5_confs = probs.top5conf.tolist()
        for idx, conf in zip(top5_indices[:3], top5_confs[:3]):
            top_3.append({"material": names[idx], "confidence": round(conf, 3)})

        return MaterialResult(
            material=names[top_idx],
            confidence=round(top_conf, 3),
            top_3=top_3,
        )

    return MaterialResult(material="unknown", confidence=0.0, top_3=[])


@app.post("/face/embed", response_model=FaceEmbedResult)
async def face_embed(file: UploadFile = File(...)):
    img = cv2.cvtColor(await _read_image(file), cv2.COLOR_RGB2BGR)

    engine = _models.get("face")
    if engine is None:
        raise HTTPException(503, "Face model not loaded")

    result = await _run_inference(engine.extract_best, img, quality_thresh=0.0)
    if result.embedding is None:
        return FaceEmbedResult(embedding=[], bbox=[0, 0, 0, 0], confidence=0.0, faces_found=0)

    return FaceEmbedResult(
        embedding=result.embedding.tolist(),
        bbox=result.bbox,
        confidence=result.det_score,
        faces_found=result.num_faces,
    )


@app.post("/face/compare")
async def face_compare(
    file1: UploadFile = File(...),
    file2: UploadFile = File(...),
    threshold: float = 0.4,
):
    img1 = cv2.cvtColor(await _read_image(file1), cv2.COLOR_RGB2BGR)
    img2 = cv2.cvtColor(await _read_image(file2), cv2.COLOR_RGB2BGR)

    engine = _models.get("face")
    if engine is None:
        raise HTTPException(503, "Face model not loaded")

    def _do_compare():
        r1 = engine.extract_best(img1, quality_thresh=0.0)
        r2 = engine.extract_best(img2, quality_thresh=0.0)
        return r1, r2

    r1, r2 = await _run_inference(_do_compare)
    if r1.embedding is None or r2.embedding is None:
        return FaceCompareResult(similarity=0.0, is_match=False, threshold=threshold)

    similarity = float(np.dot(r1.embedding, r2.embedding))
    return FaceCompareResult(similarity=round(similarity, 4), is_match=similarity >= threshold, threshold=threshold)


class FaceIdentifyResult(BaseModel):
    match: bool
    record_id: str | None = None
    collection: str | None = None
    name: str | None = None
    email: str | None = None
    phone: str | None = None
    confidence: float = 0.0
    reason: str = ""
    metadata: dict = {}
    quality: float = 0.0
    pose_yaw: float = 0.0
    partial_face: bool = False
    # Legacy fields for backward compat with Flutter operator verification
    operator_id: str | None = None
    operator_email: str | None = None
    operator_name: str | None = None
    is_active: bool = True


def _extract_embedding(face_engine, img: np.ndarray, quality_thresh: float = 0.3):
    """Extract best face embedding from image.
    Returns (embedding, det_score, bbox, quality_score, face_crop_jpeg, is_live, num_faces)."""
    result = face_engine.extract_best(img, quality_thresh=quality_thresh)
    return (
        result.embedding,
        result.det_score,
        result.bbox,
        result.quality_score,
        result.face_crop_jpeg,
        result.is_live,
        result.num_faces,
    )


@app.post("/face/enroll_from_images")
async def enroll_from_images(files: list[UploadFile] = File(...)):
    """Generate a stable embedding from multiple enrollment images (operator enrollment)."""
    engine = _models.get("face")
    if engine is None:
        raise HTTPException(503, "Face model not loaded")

    embeddings = []
    quality_scores = []
    debug_dir = Path("/tmp/face_debug/enroll")
    debug_dir.mkdir(parents=True, exist_ok=True)
    for i, f in enumerate(files):
        img = cv2.cvtColor(await _read_image(f), cv2.COLOR_RGB2BGR)
        cv2.imwrite(str(debug_dir / f"frame_{i}.jpg"), img)
        result = engine.extract_best(img, quality_thresh=0.0)
        # For enrollment, compute quality without liveness penalty
        raw_quality = result.quality_score / (0.85 if not result.is_live else 1.0)
        if result.embedding is not None and raw_quality >= 0.15:
            embeddings.append(result.embedding)
            quality_scores.append(raw_quality)
    print(f"[Enroll] Saved {len(files)} frames to {debug_dir}")

    if len(embeddings) < 3:
        raise HTTPException(
            400, f"Only {len(embeddings)} valid faces from {len(files)} images. Need at least 3."
        )

    avg_embedding = np.mean(embeddings, axis=0)
    avg_embedding = avg_embedding / np.linalg.norm(avg_embedding)

    return {
        "embedding": avg_embedding.tolist(),
        "faces_used": len(embeddings),
        "total_images": len(files),
        "avg_quality": round(float(np.mean(quality_scores)), 3),
    }


@app.post("/face/enroll_embedding")
async def enroll_embedding(body: dict):
    """Add a face embedding to the index. Works for operators, customers, or drivers."""
    record_id = body.get("record_id") or body.get("operator_id", "")
    collection = body.get("collection", "operator")
    name = body.get("name", "")
    email = body.get("email", "")
    phone = body.get("phone", "")
    embedding = body.get("embedding", [])
    metadata = body.get("metadata", {})
    is_active = body.get("is_active", True)

    if not record_id or not embedding:
        raise HTTPException(400, "record_id/operator_id and embedding required")

    if not is_active:
        metadata["is_active"] = False

    index = get_face_index()
    record = FaceRecord(
        record_id=record_id,
        collection=collection,
        name=name,
        email=email,
        phone=phone,
        embedding=np.array(embedding, dtype=np.float32),
        metadata=metadata,
    )
    index.add(record)
    return {"status": "ok", "total_enrolled": index.total_enrolled, "collection_count": index.count(collection)}


@app.get("/face/index_debug")
async def face_index_debug(collection: str = ""):
    """Debug: show enrolled records in the face index."""
    index = get_face_index()
    records = index.get_all(collection or None)
    return {
        "total": index.total_enrolled,
        "operators": index.count("operator"),
        "customers": index.count("customer"),
        "records": [
            {
                "id": r.record_id,
                "collection": r.collection,
                "name": r.name,
                "email": r.email,
                "embedding_norm": float(np.linalg.norm(r.embedding)),
                "embedding_dim": len(r.embedding),
                "centroids": len(r.centroids),
                "is_active": r.metadata.get("is_active", True),
            }
            for r in records
        ],
    }


@app.post("/face/sync_enrollments")
async def sync_enrollments(body: dict):
    """Bulk sync operator + customer embeddings (called on app startup)."""
    index = get_face_index()

    operators = body.get("operators", [])
    if operators:
        records = []
        for op in operators:
            op_id = op.get("operator_id", "")
            embedding = op.get("embedding", [])
            if op_id and embedding:
                records.append(FaceRecord(
                    record_id=op_id,
                    collection="operator",
                    name=op.get("name", ""),
                    email=op.get("email", ""),
                    phone="",
                    embedding=np.array(embedding, dtype=np.float32),
                    metadata={"is_active": op.get("is_active", True)},
                ))
        index.sync_collection("operator", records)

    customers = body.get("customers", [])
    if customers:
        records = []
        for cust in customers:
            cust_id = cust.get("customer_id", "")
            embedding = cust.get("embedding", [])
            if cust_id and embedding:
                centroids_raw = cust.get("centroids", [])
                centroids = [np.array(c, dtype=np.float32) for c in centroids_raw] if centroids_raw else []
                records.append(FaceRecord(
                    record_id=cust_id,
                    collection="customer",
                    name=cust.get("name", ""),
                    email=cust.get("email", ""),
                    phone=cust.get("phone", ""),
                    embedding=np.array(embedding, dtype=np.float32),
                    centroids=centroids,
                    metadata=cust.get("metadata", {}),
                ))
        index.sync_collection("customer", records)

    return {
        "status": "ok",
        "operators": index.count("operator"),
        "customers": index.count("customer"),
        "total": index.total_enrolled,
    }


@app.post("/face/identify", response_model=FaceIdentifyResult)
async def face_identify(
    file: UploadFile = File(...),
    threshold: float = 0.45,
    collection: str = "",
):
    """Identify a face from a single frame. For better accuracy, use /face/verify_burst."""
    engine = _models.get("face")
    if engine is None:
        raise HTTPException(503, "Face model not loaded")

    index = get_face_index()
    if index.total_enrolled == 0:
        return FaceIdentifyResult(match=False, reason="no_enrollments")

    img = cv2.cvtColor(await _read_image(file), cv2.COLOR_RGB2BGR)

    result = await _run_inference(engine.extract_best, img, quality_thresh=0.2)

    if result.embedding is None:
        return FaceIdentifyResult(match=False, reason="no_face")

    is_partial = abs(result.pose_yaw) > 35 or result.quality_score < 0.35

    if collection != "operator" and not result.is_live:
        return FaceIdentifyResult(match=False, reason="spoof_detected", quality=result.quality_score, pose_yaw=result.pose_yaw, partial_face=is_partial)

    # Reject clearly partial faces — too unreliable for matching
    if abs(result.pose_yaw) > 50:
        return FaceIdentifyResult(match=False, reason="partial_face", quality=result.quality_score, pose_yaw=result.pose_yaw, partial_face=True)

    results = index.search(
        result.embedding,
        threshold=threshold,
        top_k=1,
        collection=collection or None,
    )

    if results:
        record, similarity = results[0]
        is_active = record.metadata.get("is_active", True)
        return FaceIdentifyResult(
            match=True,
            record_id=record.record_id,
            collection=record.collection,
            name=record.name,
            email=record.email,
            phone=record.phone,
            confidence=round(similarity, 4),
            metadata=record.metadata,
            quality=result.quality_score,
            pose_yaw=result.pose_yaw,
            partial_face=is_partial,
            operator_id=record.record_id if record.collection == "operator" else None,
            operator_email=record.email if record.collection == "operator" else None,
            operator_name=record.name if record.collection == "operator" else None,
            is_active=is_active,
        )

    return FaceIdentifyResult(match=False, reason="mismatch", confidence=0.0, quality=result.quality_score, pose_yaw=result.pose_yaw, partial_face=is_partial)


@app.post("/face/verify_burst", response_model=FaceIdentifyResult)
async def face_verify_burst(
    files: list[UploadFile] = File(...),
    threshold: float = 0.45,
    collection: str = "",
):
    """Burst-based face verification: accepts multiple frames, picks best-quality embeddings,
    averages top 3, then matches. More reliable than single-frame identify.
    Requires at least one frame to pass liveness."""
    engine = _models.get("face")
    if engine is None:
        raise HTTPException(503, "Face model not loaded")

    index = get_face_index()
    if index.total_enrolled == 0:
        return FaceIdentifyResult(match=False, reason="no_enrollments")

    imgs = [cv2.cvtColor(await _read_image(f), cv2.COLOR_RGB2BGR) for f in files]

    # Debug: save received frames to /tmp for visual inspection
    debug_dir = Path("/tmp/face_debug/verify")
    debug_dir.mkdir(parents=True, exist_ok=True)
    for i, img in enumerate(imgs):
        cv2.imwrite(str(debug_dir / f"frame_{i}.jpg"), img)
    print(f"[VerifyBurst] Saved {len(imgs)} frames to {debug_dir} (shape={imgs[0].shape if imgs else 'N/A'})")

    def _do_burst_inference():
        candidates = []
        any_live = False
        best_yaw = 0.0
        best_quality = 0.0
        for i, img in enumerate(imgs):
            result = engine.extract_best(img, quality_thresh=0.1)
            if result.embedding is not None:
                # Skip frames with extreme yaw (profile/partial face)
                if abs(result.pose_yaw) > 45:
                    print(f"  [Frame {i}] SKIPPED: yaw={result.pose_yaw:.1f} (partial face)")
                    continue
                candidates.append((result.embedding, result.quality_score, result.is_live, result.pose_yaw))
                if result.is_live:
                    any_live = True
                if result.quality_score > best_quality:
                    best_quality = result.quality_score
                    best_yaw = result.pose_yaw
                if result.face_crop_jpeg:
                    (debug_dir / f"crop_{i}.jpg").write_bytes(result.face_crop_jpeg)
        return candidates, any_live, best_quality, best_yaw

    candidates, any_live, best_quality, best_yaw = await _run_inference(_do_burst_inference)

    is_partial = abs(best_yaw) > 35 or best_quality < 0.35

    if not candidates:
        return FaceIdentifyResult(match=False, reason="no_face", partial_face=is_partial)

    print(f"[VerifyBurst] {len(candidates)} candidates, any_live={any_live}, threshold={threshold}, best_quality={best_quality:.3f}")

    # Require at least one live frame for all collections
    if not any_live:
        print(f"[VerifyBurst] REJECTED: no live frames")
        return FaceIdentifyResult(match=False, reason="spoof_detected", quality=best_quality, pose_yaw=best_yaw, partial_face=is_partial)

    # Sort by quality descending, take top 3
    candidates.sort(key=lambda x: x[1], reverse=True)
    top_n = min(3, len(candidates))
    top_embeddings = [c[0] for c in candidates[:top_n]]

    # Average top embeddings and L2-normalize
    avg_emb = np.mean(top_embeddings, axis=0)
    avg_emb = avg_emb / np.linalg.norm(avg_emb)
    avg_quality = np.mean([c[1] for c in candidates[:top_n]])

    # Debug: log per-frame similarities against enrolled
    for i, (emb_i, q_i, live_i, yaw_i) in enumerate(candidates[:top_n]):
        frame_results = index.search(emb_i, threshold=0.0, top_k=1, collection=collection or None)
        if frame_results:
            print(f"  [Frame {i}] quality={q_i:.3f} live={live_i} sim={frame_results[0][1]:.4f} → {frame_results[0][0].name}")
        else:
            print(f"  [Frame {i}] quality={q_i:.3f} live={live_i} — no enrolled faces in collection '{collection}'")

    results = index.search(
        avg_emb,
        threshold=threshold,
        top_k=1,
        collection=collection or None,
    )
    if results:
        record, similarity = results[0]
        print(f"[VerifyBurst] MATCH: {record.name} sim={similarity:.4f} threshold={threshold} quality={avg_quality:.3f}")
        is_active = record.metadata.get("is_active", True)
        return FaceIdentifyResult(
            match=True,
            record_id=record.record_id,
            collection=record.collection,
            name=record.name,
            email=record.email,
            phone=record.phone,
            confidence=round(similarity, 4),
            metadata=record.metadata,
            quality=round(float(avg_quality), 3),
            pose_yaw=round(best_yaw, 1),
            partial_face=is_partial,
            operator_id=record.record_id if record.collection == "operator" else None,
            operator_email=record.email if record.collection == "operator" else None,
            operator_name=record.name if record.collection == "operator" else None,
            is_active=is_active,
        )

    # No match above threshold — report the best sub-threshold similarity for debugging
    below_results = index.search(avg_emb, threshold=0.0, top_k=1, collection=collection or None)
    best_sim = below_results[0][1] if below_results else 0.0
    best_name = below_results[0][0].name if below_results else "none"
    print(f"[VerifyBurst] MISMATCH: best_sim={best_sim:.4f} best_name={best_name} threshold={threshold} enrolled={index.count(collection or None)}")
    return FaceIdentifyResult(match=False, reason="mismatch", confidence=round(best_sim, 4), quality=round(float(avg_quality), 3), pose_yaw=round(best_yaw, 1), partial_face=is_partial)


@app.post("/face/identify_customer")
async def face_identify_customer(
    files: list[UploadFile] = File(...),
    threshold: float = Form(0.45),
    margin: float = Form(0.08),
):
    """Identify a customer from burst of frames (7 recommended).

    Pipeline:
    1. Extract embeddings from all frames, enforce liveness
    2. Average top-3 by quality for robust embedding
    3. Search 10K+ customer gallery with FAISS
    4. Apply margin check: top1 - top2 must exceed `margin` for auto-accept
    5. Progressive update on confident match

    Returns:
    - match=True + customer data if confident identification
    - match=True + ambiguous=True + candidates[] if margin too small
    - match=False + embedding for new enrollment if unknown
    """
    engine = _models.get("face")
    if engine is None:
        raise HTTPException(503, "Face model not loaded")

    # Extract embeddings from burst
    candidates = []
    any_live = False
    best_crop_jpeg = None
    best_quality = 0.0

    for f in files:
        img_rgb = await _read_image(f)
        img = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR)
        result = engine.extract_best(img, det_thresh=0.4, quality_thresh=0.12)
        if result.embedding is not None:
            candidates.append((result.embedding, result.quality_score, result.is_live))
            if result.is_live:
                any_live = True
            if result.quality_score > best_quality:
                best_quality = result.quality_score
                best_crop_jpeg = result.face_crop_jpeg

    if not candidates:
        return {"match": False, "reason": "no_face", "faces_detected": 0}

    # Note: liveness check is informational for customer — don't block identification
    # (geometric checks can fail at distance/angle typical of weighbridge cameras)

    # Average top-3 embeddings by quality
    candidates.sort(key=lambda x: x[1], reverse=True)
    top_n = min(3, len(candidates))
    top_embeddings = [c[0] for c in candidates[:top_n]]
    avg_emb = np.mean(top_embeddings, axis=0).astype(np.float32)
    avg_emb = avg_emb / np.linalg.norm(avg_emb)
    avg_quality = float(np.mean([c[1] for c in candidates[:top_n]]))

    crop_b64 = base64.b64encode(best_crop_jpeg).decode() if best_crop_jpeg else None

    # Search customer gallery (top-5 for margin analysis)
    index = get_face_index()
    results = index.search(avg_emb, threshold=threshold * 0.8, top_k=5, collection="customer")

    if not results:
        return {
            "match": False,
            "reason": "new_face",
            "embedding": avg_emb.tolist(),
            "quality_score": avg_quality,
            "face_crop_b64": crop_b64,
            "frames_used": top_n,
            "total_customers": index.count("customer"),
        }

    top1_record, top1_sim = results[0]
    top2_sim = results[1][1] if len(results) > 1 else 0.0
    gap = top1_sim - top2_sim

    # Below threshold — treat as new face
    if top1_sim < threshold:
        return {
            "match": False,
            "reason": "new_face",
            "embedding": avg_emb.tolist(),
            "quality_score": avg_quality,
            "face_crop_b64": crop_b64,
            "frames_used": top_n,
            "closest_sim": round(top1_sim, 4),
            "total_customers": index.count("customer"),
        }

    # Margin check: if gap too small, it's ambiguous
    if gap < margin and len(results) > 1:
        ambiguous_candidates = []
        for record, sim in results[:3]:
            ambiguous_candidates.append({
                "customer_id": record.record_id,
                "name": record.name,
                "phone": record.phone,
                "confidence": round(sim, 4),
            })
        return {
            "match": True,
            "ambiguous": True,
            "reason": "margin_too_small",
            "candidates": ambiguous_candidates,
            "top1_sim": round(top1_sim, 4),
            "top2_sim": round(top2_sim, 4),
            "gap": round(gap, 4),
            "face_crop_b64": crop_b64,
            "quality_score": avg_quality,
        }

    # Confident match — progressive update
    updated_embedding = None
    updated_centroids = None
    if avg_quality >= 0.4 and top1_sim >= 0.5:
        update_result = index.update_embedding(top1_record.record_id, avg_emb, confidence=top1_sim)
        if update_result is not None:
            updated_embedding = update_result[0].tolist()
            updated_centroids = update_result[1]

    return {
        "match": True,
        "ambiguous": False,
        "customer_id": top1_record.record_id,
        "name": top1_record.name,
        "email": top1_record.email,
        "phone": top1_record.phone,
        "confidence": round(top1_sim, 4),
        "margin": round(gap, 4),
        "metadata": top1_record.metadata,
        "quality_score": avg_quality,
        "face_crop_b64": crop_b64,
        "frames_used": top_n,
        "updated_embedding": updated_embedding,
        "updated_centroids": updated_centroids,
    }


@app.post("/face/enroll_customer")
async def face_enroll_customer(
    files: list[UploadFile] = File(None),
    body: dict | None = None,
):
    """Enroll a new customer face.

    Two modes:
    1. From raw frames (files + form data): extracts multi-frame embedding
    2. From pre-computed embedding (JSON body): uses provided embedding directly

    Performs confusion pair detection: rejects if new face is within 0.45 of
    any existing customer (likely duplicate).
    """
    index = get_face_index()
    engine = _models.get("face")

    # Mode 1: enroll from frames
    if files and len(files) > 0 and files[0].filename:
        if engine is None:
            raise HTTPException(503, "Face model not loaded")

        customer_id = ""
        name = ""
        phone = ""
        email = ""
        metadata = {}

        # Read form data from first file's content-type headers or separate form fields
        # For simplicity, expect these as query params or in a following call
        # Extract embeddings from frames
        embeddings = []
        best_crop = None
        best_q = 0.0
        for f in files:
            img = cv2.cvtColor(await _read_image(f), cv2.COLOR_RGB2BGR)
            result = engine.extract_best(img, quality_thresh=0.15)
            if result.embedding is not None:
                embeddings.append((result.embedding, result.quality_score))
                if result.quality_score > best_q:
                    best_q = result.quality_score
                    best_crop = result.face_crop_jpeg

        if not embeddings:
            raise HTTPException(400, "No face detected in any frame")

        embeddings.sort(key=lambda x: x[1], reverse=True)
        top_n = min(5, len(embeddings))
        avg_emb = np.mean([e[0] for e in embeddings[:top_n]], axis=0).astype(np.float32)
        avg_emb = avg_emb / np.linalg.norm(avg_emb)

        crop_b64 = base64.b64encode(best_crop).decode() if best_crop else None

        return {
            "status": "embedding_ready",
            "embedding": avg_emb.tolist(),
            "faces_used": top_n,
            "total_frames": len(files),
            "avg_quality": round(float(np.mean([e[1] for e in embeddings[:top_n]])), 3),
            "face_crop_b64": crop_b64,
        }

    # Mode 2: enroll from pre-computed embedding (with customer data)
    if body is None:
        raise HTTPException(400, "Provide frames or JSON body with embedding")

    customer_id = body.get("customer_id", "")
    name = body.get("name", "")
    phone = body.get("phone", "")
    email = body.get("email", "")
    embedding = body.get("embedding", [])
    metadata = body.get("metadata", {})

    if not customer_id or not embedding:
        raise HTTPException(400, "customer_id and embedding required")

    emb = np.array(embedding, dtype=np.float32)
    norm = np.linalg.norm(emb)
    if norm < 1e-6:
        raise HTTPException(400, "Invalid embedding (zero norm)")
    emb = emb / norm

    # Confusion pair detection: check if this face matches an existing customer
    existing = index.search(emb, threshold=0.45, top_k=1, collection="customer")
    if existing:
        dup_record, dup_sim = existing[0]
        if dup_record.record_id != customer_id:
            return {
                "status": "duplicate_detected",
                "duplicate_customer_id": dup_record.record_id,
                "duplicate_name": dup_record.name,
                "duplicate_phone": dup_record.phone,
                "similarity": round(dup_sim, 4),
                "message": "This face closely matches an existing customer. Confirm or merge.",
            }

    record = FaceRecord(
        record_id=customer_id,
        collection="customer",
        name=name,
        email=email,
        phone=phone,
        embedding=emb,
        metadata=metadata,
    )
    index.add(record)

    return {
        "status": "enrolled",
        "customer_id": customer_id,
        "total_customers": index.count("customer"),
    }


@app.post("/face/enroll_customer_forced")
async def face_enroll_customer_forced(body: dict):
    """Force-enroll a customer even if confusion pair detected (operator override)."""
    customer_id = body.get("customer_id", "")
    name = body.get("name", "")
    phone = body.get("phone", "")
    email = body.get("email", "")
    embedding = body.get("embedding", [])
    metadata = body.get("metadata", {})

    if not customer_id or not embedding:
        raise HTTPException(400, "customer_id and embedding required")

    emb = np.array(embedding, dtype=np.float32)
    norm = np.linalg.norm(emb)
    if norm < 1e-6:
        raise HTTPException(400, "Invalid embedding")
    emb = emb / norm

    index = get_face_index()
    record = FaceRecord(
        record_id=customer_id,
        collection="customer",
        name=name,
        email=email,
        phone=phone,
        embedding=emb,
        metadata=metadata,
    )
    index.add(record)

    return {
        "status": "enrolled",
        "customer_id": customer_id,
        "total_customers": index.count("customer"),
        "forced": True,
    }


@app.post("/face/customer/{customer_id}/merge")
async def face_merge_customers(customer_id: str, body: dict):
    """Merge duplicate customer into target. Combines centroids from both records."""
    merge_from_id = body.get("merge_from_id", "")
    if not merge_from_id:
        raise HTTPException(400, "merge_from_id required")

    index = get_face_index()
    target = index.get(customer_id)
    source = index.get(merge_from_id)

    if target is None:
        raise HTTPException(404, f"Target customer {customer_id} not found")
    if source is None:
        raise HTTPException(404, f"Source customer {merge_from_id} not found")

    # Add source centroids to target
    if not target.centroids:
        target.centroids = [target.embedding.copy()]
    source_centroids = source.centroids if source.centroids else [source.embedding.copy()]
    for c in source_centroids:
        if len(target.centroids) < MAX_CENTROIDS:
            target.centroids.append(c)

    # Recompute primary embedding
    stacked = np.stack(target.centroids)
    primary = stacked.mean(axis=0)
    target.embedding = (primary / np.linalg.norm(primary)).astype(np.float32)

    # Update target in index
    index.add(target)
    # Remove source
    index.remove(merge_from_id)

    return {
        "status": "merged",
        "target_id": customer_id,
        "removed_id": merge_from_id,
        "centroids_count": len(target.centroids),
        "total_customers": index.count("customer"),
    }


@app.get("/face/customer/{customer_id}")
async def face_get_customer(customer_id: str):
    """Get customer record details."""
    index = get_face_index()
    record = index.get(customer_id)
    if record is None:
        raise HTTPException(404, "Customer not found")
    return {
        "customer_id": record.record_id,
        "name": record.name,
        "email": record.email,
        "phone": record.phone,
        "metadata": record.metadata,
        "centroids_count": len(record.centroids),
        "enrolled_at": record.enrolled_at,
    }


@app.delete("/face/customer/{customer_id}")
async def face_remove_customer(customer_id: str):
    """Remove a customer face from the index."""
    index = get_face_index()
    removed = index.remove(customer_id)
    return {"removed": removed, "total_customers": index.count("customer")}


@app.get("/face/customer_stats")
async def face_customer_stats():
    """Get customer gallery statistics."""
    index = get_face_index()
    customers = index.get_all("customer")
    multi_centroid = sum(1 for c in customers if len(c.centroids) > 1)
    return {
        "total_customers": len(customers),
        "multi_centroid_count": multi_centroid,
        "avg_centroids": round(
            sum(max(1, len(c.centroids)) for c in customers) / max(1, len(customers)), 1
        ),
    }


# =============================================================================
# Driver Assist — verify same driver across both weighments
# =============================================================================

_driver_sessions: dict[str, dict] = {}


@app.post("/face/driver/capture")
async def driver_capture(file: UploadFile = File(...), weighment_id: str = Form("")):
    """Capture driver face during a weighment. Stores embedding for later comparison."""
    if not weighment_id:
        raise HTTPException(400, "weighment_id required")

    engine = _models.get("face")
    if engine is None:
        raise HTTPException(503, "Face model not loaded")

    img = cv2.cvtColor(await _read_image(file), cv2.COLOR_RGB2BGR)
    emb, det_score, bbox, quality, _, is_live, num_faces = _extract_embedding(engine, img, quality_thresh=0.2)

    if emb is None:
        return {
            "captured": False,
            "reason": "no_face",
            "person_count": num_faces,
            "weighment_id": weighment_id,
        }

    _driver_sessions[weighment_id] = {
        "embedding": emb,
        "det_score": det_score,
        "bbox": bbox,
        "timestamp": time.time(),
        "person_count": num_faces,
    }

    # Cleanup old sessions (>24h)
    now = time.time()
    stale = [k for k, v in _driver_sessions.items() if now - v["timestamp"] > 86400]
    for k in stale:
        del _driver_sessions[k]

    return {
        "captured": True,
        "det_score": round(det_score, 3),
        "weighment_id": weighment_id,
    }


@app.post("/face/driver/verify")
async def driver_verify(
    file: UploadFile = File(...),
    first_weighment_id: str = Form(""),
    threshold: float = Form(0.50),
):
    """Verify that the driver on 2nd weighment matches the 1st weighment driver."""
    if not first_weighment_id:
        raise HTTPException(400, "first_weighment_id required")

    stored = _driver_sessions.get(first_weighment_id)
    if stored is None:
        return {
            "verified": False,
            "reason": "no_first_capture",
            "confidence": 0.0,
            "level": "unknown",
        }

    engine = _models.get("face")
    if engine is None:
        raise HTTPException(503, "Face model not loaded")

    img = cv2.cvtColor(await _read_image(file), cv2.COLOR_RGB2BGR)
    emb, det_score, _, _, _, _, num_faces = _extract_embedding(engine, img, quality_thresh=0.2)

    if emb is None:
        first_count = stored.get("person_count", 1)
        count_matches = num_faces == first_count
        return {
            "verified": False,
            "reason": "no_face_second",
            "confidence": 0.0,
            "level": "fallback_count",
            "person_count_first": first_count,
            "person_count_second": num_faces,
            "count_matches": count_matches,
        }

    stored_emb = stored["embedding"]
    similarity = float(np.dot(emb, stored_emb))

    if similarity >= threshold:
        level = "high" if similarity >= 0.55 else "medium"
        return {
            "verified": True,
            "confidence": round(similarity, 4),
            "level": level,
        }

    return {
        "verified": False,
        "reason": "driver_mismatch",
        "confidence": round(similarity, 4),
        "level": "mismatch",
    }


@app.get("/face/stats")
async def face_stats():
    """Get face index statistics."""
    index = get_face_index()
    return {
        "total_enrolled": index.total_enrolled,
        "operators": index.count("operator"),
        "customers": index.count("customer"),
        "driver_sessions": len(_driver_sessions),
        "faiss_available": True,
    }


@app.get("/models/status")
async def model_status():
    training_dir = TRAINING_DIR
    total_samples = 0
    if training_dir.exists():
        for feature_dir in training_dir.iterdir():
            if feature_dir.is_dir():
                total_samples += sum(1 for f in feature_dir.rglob("*.json"))

    models_info = {}
    for name in ["anpr", "material", "face"]:
        model_dir = MODEL_DIR / name
        version_file = model_dir / "version.txt"
        version = "0.0.0"
        if version_file.exists():
            version = version_file.read_text().strip()

        new_version_file = model_dir / "new_version.txt"
        update_available = new_version_file.exists()
        new_version = new_version_file.read_text().strip() if update_available else None

        models_info[name] = {
            "version": version,
            "accuracy": 0.0,
            "sample_count": sum(1 for f in (training_dir / name).rglob("*.json")) if (training_dir / name).exists() else 0,
            "update_available": update_available,
            "new_version": new_version,
        }

    last_retrained = None
    retrain_log = MODEL_DIR / "last_retrained.txt"
    if retrain_log.exists():
        last_retrained = retrain_log.read_text().strip()

    return {
        "models": models_info,
        "last_retrained": last_retrained,
        "total_samples": total_samples,
    }


@app.post("/models/update")
async def update_model(body: dict):
    model_name = body.get("model", "")
    if model_name not in ["anpr", "material", "face"]:
        raise HTTPException(400, f"Unknown model: {model_name}")

    if model_name == "anpr" and plate_detector is not None:
        reloaded = plate_detector.reload_if_updated()
        if reloaded:
            return {"status": "reloaded", "model": model_name, "file": plate_detector.model_name}

    new_version_file = MODEL_DIR / model_name / "new_version.txt"
    if not new_version_file.exists():
        raise HTTPException(404, "No update available for this model")

    new_version_file.unlink()
    return {"status": "updated", "model": model_name}


@app.post("/models/reload")
async def reload_model(body: dict):
    """Force hot-reload of a model from disk (after re-training or manual file replacement)."""
    model_name = body.get("model", "")
    if model_name == "anpr" and plate_detector is not None:
        if plate_detector.reload_if_updated():
            return {"status": "reloaded", "model": "anpr", "file": plate_detector.model_name}
        return {"status": "no_change", "model": "anpr"}
    raise HTTPException(400, f"Cannot reload: {model_name}")


# =============================================================================
# ANPR Plate Correction Reviewer (admin review before training data)
# =============================================================================

ANPR_REVIEW_DIR = Path.home() / ".weighbridge" / "anpr_review"


def _ensure_review_dir():
    (ANPR_REVIEW_DIR / "pending").mkdir(parents=True, exist_ok=True)
    (ANPR_REVIEW_DIR / "approved").mkdir(parents=True, exist_ok=True)
    (ANPR_REVIEW_DIR / "rejected").mkdir(parents=True, exist_ok=True)


@app.get("/anpr-reviewer")
async def anpr_reviewer_ui():
    """Serve the ANPR plate correction reviewer UI."""
    return FileResponse(str(STATIC_DIR / "anpr_reviewer.html"))


@app.get("/anpr-reviewer/stats")
async def anpr_reviewer_stats():
    """Get review queue statistics."""
    _ensure_review_dir()
    pending = sum(1 for _ in (ANPR_REVIEW_DIR / "pending").glob("*.json"))
    approved = sum(1 for _ in (ANPR_REVIEW_DIR / "approved").glob("*.json"))
    rejected = sum(1 for _ in (ANPR_REVIEW_DIR / "rejected").glob("*.json"))
    return {
        "pending": pending,
        "approved": approved,
        "rejected": rejected,
        "total": pending + approved + rejected,
    }


@app.get("/anpr-reviewer/pending")
async def anpr_reviewer_pending(filter: str = "pending", limit: int = 100):
    """Get items for review."""
    import json as _json

    _ensure_review_dir()
    target_dir = ANPR_REVIEW_DIR / filter if filter in ("pending", "approved", "rejected") else ANPR_REVIEW_DIR / "pending"

    items = []
    json_files = sorted(target_dir.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)

    for jf in json_files[:limit]:
        try:
            meta = _json.loads(jf.read_text())
            sample_id = jf.stem

            crop_b64 = ""
            crop_path = target_dir / f"{sample_id}.jpg"
            if crop_path.exists():
                crop_b64 = base64.b64encode(crop_path.read_bytes()).decode("ascii")

            items.append({
                "id": sample_id,
                "ocr_prediction": meta.get("ocr_prediction", ""),
                "correct_plate": meta.get("correct_plate", ""),
                "confidence": meta.get("confidence", 0.0),
                "timestamp": meta.get("timestamp", 0),
                "plate_crop_b64": crop_b64,
                "status": filter,
            })
        except Exception:
            continue

    return {"items": items}


@app.post("/anpr-reviewer/review")
async def anpr_reviewer_review(body: dict):
    """Admin reviews a correction: approve, edit, or reject."""
    import json as _json
    import shutil

    sample_id = body.get("sample_id", "")
    action = body.get("action", "")
    final_plate = body.get("final_plate", "")

    if not sample_id or action not in ("approve", "edit", "reject"):
        raise HTTPException(400, "sample_id and valid action (approve/edit/reject) required")

    _ensure_review_dir()
    pending_json = ANPR_REVIEW_DIR / "pending" / f"{sample_id}.json"
    pending_crop = ANPR_REVIEW_DIR / "pending" / f"{sample_id}.jpg"

    if not pending_json.exists():
        raise HTTPException(404, "Sample not found in pending queue")

    meta = _json.loads(pending_json.read_text())

    if action == "reject":
        dest_dir = ANPR_REVIEW_DIR / "rejected"
    else:
        dest_dir = ANPR_REVIEW_DIR / "approved"
        meta["approved_plate"] = final_plate
        meta["reviewed_at"] = time.time()
        meta["action"] = action

    # Move files
    dest_dir.mkdir(parents=True, exist_ok=True)
    (dest_dir / f"{sample_id}.json").write_text(_json.dumps(meta))
    if pending_crop.exists():
        shutil.move(str(pending_crop), str(dest_dir / f"{sample_id}.jpg"))
    pending_json.unlink()

    # If approved, also write to PARSeq training format (crop + label)
    if action in ("approve", "edit") and final_plate:
        train_dir = TRAINING_DIR / "anpr_ocr"
        train_dir.mkdir(parents=True, exist_ok=True)
        approved_crop = dest_dir / f"{sample_id}.jpg"
        if approved_crop.exists():
            shutil.copy2(str(approved_crop), str(train_dir / f"{sample_id}.jpg"))
        # gt.txt: one line per sample (path<tab>label)
        gt_file = train_dir / "gt.txt"
        with open(gt_file, "a") as f:
            f.write(f"{sample_id}.jpg\t{final_plate}\n")

    return {"status": action, "sample_id": sample_id}


@app.post("/anpr-reviewer/submit")
async def anpr_reviewer_submit(
    file: UploadFile = File(None),
    plate_crop_b64: str = Form(""),
    ocr_prediction: str = Form(""),
    correct_plate: str = Form(""),
    confidence: float = Form(0.0),
):
    """Submit a new correction to the pending review queue.
    Called from the Flutter app when operator corrects a plate."""
    import json as _json
    import uuid as _uuid

    _ensure_review_dir()
    sample_id = _uuid.uuid4().hex[:10]

    # Save crop image
    crop_path = ANPR_REVIEW_DIR / "pending" / f"{sample_id}.jpg"
    if file:
        data = await file.read()
        crop_path.write_bytes(data)
    elif plate_crop_b64:
        crop_path.write_bytes(base64.b64decode(plate_crop_b64))

    # Save metadata
    meta = {
        "ocr_prediction": ocr_prediction,
        "correct_plate": correct_plate,
        "confidence": confidence,
        "timestamp": time.time(),
    }
    (ANPR_REVIEW_DIR / "pending" / f"{sample_id}.json").write_text(_json.dumps(meta))

    return {"status": "queued", "sample_id": sample_id}


if __name__ == "__main__":
    port = int(os.environ.get("SIDECAR_PORT", "8765"))
    host = os.environ.get("SIDECAR_HOST", "0.0.0.0")
    uvicorn.run(app, host=host, port=port, log_level="info")
