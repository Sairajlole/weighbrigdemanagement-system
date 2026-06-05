"""
Image preprocessing for Indian number plates.
Produces multiple variants for OCR — original, CLAHE-enhanced, and binarized.
"""

import cv2
import numpy as np


def resize_to_height(img: np.ndarray, target_height: int = 64) -> np.ndarray:
    h, w = img.shape[:2]
    if h == 0:
        return img
    scale = target_height / h
    new_w = max(1, int(w * scale))
    return cv2.resize(img, (new_w, target_height), interpolation=cv2.INTER_CUBIC)


def apply_clahe(img: np.ndarray) -> np.ndarray:
    if len(img.shape) == 3:
        lab = cv2.cvtColor(img, cv2.COLOR_RGB2LAB)
        l_channel = lab[:, :, 0]
    else:
        l_channel = img

    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(l_channel)

    if len(img.shape) == 3:
        lab[:, :, 0] = enhanced
        return cv2.cvtColor(lab, cv2.COLOR_LAB2RGB)
    return enhanced


def deskew(img: np.ndarray) -> np.ndarray:
    if len(img.shape) == 3:
        gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
    else:
        gray = img

    edges = cv2.Canny(gray, 50, 150, apertureSize=3)
    lines = cv2.HoughLinesP(edges, 1, np.pi / 180, threshold=30, minLineLength=20, maxLineGap=10)

    if lines is None or len(lines) == 0:
        return img

    angles = []
    for line in lines:
        x1, y1, x2, y2 = line[0]
        dx = x2 - x1
        dy = y2 - y1
        if abs(dx) > 0:
            angle = np.degrees(np.arctan2(dy, dx))
            if abs(angle) < 30:
                angles.append(angle)

    if not angles:
        return img

    median_angle = np.median(angles)
    if abs(median_angle) < 0.5:
        return img

    h, w = img.shape[:2]
    center = (w // 2, h // 2)
    matrix = cv2.getRotationMatrix2D(center, median_angle, 1.0)
    rotated = cv2.warpAffine(img, matrix, (w, h), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REPLICATE)
    return rotated


def binarize(img: np.ndarray) -> np.ndarray:
    if len(img.shape) == 3:
        gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
    else:
        gray = img.copy()

    # Sharpen before binarization to preserve Indian plate font edges
    sharpened = cv2.filter2D(gray, -1, np.array([[-1,-1,-1],[-1,9,-1],[-1,-1,-1]]) / 5.0)
    blurred = cv2.GaussianBlur(sharpened, (3, 3), 0)

    # Otsu for clean plates, adaptive for uneven lighting
    _, otsu = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    adaptive = cv2.adaptiveThreshold(
        blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 15, 4
    )

    # Use Otsu if it produces reasonable white/black ratio (30-70% white)
    white_ratio = np.sum(otsu > 127) / otsu.size
    binary = otsu if 0.3 < white_ratio < 0.7 else adaptive

    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (2, 2))
    binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)
    return binary


def compute_sharpness(img: np.ndarray) -> float:
    if len(img.shape) == 3:
        gray = cv2.cvtColor(img, cv2.COLOR_RGB2GRAY)
    else:
        gray = img
    return float(cv2.Laplacian(gray, cv2.CV_64F).var())


def trim_plate_border(crop: np.ndarray, margin_pct: float = 0.05) -> np.ndarray:
    """Trim plate border/screws that confuse OCR — removes outer margin."""
    h, w = crop.shape[:2]
    mx = int(w * margin_pct)
    my = int(h * margin_pct)
    if mx < 1 and my < 1:
        return crop
    trimmed = crop[my:h-my, mx:w-mx]
    if trimmed.size == 0:
        return crop
    return trimmed


def preprocess_plate(crop: np.ndarray) -> list[np.ndarray]:
    """
    Returns multiple preprocessing variants of a plate crop for OCR.
    Each variant targets different plate conditions (faded, low contrast, handwritten).
    """
    if crop.size == 0:
        return []

    # Trim plate border (screws, frame edges confuse OCR)
    crop = trim_plate_border(crop)
    resized = resize_to_height(crop, target_height=64)
    deskewed = deskew(resized)

    original = deskewed
    clahe_enhanced = apply_clahe(deskewed)
    binary = binarize(deskewed)
    binary_3ch = cv2.cvtColor(binary, cv2.COLOR_GRAY2RGB)

    return [original, clahe_enhanced, binary_3ch]
