"""
Download and cache PARSeq model for offline use.

Run once with internet:
    python scripts/setup_parseq.py

This clones the parseq repo into models/parseq/ and downloads weights.
After this, the sidecar works fully offline.
"""

import subprocess
import sys
from pathlib import Path

MODELS_DIR = Path(__file__).parent.parent / "models"
PARSEQ_DIR = MODELS_DIR / "parseq"


def main():
    print("Setting up PARSeq for offline use...")

    # Clone the parseq repo (lightweight — just the code)
    if not PARSEQ_DIR.exists():
        print(f"Cloning parseq repo to {PARSEQ_DIR}...")
        subprocess.run(
            ["git", "clone", "--depth=1", "https://github.com/baudm/parseq.git", str(PARSEQ_DIR)],
            check=True,
        )
    else:
        print(f"PARSeq repo already exists at {PARSEQ_DIR}")

    # Install strhub dependencies (from parseq repo)
    print("Installing parseq dependencies...")
    subprocess.run(
        [sys.executable, "-m", "pip", "install", "-e", str(PARSEQ_DIR), "--quiet"],
        check=True,
    )

    # Download and cache the pre-trained weights
    print("Downloading pre-trained weights...")
    import torch
    sys.path.insert(0, str(PARSEQ_DIR))
    model = torch.hub.load(str(PARSEQ_DIR), "parseq", pretrained=True, source="local", trust_repo=True)
    model.eval()

    # Verify
    from strhub.data.module import SceneTextDataModule
    transform = SceneTextDataModule.get_transform(model.hparams.img_size)
    print(f"\nPARSeq setup complete!")
    print(f"  Model location: {PARSEQ_DIR}")
    print(f"  Input size: {model.hparams.img_size}")
    print(f"  Parameters: {sum(p.numel() for p in model.parameters()) / 1e6:.1f}M")
    print(f"  Device: {'MPS' if torch.backends.mps.is_available() else 'CPU'}")

    # Quick test with dummy input
    import numpy as np
    from PIL import Image
    dummy = Image.fromarray(np.zeros((64, 200, 3), dtype=np.uint8))
    tensor = transform(dummy).unsqueeze(0)
    with torch.no_grad():
        logits = model(tensor)
    probs = logits.softmax(-1)
    preds, _ = model.tokenizer.decode(probs)
    print(f"  Test inference: '{preds[0]}' (expected empty/noise on blank image)")
    print("\nReady! The sidecar will now use PARSeq automatically.")


if __name__ == "__main__":
    main()
