"""
Download fine-tuned PARSeq model from Lightning AI studio.
Run after training completes on the remote studio.

Usage: python scripts/download_parseq_model.py
"""

import base64
import os
import sys
from pathlib import Path

MODELS_DIR = Path(__file__).parent.parent / "models" / "parseq"


def main():
    os.environ['LIGHTNING_USER_ID'] = '0bf37044-695e-4c0e-a5f7-35c1102bb916'
    os.environ['LIGHTNING_API_KEY'] = '727b9332-1ffe-4b26-9626-f2b628475879'

    try:
        from lightning_sdk import Studio
    except ImportError:
        print("Install lightning-sdk: pip install lightning-sdk")
        sys.exit(1)

    print("Connecting to Lightning AI studio...")
    s = Studio(name='parseq-indian', teamspace='vision-model', user='yashjain2681')
    print(f"Studio status: {s.status}, machine: {s.machine}")

    if s.status != "Running":
        print("Studio not running. Starting...")
        s.start()
        import time
        time.sleep(10)

    # Check if training is complete
    model_path = "/teamspace/studios/this_studio/parseq_indian.pt"
    result = s.run(f'ls -la {model_path} 2>/dev/null || echo "NOT_FOUND"')
    if "NOT_FOUND" in result:
        print("ERROR: parseq_indian.pt not found. Training may still be running.")
        result = s.run('tail -5 /teamspace/studios/this_studio/train_log_ft.txt 2>/dev/null')
        print(f"Last training log:\n{result}")
        sys.exit(1)

    print(f"Model found: {result.strip()}")

    # Get file size
    size_str = s.run(f'stat --printf="%s" {model_path}')
    file_size = int(size_str.strip())
    print(f"File size: {file_size / 1024 / 1024:.1f} MB")

    # Download in chunks
    CHUNK_SIZE = 3 * 1024 * 1024
    s.run(f'cd /tmp && rm -f parseq_chunk_* && split -b {CHUNK_SIZE} {model_path} parseq_chunk_')
    chunk_files = s.run('ls /tmp/parseq_chunk_* | sort').strip().split('\n')
    print(f"Downloading in {len(chunk_files)} chunks...")

    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    local_path = MODELS_DIR / "parseq_indian.pt"

    with open(local_path, 'wb') as f:
        for i, cf in enumerate(chunk_files):
            b64_data = s.run(f'base64 {cf.strip()}')
            chunk_bytes = base64.b64decode(b64_data.strip())
            f.write(chunk_bytes)
            print(f"  Chunk {i + 1}/{len(chunk_files)}: {len(chunk_bytes)} bytes")

    # Verify
    local_size = local_path.stat().st_size
    assert local_size == file_size, f"Size mismatch! Expected {file_size}, got {local_size}"

    # Cleanup
    s.run('rm -f /tmp/parseq_chunk_*')

    print(f"\nDownloaded: {local_path} ({local_size} bytes)")
    print("PARSeq OCR will automatically use fine-tuned weights on next sidecar restart.")

    # Also grab final accuracy from training log
    result = s.run('grep "Best accuracy" /teamspace/studios/this_studio/train_log_ft.txt 2>/dev/null || echo ""')
    if result.strip():
        print(f"\n{result.strip()}")


if __name__ == "__main__":
    main()
