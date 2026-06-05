"""
Generate synthetic Indian license plate crops for OCR training.

Produces 50K+ plate images with known text labels in LMDB format
(compatible with PARSeq/STR training pipeline).

Incorporates realistic commercial vehicle plate characteristics:
- Double-line plate formats (55% of commercial vehicles)
- Hand-painted font variation (65-75% of trucks still non-HSRP)
- Degradation: mud, fading, peeling paint, rust stains
- Yellow plates (commercial), white (private/tractor), green (EV)
- State code weighting by truck traffic volume
- "T" prefix series for transport vehicles (UP/Bihar)

Run: python scripts/generate_synthetic_plates.py --count 50000
Output: datasets/indian_plates_lmdb/train/ and datasets/indian_plates_lmdb/val/
"""

import argparse
import io
import math
import random
import string
import sys
from pathlib import Path

import cv2
import lmdb
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# Indian state codes weighted by truck traffic volume
# Higher weight = more likely to appear (reflects weighbridge reality)
STATE_CODES_WEIGHTED = {
    "MH": 12, "GJ": 11, "RJ": 10, "UP": 10, "MP": 9, "KA": 8,
    "TN": 8, "AP": 7, "TS": 7, "HR": 7, "PB": 6, "DL": 6,
    "WB": 5, "BR": 5, "CG": 5, "JH": 4, "OD": 4, "UK": 3,
    "HP": 3, "JK": 2, "AS": 2, "GA": 2, "KL": 2, "TR": 1,
    "MN": 1, "ML": 1, "MZ": 1, "NL": 1, "SK": 1, "AR": 1,
    "AN": 1, "CH": 2, "DD": 1, "DN": 1, "LD": 1, "PY": 1, "LA": 1,
}

STATE_CODES = list(STATE_CODES_WEIGHTED.keys())
STATE_WEIGHTS = list(STATE_CODES_WEIGHTED.values())

LETTER_POOL = "ABCDEFGHJKLMNPRSTUVWXYZ"

# Font paths to try — varied styles simulate hand-painted plates
FONT_PATHS_MONO = [
    "/System/Library/Fonts/Courier.dfont",
    "/System/Library/Fonts/Menlo.ttc",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationMono-Bold.ttf",
]

FONT_PATHS_SANS = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/SFCompact.ttf",
    "/Library/Fonts/Arial Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]

FONT_PATHS_SERIF = [
    "/System/Library/Fonts/Times.ttc",
    "/Library/Fonts/Georgia Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
]


def _pick_font(font_size: int, style: str = "random") -> ImageFont.FreeTypeFont:
    """Pick a font, varying style to simulate hand-painted plates."""
    if style == "mono":
        paths = FONT_PATHS_MONO
    elif style == "sans":
        paths = FONT_PATHS_SANS
    elif style == "serif":
        paths = FONT_PATHS_SERIF
    else:
        paths = random.choice([FONT_PATHS_MONO, FONT_PATHS_SANS, FONT_PATHS_SERIF])

    for p in paths:
        try:
            return ImageFont.truetype(p, font_size)
        except (OSError, IOError):
            continue
    return ImageFont.load_default()


def weighted_state() -> str:
    return random.choices(STATE_CODES, weights=STATE_WEIGHTS, k=1)[0]


def random_standard_plate() -> str:
    """SS DD LL DDDD"""
    state = weighted_state()
    district = f"{random.randint(1, 99):02d}"
    letters = random.choice(LETTER_POOL) + random.choice(LETTER_POOL)
    number = f"{random.randint(1, 9999):04d}"
    return f"{state}{district}{letters}{number}"


def random_commercial_plate() -> str:
    """SS DD T L DDDD — transport series (common in UP/Bihar)"""
    state = random.choices(
        ["UP", "BR", "JH", "MP", "CG", "RJ", "MH", "GJ"],
        weights=[25, 20, 10, 10, 8, 8, 10, 9], k=1
    )[0]
    district = f"{random.randint(1, 99):02d}"
    letter = random.choice(LETTER_POOL)
    number = f"{random.randint(1, 9999):04d}"
    return f"{state}{district}T{letter}{number}"


def random_single_letter_plate() -> str:
    """SS DD L DDDD"""
    state = weighted_state()
    district = f"{random.randint(1, 99):02d}"
    letter = random.choice(LETTER_POOL)
    number = f"{random.randint(1, 9999):04d}"
    return f"{state}{district}{letter}{number}"


def random_bharat_plate() -> str:
    """BH series: YY BH NNNN LL"""
    year = random.randint(20, 26)
    number = f"{random.randint(1, 9999):04d}"
    letters = random.choice(LETTER_POOL) + random.choice(LETTER_POOL)
    return f"{year}BH{number}{letters}"


def random_tractor_plate() -> str:
    """Tractor plates: shorter numbers, often SS DD LDDDD or SS DD LLL DDDD"""
    state = random.choices(
        ["MH", "UP", "MP", "RJ", "PB", "HR", "GJ", "KA"],
        weights=[15, 15, 12, 12, 10, 10, 13, 13], k=1
    )[0]
    district = f"{random.randint(1, 50):02d}"
    if random.random() < 0.5:
        letter = random.choice(LETTER_POOL)
        number = f"{random.randint(1, 9999):04d}"
        return f"{state}{district}{letter}{number}"
    else:
        letters = random.choice(LETTER_POOL) + random.choice(LETTER_POOL)
        number = f"{random.randint(1, 999):03d}"
        return f"{state}{district}{letters}{number}"


def generate_plate_text() -> tuple[str, str, str]:
    """Generate random plate text, type, and layout style.

    Returns: (text, plate_type, layout)
    plate_type: "commercial", "standard", "tractor", "bharat"
    layout: "single_line", "double_line"
    """
    r = random.random()
    if r < 0.35:
        text = random_standard_plate()
        plate_type = "standard"
        layout = "double_line" if random.random() < 0.15 else "single_line"
    elif r < 0.60:
        text = random_commercial_plate()
        plate_type = "commercial"
        layout = "double_line" if random.random() < 0.55 else "single_line"
    elif r < 0.75:
        text = random_single_letter_plate()
        plate_type = "standard"
        layout = "double_line" if random.random() < 0.20 else "single_line"
    elif r < 0.88:
        text = random_tractor_plate()
        plate_type = "tractor"
        layout = "double_line" if random.random() < 0.40 else "single_line"
    else:
        text = random_bharat_plate()
        plate_type = "bharat"
        layout = "single_line"
    return text, plate_type, layout


def get_plate_colors(plate_type: str) -> tuple[tuple, tuple]:
    """Return (bg_color, text_color) based on plate type."""
    if plate_type == "commercial":
        # Yellow background — varies from bright to aged/faded
        if random.random() < 0.3:
            # Aged/dirty yellow
            bg = (random.randint(170, 210), random.randint(150, 180), random.randint(20, 70))
        else:
            bg = (random.randint(210, 255), random.randint(190, 230), random.randint(0, 40))
        text = (random.randint(0, 40), random.randint(0, 40), random.randint(0, 40))
    elif plate_type == "tractor":
        # White plate (agricultural/private)
        bg = (random.randint(210, 250), random.randint(210, 250), random.randint(210, 250))
        text = (random.randint(0, 40), random.randint(0, 40), random.randint(0, 40))
    elif random.random() < 0.04:
        # Green EV plate (rare)
        bg = (random.randint(0, 40), random.randint(100, 160), random.randint(0, 60))
        text = (random.randint(220, 255), random.randint(220, 255), random.randint(220, 255))
    else:
        # White private plate
        bg = (random.randint(215, 255), random.randint(215, 255), random.randint(215, 255))
        text = (random.randint(0, 45), random.randint(0, 45), random.randint(0, 45))
    return bg, text


def _split_for_double_line(text: str) -> tuple[str, str]:
    """Split plate text into top/bottom lines for double-line format.

    Standard: top=SSDD, bottom=LLDDDD
    Commercial: top=SSDD, bottom=TLDDDD
    """
    if len(text) >= 8:
        return text[:4], text[4:]
    return text[:len(text)//2], text[len(text)//2:]


def _render_char_by_char(draw: ImageDraw.Draw, text: str, x_start: int, y: int,
                          font: ImageFont.FreeTypeFont, text_color: tuple,
                          hand_painted: bool) -> None:
    """Render text character-by-character with optional hand-painted jitter."""
    x = x_start
    for ch in text:
        if hand_painted:
            dy = random.randint(-2, 2)
            dx_extra = random.randint(-1, 2)
        else:
            dy = 0
            dx_extra = 0

        draw.text((x + dx_extra, y + dy), ch, fill=text_color, font=font)
        bbox = draw.textbbox((0, 0), ch, font=font)
        char_w = bbox[2] - bbox[0]

        if hand_painted:
            kerning = random.randint(-1, 4)
        else:
            kerning = random.randint(0, 2)
        x += char_w + kerning


def _get_text_width_charwise(draw: ImageDraw.Draw, text: str, font: ImageFont.FreeTypeFont,
                              hand_painted: bool) -> int:
    """Estimate width when rendering char-by-char."""
    w = 0
    for ch in text:
        bbox = draw.textbbox((0, 0), ch, font=font)
        char_w = bbox[2] - bbox[0]
        avg_kern = 2 if hand_painted else 1
        w += char_w + avg_kern
    return w


def render_plate(text: str, plate_type: str, layout: str,
                 width: int = 300, height: int = 80) -> np.ndarray:
    """Render a synthetic plate image with realistic characteristics."""
    bg_color, text_color = get_plate_colors(plate_type)

    # Hand-painted: ~65% of commercial, ~40% of tractors, ~20% of standard
    hand_painted_prob = {"commercial": 0.65, "tractor": 0.40, "standard": 0.20, "bharat": 0.05}
    hand_painted = random.random() < hand_painted_prob.get(plate_type, 0.2)

    # Double-line plates are taller
    if layout == "double_line":
        height = random.randint(90, 130)
        width = random.randint(200, 280)
    else:
        height = random.randint(60, 90)
        width = random.randint(260, 340)

    img = Image.new("RGB", (width, height), bg_color)
    draw = ImageDraw.Draw(img)

    # Font selection
    if hand_painted:
        font_style = random.choice(["sans", "serif", "mono"])
        font_size_base = int(height * (0.35 if layout == "double_line" else 0.55))
        font_size = font_size_base + random.randint(-3, 5)
    else:
        font_style = "mono"
        font_size = int(height * (0.35 if layout == "double_line" else 0.58))

    font = _pick_font(font_size, font_style)

    if layout == "double_line":
        top_line, bottom_line = _split_for_double_line(text)

        # Top line
        tw = _get_text_width_charwise(draw, top_line, font, hand_painted)
        x_top = max(5, (width - tw) // 2 + random.randint(-5, 5))
        y_top = int(height * 0.10) + random.randint(-3, 3)
        _render_char_by_char(draw, top_line, x_top, y_top, font, text_color, hand_painted)

        # Bottom line (may use slightly larger font)
        bottom_font_size = font_size + random.randint(-2, 4)
        bottom_font = _pick_font(bottom_font_size, font_style)
        bw = _get_text_width_charwise(draw, bottom_line, bottom_font, hand_painted)
        x_bot = max(5, (width - bw) // 2 + random.randint(-5, 5))
        y_bot = int(height * 0.52) + random.randint(-3, 3)
        _render_char_by_char(draw, bottom_line, x_bot, y_bot, bottom_font, text_color, hand_painted)
    else:
        # Single line — optionally add spacing groups
        display_text = text
        if not hand_painted and random.random() < 0.4 and len(text) >= 10:
            display_text = f"{text[:2]} {text[2:4]} {text[4:6]} {text[6:]}"
        elif hand_painted and random.random() < 0.3:
            # Hand-painted often has dots or dashes
            sep = random.choice(["·", "•", "-", " "])
            if len(text) >= 10:
                display_text = f"{text[:4]}{sep}{text[4:]}"

        tw = _get_text_width_charwise(draw, display_text, font, hand_painted)
        x = max(5, (width - tw) // 2 + random.randint(-3, 3))
        bbox = draw.textbbox((0, 0), "A", font=font)
        char_h = bbox[3] - bbox[1]
        y = max(3, (height - char_h) // 2 + random.randint(-3, 3))
        _render_char_by_char(draw, display_text, x, y, font, text_color, hand_painted)

    # Border styles
    if random.random() < 0.6:
        border_w = random.randint(1, 3)
        if hand_painted and random.random() < 0.3:
            # Decorative double border
            border_color = (random.randint(0, 80), random.randint(0, 80), random.randint(0, 80))
            draw.rectangle([(1, 1), (width - 2, height - 2)], outline=border_color, width=border_w)
            if random.random() < 0.4:
                inner = border_w + 2
                draw.rectangle([(inner, inner), (width - inner - 1, height - inner - 1)],
                               outline=border_color, width=1)
        else:
            border_color = (random.randint(0, 60), random.randint(0, 60), random.randint(0, 60))
            draw.rectangle([(1, 1), (width - 2, height - 2)], outline=border_color, width=border_w)

    # Screws/rivets (common on metal plates)
    if random.random() < 0.3:
        rivet_color = (random.randint(80, 140), random.randint(80, 140), random.randint(80, 140))
        r = random.randint(2, 4)
        positions = [(8, height // 2), (width - 8, height // 2)]
        if random.random() < 0.3:
            positions = [(8, 8), (width - 8, 8), (8, height - 8), (width - 8, height - 8)]
        for px, py in positions:
            draw.ellipse([(px - r, py - r), (px + r, py + r)], fill=rivet_color)

    return np.array(img)


def apply_degradation(img: np.ndarray) -> np.ndarray:
    """Apply realistic degradation effects seen on commercial vehicles."""
    h, w = img.shape[:2]

    # Mud/dirt overlay (40% of commercial vehicles)
    if random.random() < 0.35:
        mud_intensity = random.uniform(0.1, 0.4)
        mud = np.zeros_like(img, dtype=np.float32)
        # Random mud splotches
        n_splotches = random.randint(2, 8)
        for _ in range(n_splotches):
            cx = random.randint(0, w)
            cy = random.randint(0, h)
            rx = random.randint(10, w // 3)
            ry = random.randint(5, h // 3)
            mud_color = np.array([random.randint(60, 120), random.randint(50, 100), random.randint(30, 70)], dtype=np.float32)
            Y, X = np.ogrid[:h, :w]
            mask = ((X - cx) ** 2 / max(rx ** 2, 1) + (Y - cy) ** 2 / max(ry ** 2, 1)) < 1
            mud[mask] = mud_color
        alpha = mud_intensity * (mud.sum(axis=2, keepdims=True) > 0).astype(np.float32)
        img = np.clip(img.astype(np.float32) * (1 - alpha) + mud * alpha, 0, 255).astype(np.uint8)

    # Fading/sun bleach (30% — especially yellow plates)
    if random.random() < 0.25:
        fade_factor = random.uniform(0.15, 0.4)
        # Non-uniform fading (top fades more)
        fade_gradient = np.linspace(1.0, 1.0 - fade_factor, h).reshape(h, 1, 1)
        if random.random() < 0.5:
            fade_gradient = np.flip(fade_gradient, axis=0)
        faded = img.astype(np.float32)
        faded = faded * fade_gradient + 255 * (1 - fade_gradient) * 0.3
        img = np.clip(faded, 0, 255).astype(np.uint8)

    # Peeling paint (15%)
    if random.random() < 0.12:
        n_peels = random.randint(1, 4)
        for _ in range(n_peels):
            px = random.randint(0, w - 10)
            py = random.randint(0, h - 5)
            pw = random.randint(5, 25)
            ph = random.randint(3, 15)
            metal_color = random.randint(100, 160)
            img[py:py+ph, px:px+pw] = np.clip(
                img[py:py+ph, px:px+pw].astype(np.float32) * 0.3 + metal_color * 0.7,
                0, 255
            ).astype(np.uint8)

    # Rust stains (10%)
    if random.random() < 0.08:
        n_spots = random.randint(1, 3)
        for _ in range(n_spots):
            cx = random.randint(0, w)
            cy = random.randint(0, h)
            radius = random.randint(5, 20)
            rust_color = np.array([random.randint(40, 80), random.randint(60, 120), random.randint(140, 200)])
            Y, X = np.ogrid[:h, :w]
            dist = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2)
            mask = dist < radius
            alpha = np.clip(1.0 - dist / radius, 0, 1)[..., np.newaxis] * 0.5
            region = img.astype(np.float32)
            region[mask] = region[mask] * (1 - alpha[mask]) + rust_color * alpha[mask]
            img = np.clip(region, 0, 255).astype(np.uint8)

    # Water streaks (8%)
    if random.random() < 0.06:
        for _ in range(random.randint(1, 3)):
            x = random.randint(0, w - 1)
            streak_w = random.randint(2, 6)
            alpha = random.uniform(0.1, 0.3)
            x_end = min(x + streak_w, w)
            img[:, x:x_end] = np.clip(
                img[:, x:x_end].astype(np.float32) * (1 - alpha) + 200 * alpha,
                0, 255
            ).astype(np.uint8)

    return img


def augment_plate(img: np.ndarray) -> np.ndarray:
    """Apply random augmentations to simulate real-world capture conditions."""
    h, w = img.shape[:2]

    # Perspective warp (plate angle from camera)
    if random.random() < 0.6:
        severity = random.uniform(0.02, 0.08)
        pts1 = np.float32([[0, 0], [w, 0], [0, h], [w, h]])
        pts2 = np.float32([
            [random.uniform(0, w * severity), random.uniform(0, h * severity)],
            [w - random.uniform(0, w * severity), random.uniform(0, h * severity)],
            [random.uniform(0, w * severity), h - random.uniform(0, h * severity)],
            [w - random.uniform(0, w * severity), h - random.uniform(0, h * severity)],
        ])
        M = cv2.getPerspectiveTransform(pts1, pts2)
        img = cv2.warpPerspective(img, M, (w, h), borderMode=cv2.BORDER_REPLICATE)

    # Slight rotation (plates not perfectly horizontal)
    if random.random() < 0.4:
        angle = random.uniform(-5, 5)
        center = (w // 2, h // 2)
        M = cv2.getRotationMatrix2D(center, angle, 1.0)
        img = cv2.warpAffine(img, M, (w, h), borderMode=cv2.BORDER_REPLICATE)

    # Brightness/contrast variation
    alpha = random.uniform(0.5, 1.5)
    beta = random.randint(-40, 40)
    img = np.clip(img.astype(np.float32) * alpha + beta, 0, 255).astype(np.uint8)

    # Partial shadow (simulate overhang, bumper shadow)
    if random.random() < 0.25:
        shadow_h = random.randint(h // 6, h // 3)
        shadow_side = random.choice(["top", "bottom", "left", "right"])
        shadow_alpha = random.uniform(0.3, 0.7)
        if shadow_side == "top":
            img[:shadow_h] = (img[:shadow_h].astype(np.float32) * shadow_alpha).astype(np.uint8)
        elif shadow_side == "bottom":
            img[-shadow_h:] = (img[-shadow_h:].astype(np.float32) * shadow_alpha).astype(np.uint8)
        elif shadow_side == "left":
            sw = random.randint(w // 6, w // 3)
            img[:, :sw] = (img[:, :sw].astype(np.float32) * shadow_alpha).astype(np.uint8)
        else:
            sw = random.randint(w // 6, w // 3)
            img[:, -sw:] = (img[:, -sw:].astype(np.float32) * shadow_alpha).astype(np.uint8)

    # Gaussian blur (distance/defocus)
    if random.random() < 0.4:
        ksize = random.choice([3, 5, 7])
        img = cv2.GaussianBlur(img, (ksize, ksize), 0)

    # Motion blur (vehicle movement or camera shake)
    if random.random() < 0.2:
        kernel_size = random.choice([3, 5, 7])
        angle = random.uniform(-15, 15)
        kernel = np.zeros((kernel_size, kernel_size))
        kernel[kernel_size // 2, :] = np.ones(kernel_size) / kernel_size
        M = cv2.getRotationMatrix2D((kernel_size // 2, kernel_size // 2), angle, 1.0)
        kernel = cv2.warpAffine(kernel, M, (kernel_size, kernel_size))
        kernel = kernel / kernel.sum()
        img = cv2.filter2D(img, -1, kernel)

    # Gaussian noise (sensor noise, especially at night)
    if random.random() < 0.35:
        noise_std = random.uniform(5, 25)
        noise = np.random.randn(*img.shape) * noise_std
        img = np.clip(img.astype(np.float32) + noise, 0, 255).astype(np.uint8)

    # JPEG compression artifacts
    if random.random() < 0.35:
        quality = random.randint(20, 70)
        _, buf = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, quality])
        img = cv2.imdecode(buf, cv2.IMREAD_COLOR)

    # Random resize to simulate varying distance, then resize to PARSeq input (32x128)
    target_h = random.randint(20, 80)
    scale = target_h / h
    new_w = max(32, int(w * scale))
    interp = random.choice([cv2.INTER_LINEAR, cv2.INTER_AREA, cv2.INTER_CUBIC])
    img = cv2.resize(img, (new_w, target_h), interpolation=interp)

    # Final resize to PARSeq input size
    img = cv2.resize(img, (128, 32), interpolation=cv2.INTER_LINEAR)

    return img


def write_lmdb(output_dir: Path, samples: list[tuple[np.ndarray, str]]):
    """Write samples to LMDB in STR benchmark format."""
    output_dir.mkdir(parents=True, exist_ok=True)
    db_path = str(output_dir)

    map_size = len(samples) * 50_000
    env = lmdb.open(db_path, map_size=map_size)

    with env.begin(write=True) as txn:
        for idx, (img, label) in enumerate(samples):
            _, buf = cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, 90])
            img_bytes = buf.tobytes()

            img_key = f"image-{idx+1:09d}".encode()
            label_key = f"label-{idx+1:09d}".encode()

            txn.put(img_key, img_bytes)
            txn.put(label_key, label.encode())

        txn.put(b"num-samples", str(len(samples)).encode())

    env.close()
    print(f"  Written {len(samples)} samples to {output_dir}")


def main():
    parser = argparse.ArgumentParser(description='Generate synthetic Indian plate dataset')
    parser.add_argument('--count', type=int, default=50000, help='Total samples to generate')
    parser.add_argument('--val-split', type=float, default=0.1, help='Validation split ratio')
    parser.add_argument('--output', type=str, default='datasets/indian_plates_lmdb', help='Output directory')
    parser.add_argument('--seed', type=int, default=42, help='Random seed')
    args = parser.parse_args()

    random.seed(args.seed)
    np.random.seed(args.seed)

    output_dir = Path(args.output)
    total = args.count
    val_count = int(total * args.val_split)
    train_count = total - val_count

    print(f"Generating {total} synthetic Indian plates...")
    print(f"  Train: {train_count}, Val: {val_count}")
    print(f"  Output: {output_dir}")
    print(f"  Includes: commercial double-line, hand-painted, degradation effects")
    print()

    stats = {"standard": 0, "commercial": 0, "tractor": 0, "bharat": 0,
             "double_line": 0, "hand_painted_approx": 0}

    all_samples = []
    for i in range(total):
        text, plate_type, layout = generate_plate_text()
        stats[plate_type] = stats.get(plate_type, 0) + 1
        if layout == "double_line":
            stats["double_line"] += 1

        img = render_plate(text, plate_type, layout)
        img = apply_degradation(img)
        img = augment_plate(img)

        label = text.replace(" ", "").replace("·", "").replace("•", "").replace("-", "")
        all_samples.append((img, label))

        if (i + 1) % 10000 == 0:
            print(f"  Generated {i+1}/{total}...")

    random.shuffle(all_samples)
    train_samples = all_samples[:train_count]
    val_samples = all_samples[train_count:]

    print("\nWriting LMDB databases...")
    write_lmdb(output_dir / "train", train_samples)
    write_lmdb(output_dir / "val", val_samples)

    with open(output_dir / "labels.txt", "w") as f:
        for _, label in all_samples[:200]:
            f.write(f"{label}\n")

    print(f"\nDone! Dataset at: {output_dir}")
    print(f"  Distribution: {stats}")
    charset = sorted(set(''.join(l for _, l in all_samples)))
    print(f"  Charset ({len(charset)}): {''.join(charset)}")
    print(f"\nNext: upload to Lightning AI and run PARSeq fine-tuning")


if __name__ == "__main__":
    main()
