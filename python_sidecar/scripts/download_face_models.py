"""
Download AdaFace + SCRFD models for the face recognition engine.

Models:
  - SCRFD 2.5G (detection): fast, lightweight, 5-point landmarks
  - AdaFace IR-50 WebFace12M (recognition): SOTA on low-quality faces

Usage:
  python scripts/download_face_models.py
"""

import os
import sys
from pathlib import Path

MODEL_DIR = Path(__file__).parent.parent / "models" / "face"

MODELS = {
    "scrfd_2.5g_bnkps.onnx": {
        "url": "https://huggingface.co/hsuyabc/scrfd_2.5g_bnkps.onnx/resolve/main/scrfd_2.5g_bnkps.onnx",
        "size_mb": 3.3,
        "description": "SCRFD 2.5G face detector with keypoints (fast, ~5ms on CPU)",
    },
    "adaface.onnx": {
        "url": "https://huggingface.co/palhs/ekyc-adaface-ir50/resolve/main/adaface.onnx",
        "size_mb": 174,
        "description": "AdaFace IR-50 recognition (512-dim embeddings, SOTA on low-quality faces)",
    },
}

ALTERNATIVE_URLS = {
    "scrfd_2.5g_bnkps.onnx": [],
    "adaface.onnx": [],
}


def download_file(url: str, dest: Path) -> bool:
    """Download a file with progress."""
    try:
        import urllib.request
        import ssl

        print(f"  Downloading from: {url}")
        # macOS Python often lacks system certs — use unverified context as fallback
        ctx = ssl.create_default_context()
        try:
            import certifi
            ctx.load_verify_locations(certifi.where())
        except (ImportError, Exception):
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE

        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, context=ctx) as response:
            total = int(response.headers.get("Content-Length", 0))
            with open(dest, "wb") as f:
                downloaded = 0
                while True:
                    chunk = response.read(8192)
                    if not chunk:
                        break
                    f.write(chunk)
                    downloaded += len(chunk)
                    if total:
                        pct = downloaded * 100 / total
                        print(f"\r  Progress: {pct:.1f}% ({downloaded // 1024 // 1024}MB / {total // 1024 // 1024}MB)", end="")
                print()
        return True
    except Exception as e:
        print(f"  Failed: {e}")
        if dest.exists():
            dest.unlink()
        return False


EXTRA_FILES = {
    "adaface.onnx": [
        {
            "filename": "adaface.onnx.data",
            "url": "https://huggingface.co/palhs/ekyc-adaface-ir50/resolve/main/adaface.onnx.data",
            "size_mb": 174,
        }
    ],
}


def main():
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Model directory: {MODEL_DIR}\n")

    for filename, info in MODELS.items():
        dest = MODEL_DIR / filename
        if dest.exists():
            print(f"[OK] {filename} already exists ({dest.stat().st_size // 1024 // 1024}MB)")
        else:
            print(f"[DL] {filename} — {info['description']} (~{info['size_mb']}MB)")

            urls = [info["url"]] + ALTERNATIVE_URLS.get(filename, [])
            success = False
            for url in urls:
                if download_file(url, dest):
                    success = True
                    break

            if not success:
                print(f"  [FAIL] Could not download {filename} from any source.")
                print(f"  Please manually download and place in: {dest}")
                sys.exit(1)

        # Download companion files (e.g. .onnx.data for external weights)
        for extra in EXTRA_FILES.get(filename, []):
            extra_dest = MODEL_DIR / extra["filename"]
            if extra_dest.exists():
                print(f"[OK] {extra['filename']} already exists")
                continue
            print(f"[DL] {extra['filename']} (~{extra['size_mb']}MB)")
            if not download_file(extra["url"], extra_dest):
                print(f"  [FAIL] Could not download {extra['filename']}.")
                sys.exit(1)

    print("\nAll face models ready.")
    print(f"  Detection: {MODEL_DIR / 'scrfd_2.5g_bnkps.onnx'}")
    print(f"  Recognition: {MODEL_DIR / 'adaface.onnx'}")


if __name__ == "__main__":
    main()
