"""
Download Real-ESRGAN ONNX models for plate crop super-resolution.

Three tiers matched to hardware capability:
  high:   realesrgan_x2plus.onnx (~25MB) — RRDBNet 23 blocks, best quality
  mid:    realesrgan_compact.onnx (~5MB) — SRVGGNet, good quality/speed balance
  budget: no model needed (bicubic 2x + unsharp, handled in code)

Usage:
  python3 scripts/download_realesrgan.py             # download both
  python3 scripts/download_realesrgan.py --tier high # download high only
  python3 scripts/download_realesrgan.py --tier mid  # download mid only
"""

import argparse
import subprocess
import sys
from pathlib import Path


MODEL_DIR = Path(__file__).parent.parent / "models" / "anpr"

# PyTorch source weights (we convert to ONNX locally)
MODELS = {
    "high": {
        "pth_url": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth",
        "output": MODEL_DIR / "realesrgan_x2plus.onnx",
        "arch": "rrdbnet",
        "scale": 2,
        "num_block": 23,
        "num_feat": 64,
        "num_grow_ch": 32,
        "description": "RRDBNet x2plus — best quality, ~40ms on Apple Silicon, ~150ms on i7",
    },
    "mid": {
        "pth_url": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.5.0/realesr-general-x4v3.pth",
        "output": MODEL_DIR / "realesrgan_compact.onnx",
        "arch": "srvggnet",
        "scale": 4,
        "num_conv": 16,
        "num_feat": 64,
        "description": "SRVGGNet compact — good balance, ~15ms on Apple Silicon, ~60ms on i5",
    },
}


def _ensure_deps():
    """Ensure torch is available for ONNX export."""
    try:
        import torch  # noqa: F401
        return True
    except ImportError:
        print("PyTorch required for ONNX export. Install with:")
        print("  pip install torch --index-url https://download.pytorch.org/whl/cpu")
        return False


def _download_file(url: str, dest: Path) -> bool:
    """Download a file using requests (handles SSL properly)."""
    try:
        import requests
        print(f"  Downloading from {url.split('/')[-1]}...")
        resp = requests.get(url, stream=True, timeout=120)
        resp.raise_for_status()
        total = int(resp.headers.get("content-length", 0))
        downloaded = 0
        with open(dest, "wb") as f:
            for chunk in resp.iter_content(chunk_size=8192):
                f.write(chunk)
                downloaded += len(chunk)
                if total:
                    pct = downloaded * 100 // total
                    print(f"\r  Progress: {pct}% ({downloaded // 1024 // 1024}MB)", end="", flush=True)
        print()
        return True
    except ImportError:
        import ssl
        import urllib.request
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        urllib.request.urlretrieve(url, dest)
        return True


def export_rrdbnet(pth_path: Path, output_path: Path, scale: int, num_block: int, num_feat: int, num_grow_ch: int):
    """Export RRDBNet (x2plus) to ONNX."""
    import torch

    try:
        from basicsr.archs.rrdbnet_arch import RRDBNet
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "basicsr", "--quiet"])
        from basicsr.archs.rrdbnet_arch import RRDBNet

    model = RRDBNet(num_in_ch=3, num_out_ch=3, num_feat=num_feat, num_block=num_block, num_grow_ch=num_grow_ch, scale=scale)
    loadnet = torch.load(pth_path, map_location="cpu", weights_only=False)
    if "params_ema" in loadnet:
        model.load_state_dict(loadnet["params_ema"])
    elif "params" in loadnet:
        model.load_state_dict(loadnet["params"])
    else:
        model.load_state_dict(loadnet)
    model.eval()

    dummy = torch.randn(1, 3, 64, 200)
    torch.onnx.export(
        model, dummy, str(output_path),
        input_names=["input"], output_names=["output"],
        dynamic_axes={"input": {2: "height", 3: "width"}, "output": {2: "height", 3: "width"}},
        opset_version=17,
    )


def export_srvggnet(pth_path: Path, output_path: Path, scale: int, num_conv: int, num_feat: int):
    """Export SRVGGNetCompact to ONNX."""
    import torch

    try:
        from realesrgan.archs.srvgg_arch import SRVGGNetCompact
    except ImportError:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "realesrgan", "--quiet"])
        from realesrgan.archs.srvgg_arch import SRVGGNetCompact

    model = SRVGGNetCompact(num_in_ch=3, num_out_ch=3, num_feat=num_feat, num_conv=num_conv, upscale=scale, act_type="prelu")
    loadnet = torch.load(pth_path, map_location="cpu", weights_only=False)
    if "params_ema" in loadnet:
        model.load_state_dict(loadnet["params_ema"])
    elif "params" in loadnet:
        model.load_state_dict(loadnet["params"])
    else:
        model.load_state_dict(loadnet)
    model.eval()

    dummy = torch.randn(1, 3, 64, 200)
    torch.onnx.export(
        model, dummy, str(output_path),
        input_names=["input"], output_names=["output"],
        dynamic_axes={"input": {2: "height", 3: "width"}, "output": {2: "height", 3: "width"}},
        opset_version=17,
    )


def download_and_convert(tier: str) -> bool:
    """Download PyTorch weights and convert to ONNX for the given tier."""
    cfg = MODELS[tier]
    output_path = cfg["output"]

    if output_path.exists():
        size_mb = output_path.stat().st_size / 1024 / 1024
        print(f"  [{tier}] Already exists: {output_path.name} ({size_mb:.1f} MB)")
        return True

    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    pth_path = MODEL_DIR / f"_tmp_{tier}.pth"

    print(f"  [{tier}] {cfg['description']}")

    if not _download_file(cfg["pth_url"], pth_path):
        return False

    print(f"  [{tier}] Converting to ONNX...")
    try:
        if cfg["arch"] == "rrdbnet":
            export_rrdbnet(pth_path, output_path, cfg["scale"], cfg["num_block"], cfg["num_feat"], cfg["num_grow_ch"])
        elif cfg["arch"] == "srvggnet":
            export_srvggnet(pth_path, output_path, cfg["scale"], cfg["num_conv"], cfg["num_feat"])
        else:
            print(f"  [{tier}] Unknown arch: {cfg['arch']}")
            return False

        size_mb = output_path.stat().st_size / 1024 / 1024
        print(f"  [{tier}] Saved: {output_path.name} ({size_mb:.1f} MB)")
        return True
    except Exception as e:
        print(f"  [{tier}] Export failed: {e}")
        if output_path.exists():
            output_path.unlink()
        return False
    finally:
        if pth_path.exists():
            pth_path.unlink()


def main():
    parser = argparse.ArgumentParser(description="Download Real-ESRGAN super-resolution models")
    parser.add_argument("--tier", choices=["high", "mid", "all"], default="all",
                        help="Which model tier to download (default: all)")
    args = parser.parse_args()

    if not _ensure_deps():
        sys.exit(1)

    print("Real-ESRGAN super-resolution models for plate crop upscaling")
    print("=" * 60)
    print("  high:   RRDBNet x2plus — Apple Silicon / GPU / high-core CPUs")
    print("  mid:    SRVGGNet compact — mid-range Intel/AMD CPUs")
    print("  budget: bicubic (no model needed)")
    print()

    tiers = ["high", "mid"] if args.tier == "all" else [args.tier]
    results = {}

    for tier in tiers:
        success = download_and_convert(tier)
        results[tier] = success

    print()
    print("Summary:")
    for tier, success in results.items():
        status = "OK" if success else "FAILED"
        print(f"  {tier}: {status}")

    if not all(results.values()):
        print("\nFailed models will fall back to bicubic upscaling (still works well for plates).")
        sys.exit(1)


if __name__ == "__main__":
    main()
