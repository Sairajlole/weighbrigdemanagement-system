"""
Benchmark the ANPR pipeline end-to-end.
Generates synthetic test images and measures per-stage timings.

Usage: python scripts/benchmark.py [--frames 10]
"""

import argparse
import sys
import time
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).parent.parent))


def generate_test_frame(width: int = 1280, height: int = 720, has_plate: bool = True) -> np.ndarray:
    """Generate a synthetic frame with a plate-like region."""
    frame = np.random.randint(80, 180, (height, width, 3), dtype=np.uint8)
    frame = cv2.GaussianBlur(frame, (15, 15), 5)

    if has_plate:
        # Draw a plate-like rectangle with text-like texture
        px, py = width // 2 - 100, height // 2 + 50
        pw, ph = 200, 50
        cv2.rectangle(frame, (px, py), (px + pw, py + ph), (255, 255, 255), -1)
        cv2.rectangle(frame, (px, py), (px + pw, py + ph), (0, 0, 0), 2)
        # Add some text-like noise
        for i in range(8):
            x = px + 15 + i * 22
            cv2.rectangle(frame, (x, py + 10), (x + 15, py + 40), (0, 0, 0), -1)

    return frame


def benchmark_detection(detector, frames: list[np.ndarray]) -> list[float]:
    times = []
    for frame in frames:
        t0 = time.perf_counter()
        detector.detect(frame, conf_threshold=0.1, imgsz=640)
        times.append((time.perf_counter() - t0) * 1000)
    return times


def benchmark_preprocess(frames: list[np.ndarray]) -> list[float]:
    from anpr.preprocess import preprocess_plate
    times = []
    # Use a fixed crop size typical of a plate
    crop = np.random.randint(0, 255, (50, 200, 3), dtype=np.uint8)
    for _ in frames:
        t0 = time.perf_counter()
        preprocess_plate(crop)
        times.append((time.perf_counter() - t0) * 1000)
    return times


def benchmark_ocr(ocr_engine, n: int) -> list[float]:
    times = []
    crop = np.random.randint(100, 200, (64, 256, 3), dtype=np.uint8)
    for _ in range(n):
        t0 = time.perf_counter()
        ocr_engine.recognize(crop)
        times.append((time.perf_counter() - t0) * 1000)
    return times


def benchmark_validation(n: int) -> list[float]:
    from anpr.validators import validate_and_correct
    times = []
    test_strings = ['MH01AB1234', 'DL05CE9876', 'KA51MO2345', 'UP32GH4567', 'INVALID123']
    for i in range(n):
        t0 = time.perf_counter()
        validate_and_correct(test_strings[i % len(test_strings)])
        times.append((time.perf_counter() - t0) * 1000)
    return times


def stats(times: list[float]) -> dict:
    if not times:
        return {'mean': 0, 'min': 0, 'max': 0, 'p50': 0, 'p95': 0}
    s = sorted(times)
    return {
        'mean': sum(s) / len(s),
        'min': s[0],
        'max': s[-1],
        'p50': s[len(s) // 2],
        'p95': s[int(len(s) * 0.95)],
    }


def main():
    parser = argparse.ArgumentParser(description='Benchmark ANPR pipeline')
    parser.add_argument('--frames', type=int, default=10, help='Number of test frames')
    args = parser.parse_args()

    n = args.frames
    print(f"ANPR Pipeline Benchmark ({n} frames)")
    print("=" * 60)

    # Hardware info
    from main import _detect_hardware_tier
    tier, platform, cores = _detect_hardware_tier()
    print(f"Hardware: {tier} ({platform}, {cores} cores)")
    print()

    # Generate test frames
    frames = [generate_test_frame(has_plate=(i % 3 != 0)) for i in range(n)]

    # 1. Detection
    print("Loading models...")
    from anpr.detector import PlateDetector
    detector = PlateDetector()
    if detector.load():
        print(f"  Plate detector: {detector.model_name}")
        # Warmup
        detector.detect(frames[0], imgsz=640)
        det_times = benchmark_detection(detector, frames)
        s = stats(det_times)
        print(f"  Detection @640px: mean={s['mean']:.1f}ms, p50={s['p50']:.1f}ms, p95={s['p95']:.1f}ms")
    else:
        print("  Plate detector: NOT LOADED")
        det_times = []

    # 2. Preprocessing
    prep_times = benchmark_preprocess(frames)
    s = stats(prep_times)
    print(f"  Preprocess (3 variants): mean={s['mean']:.1f}ms, p50={s['p50']:.1f}ms, p95={s['p95']:.1f}ms")

    # 3. OCR
    from anpr.ocr import ParseqOCR
    ocr = ParseqOCR()
    if ocr.load():
        # Warmup
        crop = np.random.randint(100, 200, (64, 256, 3), dtype=np.uint8)
        ocr.recognize(crop)
        ocr_times = benchmark_ocr(ocr, n)
        s = stats(ocr_times)
        print(f"  OCR (PARSeq per crop): mean={s['mean']:.1f}ms, p50={s['p50']:.1f}ms, p95={s['p95']:.1f}ms")
        print(f"  OCR x3 variants: mean={s['mean']*3:.1f}ms")
    else:
        print("  OCR: NOT LOADED")
        ocr_times = []

    # 4. Validation
    val_times = benchmark_validation(n * 10)
    s = stats(val_times)
    print(f"  Validation: mean={s['mean']:.3f}ms (negligible)")

    # 5. Full pipeline estimate
    print()
    print("-" * 60)
    det_avg = sum(det_times) / len(det_times) if det_times else 0
    ocr_avg = sum(ocr_times) / len(ocr_times) if ocr_times else 0
    prep_avg = sum(prep_times) / len(prep_times) if prep_times else 0

    no_plate = det_avg
    with_plate = det_avg + prep_avg + ocr_avg * 3

    print(f"  Per frame (no plate):    {no_plate:.0f}ms")
    print(f"  Per frame (plate found): {with_plate:.0f}ms")
    print(f"  Effective FPS (no plate): {1000/no_plate:.1f}" if no_plate > 0 else "")
    print(f"  Effective FPS (plate):    {1000/with_plate:.1f}" if with_plate > 0 else "")
    print()

    # 6. Consensus estimate
    scan_interval = max(200, det_avg * 1.2)
    frames_to_lock = 5  # typical: 3 matching out of 5 attempts
    consensus_time = scan_interval * frames_to_lock / 1000
    print(f"  Recommended scan interval: {scan_interval:.0f}ms")
    print(f"  Estimated consensus time:  {consensus_time:.1f}s (best case)")
    print(f"  Worst case (15 frames):    {scan_interval * 15 / 1000:.1f}s")
    print()
    print("=" * 60)


if __name__ == "__main__":
    main()
