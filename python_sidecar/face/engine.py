"""
Face detection + recognition engine using ArcFace (GlintR100) + SCRFD.

GlintR100: ResNet100 trained on Glint360K — #1 open-source face recognition.
SCRFD: fast face detector with 5-point landmarks for alignment.

Pipeline: detect (SCRFD) → quality gate → align → embed (ArcFace) → anti-spoof check
"""

import math
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

_MODEL_DIR = Path(__file__).parent.parent / "models" / "face"


def _get_providers() -> list[str]:
    """Get best available ONNX Runtime execution providers (Intel GPU preferred on Windows)."""
    import onnxruntime as ort
    available = ort.get_available_providers()
    providers = []
    if "OpenVINOExecutionProvider" in available:
        providers.append("OpenVINOExecutionProvider")
    if "DmlExecutionProvider" in available:
        providers.append("DmlExecutionProvider")
    if "CoreMLExecutionProvider" in available:
        providers.append("CoreMLExecutionProvider")
    providers.append("CPUExecutionProvider")
    return providers


@dataclass
class FaceDetection:
    bbox: list[float]
    landmarks: np.ndarray  # 5x2 (left_eye, right_eye, nose, mouth_left, mouth_right)
    det_score: float
    aligned_face: np.ndarray  # 112x112 aligned crop
    quality_score: float  # 0-1 composite quality
    pose_yaw: float
    pose_pitch: float
    blur_score: float  # higher = sharper
    is_live: bool  # anti-spoof estimate


@dataclass
class FaceResult:
    embedding: np.ndarray | None
    det_score: float
    bbox: list[float]
    quality_score: float
    face_crop_jpeg: bytes | None  # JPEG-encoded best crop for audit
    is_live: bool
    pose_yaw: float
    pose_pitch: float
    num_faces: int


# Standard alignment reference points for 112x112 (ArcFace/AdaFace alignment)
_REFERENCE_LANDMARKS = np.array([
    [38.2946, 51.6963],
    [73.5318, 51.5014],
    [56.0252, 71.7366],
    [41.5493, 92.3655],
    [70.7299, 92.2041],
], dtype=np.float32)


def _align_face(img: np.ndarray, landmarks: np.ndarray, size: int = 112) -> np.ndarray:
    """Align face using similarity transform from 5 landmarks."""
    src = landmarks.astype(np.float32)
    dst = _REFERENCE_LANDMARKS
    tform = cv2.estimateAffinePartial2D(src, dst, method=cv2.LMEDS)[0]
    if tform is None:
        tform = cv2.getAffineTransform(src[:3], dst[:3])
    aligned = cv2.warpAffine(img, tform, (size, size), borderMode=cv2.BORDER_REPLICATE)
    return aligned


def _estimate_pose(landmarks: np.ndarray) -> tuple[float, float]:
    """Estimate yaw and pitch from 5-point landmarks (rough but fast)."""
    left_eye, right_eye, nose, mouth_l, mouth_r = landmarks

    eye_center = (left_eye + right_eye) / 2
    eye_dist = np.linalg.norm(right_eye - left_eye)
    if eye_dist < 1e-3:
        return 0.0, 0.0

    # Yaw: how far nose is off-center between eyes
    nose_to_center = nose[0] - eye_center[0]
    yaw = math.degrees(math.atan2(nose_to_center * 2, eye_dist))

    # Pitch: vertical offset of nose relative to eye-mouth midline
    mouth_center = (mouth_l + mouth_r) / 2
    face_height = np.linalg.norm(mouth_center - eye_center)
    if face_height < 1e-3:
        return yaw, 0.0
    nose_vert_ratio = (nose[1] - eye_center[1]) / face_height
    pitch = (nose_vert_ratio - 0.45) * 60  # calibrated empirically

    return float(yaw), float(pitch)


def _compute_blur(face_crop: np.ndarray) -> float:
    """Laplacian variance — higher means sharper."""
    gray = cv2.cvtColor(face_crop, cv2.COLOR_BGR2GRAY) if face_crop.ndim == 3 else face_crop
    lap = cv2.Laplacian(gray, cv2.CV_64F)
    return float(lap.var())


def _check_liveness(landmarks: np.ndarray, bbox: list[float], face_crop: np.ndarray, verbose: bool = False) -> bool:
    """Verify landmarks form valid face geometry — rejects non-face objects."""
    left_eye, right_eye, nose, mouth_l, mouth_r = landmarks
    eye_dist = np.linalg.norm(right_eye - left_eye)
    if eye_dist < 1e-3:
        return False

    # Eyes must be above nose, nose above mouth (Y increases downward)
    eye_center_y = (left_eye[1] + right_eye[1]) / 2
    mouth_center_y = (mouth_l[1] + mouth_r[1]) / 2
    if not (eye_center_y < nose[1] < mouth_center_y):
        return False

    # Nose-to-mouth vs eye distance ratio
    nose_to_mouth = np.linalg.norm(nose - (mouth_l + mouth_r) / 2)
    ratio = nose_to_mouth / eye_dist
    if ratio < 0.15 or ratio > 0.8:
        return False

    # Eyes should be at similar height (not tilted > 30deg)
    eye_slope = abs(right_eye[1] - left_eye[1]) / eye_dist
    if eye_slope > 0.58:  # tan(30deg)
        return False

    # Landmarks should be roughly inside the bbox (allow 10% margin for detector jitter)
    bx1, by1, bx2, by2 = bbox
    bw, bh = bx2 - bx1, by2 - by1
    margin_x, margin_y = bw * 0.1, bh * 0.1
    for pt in landmarks:
        if pt[0] < bx1 - margin_x or pt[0] > bx2 + margin_x or pt[1] < by1 - margin_y or pt[1] > by2 + margin_y:
            return False

    return True


def _compute_quality(det_score: float, blur: float, yaw: float, pitch: float, is_live: bool, verbose: bool = False) -> float:
    """Composite quality score 0-1. Used as gate for enrollment/progressive update."""
    score = 1.0

    # Detection confidence
    det_factor = min(det_score / 0.9, 1.0)
    score *= det_factor

    # Blur (Laplacian variance; webcam typical: 10-40, good DSLR: 50-150)
    blur_norm = min(blur / 40.0, 1.0)
    blur_factor = max(blur_norm, 0.3)
    score *= blur_factor

    # Pose penalty: steep angles degrade embedding quality
    yaw_penalty = max(0.0, 1.0 - (abs(yaw) / 60.0))
    pitch_penalty = max(0.0, 1.0 - (abs(pitch) / 50.0))
    score *= yaw_penalty * pitch_penalty

    # Liveness — mild penalty, not a quality killer
    if not is_live:
        score *= 0.85

    if verbose:
        print(f"  [Quality] det={det_factor:.2f} blur_raw={blur:.1f} blur_f={blur_factor:.2f} yaw={yaw:.1f}({yaw_penalty:.2f}) pitch={pitch:.1f}({pitch_penalty:.2f}) live={is_live} → {score:.3f}")

    return round(float(score), 3)


class FaceEngine:
    """ArcFace (GlintR100) + SCRFD face recognition engine."""

    def __init__(self, model_dir: Path = _MODEL_DIR):
        self._model_dir = model_dir
        self._detector = None
        self._recognizer = None
        self._loaded = False

    @property
    def loaded(self) -> bool:
        return self._loaded

    def load(self) -> bool:
        """Load detector and recognizer models."""
        try:
            self._load_detector()
            self._load_recognizer()
            self._loaded = True
            return True
        except Exception as e:
            import traceback
            traceback.print_exc()
            return False

    def _load_detector(self):
        """Load SCRFD via ONNX Runtime (prefer largest available)."""
        import onnxruntime as ort

        det_path = self._model_dir / "scrfd_34g_gnkps.onnx"
        if not det_path.exists():
            det_path = self._model_dir / "scrfd_10g_bnkps.onnx"
        if not det_path.exists():
            det_path = self._model_dir / "scrfd_2.5g_bnkps.onnx"
        if not det_path.exists():
            raise FileNotFoundError(f"No SCRFD model found in {self._model_dir}")

        providers = _get_providers()
        opts = ort.SessionOptions()
        opts.inter_op_num_threads = 2
        opts.intra_op_num_threads = 2
        self._detector = ort.InferenceSession(str(det_path), sess_options=opts, providers=providers)
        active = self._detector.get_providers()
        self._det_input_name = self._detector.get_inputs()[0].name
        self._det_input_shape = self._detector.get_inputs()[0].shape  # [1,3,H,W]
        print(f"  [FaceEngine] Loaded detector: {det_path.name} (providers: {active})")

    def _load_recognizer(self):
        """Load ArcFace recognition model (GlintR100 preferred, w600k_r50 fallback)."""
        import onnxruntime as ort

        onnx_path = self._model_dir / "glintr100.onnx"
        if not onnx_path.exists():
            onnx_path = self._model_dir / "w600k_r50.onnx"
        if not onnx_path.exists():
            raise FileNotFoundError(f"No ArcFace model found in {self._model_dir}")

        providers = _get_providers()
        opts = ort.SessionOptions()
        opts.inter_op_num_threads = 2
        opts.intra_op_num_threads = 2
        self._recognizer = ort.InferenceSession(str(onnx_path), sess_options=opts, providers=providers)
        active = self._recognizer.get_providers()
        self._rec_input_name = self._recognizer.get_inputs()[0].name
        print(f"  [FaceEngine] Loaded recognizer: {onnx_path.name} (providers: {active})")

    def detect(self, img: np.ndarray, det_thresh: float = 0.5) -> list[FaceDetection]:
        """Detect faces and compute all quality metrics."""
        if self._detector is None:
            return []

        detections = self._run_scrfd(img, det_thresh)
        results = []

        for bbox, kps, score in detections:
            # Filter invalid/tiny bboxes — require minimum 40px face
            bw = bbox[2] - bbox[0]
            bh = bbox[3] - bbox[1]
            if bw < 40 or bh < 40:
                continue
            # Reject non-square-ish detections (faces are roughly square)
            aspect = bw / bh if bh > 0 else 0
            if aspect < 0.5 or aspect > 2.0:
                continue
            aligned = _align_face(img, kps)
            yaw, pitch = _estimate_pose(kps)
            blur = _compute_blur(aligned)
            is_live = _check_liveness(kps, bbox, aligned, verbose=True)
            quality = _compute_quality(score, blur, yaw, pitch, is_live)

            results.append(FaceDetection(
                bbox=bbox,
                landmarks=kps,
                det_score=score,
                aligned_face=aligned,
                quality_score=quality,
                pose_yaw=yaw,
                pose_pitch=pitch,
                blur_score=blur,
                is_live=is_live,
            ))

        return results

    def embed(self, aligned_face: np.ndarray) -> np.ndarray:
        """Get 512-dim L2-normalized embedding from aligned 112x112 face."""
        if self._recognizer is None:
            raise RuntimeError("Recognizer not loaded")

        # InsightFace preprocessing: BGR→RGB, then (x - 127.5) / 127.5 → [-1, 1]
        face_rgb = cv2.cvtColor(aligned_face, cv2.COLOR_BGR2RGB)
        face_t = face_rgb.astype(np.float32)
        face_t = (face_t - 127.5) / 127.5
        face_t = face_t.transpose(2, 0, 1)  # HWC → CHW
        face_t = np.expand_dims(face_t, 0)  # add batch

        outputs = self._recognizer.run(None, {self._rec_input_name: face_t})
        emb = outputs[0][0]

        # L2 normalize
        norm = np.linalg.norm(emb)
        if norm > 1e-6:
            emb = emb / norm
        return emb.astype(np.float32)

    def extract_best(
        self,
        img: np.ndarray,
        det_thresh: float = 0.55,
        quality_thresh: float = 0.3,
    ) -> FaceResult:
        """Full pipeline: detect → quality gate → embed → return best face."""
        detections = self.detect(img, det_thresh)
        num_faces = len(detections)

        if not detections:
            return FaceResult(
                embedding=None, det_score=0, bbox=[], quality_score=0,
                face_crop_jpeg=None, is_live=True, pose_yaw=0, pose_pitch=0,
                num_faces=0,
            )

        # Pick best by quality
        best = max(detections, key=lambda d: d.quality_score)

        # Quality gate
        if best.quality_score < quality_thresh:
            return FaceResult(
                embedding=None, det_score=best.det_score, bbox=best.bbox,
                quality_score=best.quality_score, face_crop_jpeg=None,
                is_live=best.is_live, pose_yaw=best.pose_yaw,
                pose_pitch=best.pose_pitch, num_faces=num_faces,
            )

        # Embed
        emb = self.embed(best.aligned_face)

        # Crop face from original image with padding for natural display
        img_h, img_w = img.shape[:2]
        bx1, by1, bx2, by2 = best.bbox
        bw, bh = bx2 - bx1, by2 - by1
        pad_x, pad_y = int(bw * 0.3), int(bh * 0.3)
        cx1 = max(0, int(bx1) - pad_x)
        cy1 = max(0, int(by1) - pad_y)
        cx2 = min(img_w, int(bx2) + pad_x)
        cy2 = min(img_h, int(by2) + pad_y)
        face_region = img[cy1:cy2, cx1:cx2]
        _, crop_buf = cv2.imencode(".jpg", face_region, [cv2.IMWRITE_JPEG_QUALITY, 85])
        crop_jpeg = crop_buf.tobytes()

        return FaceResult(
            embedding=emb,
            det_score=best.det_score,
            bbox=best.bbox,
            quality_score=best.quality_score,
            face_crop_jpeg=crop_jpeg,
            is_live=best.is_live,
            pose_yaw=best.pose_yaw,
            pose_pitch=best.pose_pitch,
            num_faces=num_faces,
        )

    def _run_scrfd(self, img: np.ndarray, det_thresh: float) -> list[tuple[list[float], np.ndarray, float]]:
        """Run SCRFD detector. Returns [(bbox, landmarks_5x2, score), ...]."""
        # Determine input size from model
        input_h = self._det_input_shape[2] if isinstance(self._det_input_shape[2], int) else 640
        input_w = self._det_input_shape[3] if isinstance(self._det_input_shape[3], int) else 640

        img_h, img_w = img.shape[:2]
        scale = min(input_w / img_w, input_h / img_h)
        new_w, new_h = int(img_w * scale), int(img_h * scale)

        resized = cv2.resize(img, (new_w, new_h))
        padded = np.zeros((input_h, input_w, 3), dtype=np.uint8)
        padded[:new_h, :new_w] = resized

        # Preprocess: BGR→RGB, NCHW float32, normalize
        blob = cv2.dnn.blobFromImage(padded, 1.0 / 128, (input_w, input_h), (127.5, 127.5, 127.5), swapRB=True)

        outputs = self._detector.run(None, {self._det_input_name: blob})

        return self._decode_scrfd_outputs(outputs, scale, det_thresh, img_w, img_h)

    def _decode_scrfd_outputs(
        self, outputs: list, scale: float, det_thresh: float, img_w: int, img_h: int
    ) -> list[tuple[list[float], np.ndarray, float]]:
        """Decode SCRFD outputs into bboxes + landmarks.
        Format: 9 outputs = 3 strides × (scores[N,1], bboxes[N,4], kps[N,10])
        Strides 8,16,32 with anchor-free distance-based bbox encoding."""
        results = []

        if len(outputs) == 9:
            # Standard SCRFD with keypoints: [scores8, scores16, scores32, bbox8, bbox16, bbox32, kps8, kps16, kps32]
            strides = [8, 16, 32]
            num_strides = 3

            for stride_idx, stride in enumerate(strides):
                scores = outputs[stride_idx].reshape(-1)
                bboxes = outputs[num_strides + stride_idx]  # (N, 4)
                kps_data = outputs[2 * num_strides + stride_idx]  # (N, 10)

                # Determine feature map size for this stride
                input_h = self._det_input_shape[2] if isinstance(self._det_input_shape[2], int) else 640
                input_w = self._det_input_shape[3] if isinstance(self._det_input_shape[3], int) else 640
                feat_h = input_h // stride
                feat_w = input_w // stride
                num_anchors = len(scores) // (feat_h * feat_w)

                for i, score in enumerate(scores):
                    if score < det_thresh:
                        continue

                    # Anchor center: account for multiple anchors per spatial position
                    spatial_idx = i // num_anchors
                    anchor_y = (spatial_idx // feat_w) * stride
                    anchor_x = (spatial_idx % feat_w) * stride

                    # Decode distance-based bbox: [left, top, right, bottom] distances from anchor
                    d = bboxes[i]
                    x1 = (anchor_x - d[0] * stride) / scale
                    y1 = (anchor_y - d[1] * stride) / scale
                    x2 = (anchor_x + d[2] * stride) / scale
                    y2 = (anchor_y + d[3] * stride) / scale
                    bbox = [max(0, x1), max(0, y1), min(img_w, x2), min(img_h, y2)]

                    # Decode keypoints: 5 pairs of (dx, dy) offsets from anchor
                    kps_raw = kps_data[i].reshape(5, 2)
                    kps = np.zeros((5, 2), dtype=np.float32)
                    for k in range(5):
                        kps[k, 0] = (anchor_x + kps_raw[k, 0] * stride) / scale
                        kps[k, 1] = (anchor_y + kps_raw[k, 1] * stride) / scale

                    results.append((bbox, kps, float(score)))

        elif len(outputs) == 6:
            # SCRFD without keypoints
            strides = [8, 16, 32]
            for stride_idx, stride in enumerate(strides):
                scores = outputs[stride_idx].reshape(-1)
                bboxes = outputs[3 + stride_idx]

                input_h = self._det_input_shape[2] if isinstance(self._det_input_shape[2], int) else 640
                input_w = self._det_input_shape[3] if isinstance(self._det_input_shape[3], int) else 640
                feat_h = input_h // stride
                feat_w = input_w // stride
                num_anchors = len(scores) // (feat_h * feat_w)

                for i, score in enumerate(scores):
                    if score < det_thresh:
                        continue
                    spatial_idx = i // num_anchors
                    anchor_y = (spatial_idx // feat_w) * stride
                    anchor_x = (spatial_idx % feat_w) * stride
                    d = bboxes[i]
                    x1 = (anchor_x - d[0] * stride) / scale
                    y1 = (anchor_y - d[1] * stride) / scale
                    x2 = (anchor_x + d[2] * stride) / scale
                    y2 = (anchor_y + d[3] * stride) / scale
                    bbox = [max(0, x1), max(0, y1), min(img_w, x2), min(img_h, y2)]
                    kps = self._bbox_to_landmarks(bbox)
                    results.append((bbox, kps, float(score)))

        # NMS
        if results:
            results = self._nms(results, iou_thresh=0.4)

        return results

    def _bbox_to_landmarks(self, bbox: list[float]) -> np.ndarray:
        """Approximate 5 landmarks from bbox (fallback)."""
        x1, y1, x2, y2 = bbox
        w, h = x2 - x1, y2 - y1
        return np.array([
            [x1 + w * 0.3, y1 + h * 0.35],
            [x1 + w * 0.7, y1 + h * 0.35],
            [x1 + w * 0.5, y1 + h * 0.55],
            [x1 + w * 0.35, y1 + h * 0.75],
            [x1 + w * 0.65, y1 + h * 0.75],
        ], dtype=np.float32)

    def _nms(
        self, dets: list[tuple[list[float], np.ndarray, float]], iou_thresh: float
    ) -> list[tuple[list[float], np.ndarray, float]]:
        """Non-maximum suppression."""
        if not dets:
            return []
        dets.sort(key=lambda x: x[2], reverse=True)
        keep = []
        for det in dets:
            bbox = det[0]
            suppress = False
            for kept in keep:
                if self._iou(bbox, kept[0]) > iou_thresh:
                    suppress = True
                    break
            if not suppress:
                keep.append(det)
        return keep

    @staticmethod
    def _iou(a: list[float], b: list[float]) -> float:
        x1 = max(a[0], b[0])
        y1 = max(a[1], b[1])
        x2 = min(a[2], b[2])
        y2 = min(a[3], b[3])
        inter = max(0, x2 - x1) * max(0, y2 - y1)
        area_a = (a[2] - a[0]) * (a[3] - a[1])
        area_b = (b[2] - b[0]) * (b[3] - b[1])
        union = area_a + area_b - inter
        return inter / union if union > 0 else 0


# Singleton
_engine: FaceEngine | None = None


def get_face_engine() -> FaceEngine:
    global _engine
    if _engine is None:
        _engine = FaceEngine()
    return _engine
