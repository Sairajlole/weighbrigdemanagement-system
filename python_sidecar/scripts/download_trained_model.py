"""
Download trained YOLO26s model from Lightning AI studio.
Run after training completes on the remote studio.

Usage: python scripts/download_trained_model.py
"""

import os
import sys
from pathlib import Path

MODELS_DIR = Path(__file__).parent.parent / "models" / "anpr"


def main():
    os.environ['LIGHTNING_USER_ID'] = '0bf37044-695e-4c0e-a5f7-35c1102bb916'
    os.environ['LIGHTNING_API_KEY'] = '727b9332-1ffe-4b26-9626-f2b628475879'

    try:
        from lightning_sdk import Studio
    except ImportError:
        print("Install lightning-sdk: pip install lightning-sdk")
        sys.exit(1)

    print("Connecting to Lightning AI studio...")
    s = Studio(name='yolo26s-plate', teamspace='vision-model', user='yashjain2681')
    print(f"Studio status: {s.status}, machine: {s.machine}")

    # Check if training is complete
    epoch_count = s.run("grep -c 'all' /teamspace/studios/this_studio/train_log.txt").strip()
    print(f"Completed epochs: {epoch_count}")

    # Check for best.pt
    best_check = s.run("ls -la /teamspace/studios/this_studio/runs/detect/yolo26s_plate/weights/best.pt 2>/dev/null || echo NOT_FOUND")
    if "NOT_FOUND" in best_check:
        # Try alternate path
        best_check = s.run("find /teamspace/studios/this_studio/runs -name 'best.pt' | head -1")
        if not best_check.strip():
            print("ERROR: best.pt not found. Training may still be running.")
            sys.exit(1)
        remote_path = best_check.strip()
    else:
        remote_path = "/teamspace/studios/this_studio/runs/detect/yolo26s_plate/weights/best.pt"

    print(f"Found model at: {remote_path}")

    # Get file size
    size_info = s.run(f"ls -la {remote_path}")
    print(f"  {size_info.strip()}")

    # Get final metrics
    last_metrics = s.run("grep 'all' /teamspace/studios/this_studio/train_log.txt | tail -1 | strings")
    print(f"Final metrics: {last_metrics.strip()}")

    # Download via base64 encoding (lightning-sdk doesn't have direct file download)
    print("\nDownloading model...")
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    local_path = MODELS_DIR / "plate_finetuned.pt"

    # Use scp-like approach: encode on remote, decode locally
    import base64
    import tempfile

    # Split into chunks to avoid memory issues
    chunk_size = 10_000_000  # 10MB chunks
    file_size = int(s.run(f"stat -c%s {remote_path} 2>/dev/null || stat -f%z {remote_path}").strip())
    print(f"  File size: {file_size / 1024 / 1024:.1f} MB")

    with open(local_path, 'wb') as f:
        offset = 0
        while offset < file_size:
            remaining = min(chunk_size, file_size - offset)
            b64_chunk = s.run(f"dd if={remote_path} bs=1 skip={offset} count={remaining} 2>/dev/null | base64")
            chunk_data = base64.b64decode(b64_chunk)
            f.write(chunk_data)
            offset += remaining
            pct = offset / file_size * 100
            print(f"  {pct:.0f}% ({offset / 1024 / 1024:.1f} MB)", end='\r')

    print(f"\nSaved to: {local_path}")
    print(f"  Size: {local_path.stat().st_size / 1024 / 1024:.1f} MB")

    # Verify it's a valid PyTorch file
    try:
        import torch
        model_data = torch.load(str(local_path), map_location='cpu', weights_only=False)
        print("  Verification: Valid PyTorch checkpoint")
    except Exception as e:
        print(f"  WARNING: Verification failed: {e}")

    print("\nDone! Restart sidecar to use the new model:")
    print("  python3 main.py")


if __name__ == "__main__":
    main()
