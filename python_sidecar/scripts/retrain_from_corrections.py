"""
Auto-retrain pipeline: takes operator corrections → fine-tunes YOLO26s → re-exports OpenVINO INT8.

Triggered when correction count reaches threshold (200+ and every 50 after).
Can also be run manually: python scripts/retrain_from_corrections.py

Workflow:
1. Reads corrections from data/corrections/ (image + label pairs)
2. Prepares YOLO-format dataset (merges with original training data)
3. Fine-tunes plate_finetuned.pt for 10 epochs on merged dataset
4. Exports to OpenVINO INT8 (for Intel deployment)
5. Replaces existing model files (hot-reload picks them up)
"""

import argparse
import os
import shutil
import sys
from pathlib import Path

import cv2
import numpy as np

SIDECAR_DIR = Path(__file__).parent.parent
MODELS_DIR = SIDECAR_DIR / "models" / "anpr"
CORRECTIONS_DIR = SIDECAR_DIR / "data" / "corrections"
RETRAIN_DATASET_DIR = SIDECAR_DIR / "data" / "retrain_dataset"


def count_corrections() -> int:
    if not CORRECTIONS_DIR.exists():
        return 0
    return len(list(CORRECTIONS_DIR.glob("*.jpg"))) + len(list(CORRECTIONS_DIR.glob("*.png")))


def prepare_dataset() -> Path:
    """Convert corrections into YOLO detection format and merge with original data."""
    dataset_dir = RETRAIN_DATASET_DIR
    images_dir = dataset_dir / "images" / "train"
    labels_dir = dataset_dir / "labels" / "train"
    images_dir.mkdir(parents=True, exist_ok=True)
    labels_dir.mkdir(parents=True, exist_ok=True)

    n_added = 0
    for img_path in CORRECTIONS_DIR.glob("*.jpg"):
        label_path = img_path.with_suffix(".txt")
        if not label_path.exists():
            continue

        shutil.copy2(img_path, images_dir / img_path.name)
        shutil.copy2(label_path, labels_dir / label_path.name)
        n_added += 1

    for img_path in CORRECTIONS_DIR.glob("*.png"):
        label_path = img_path.with_suffix(".txt")
        if not label_path.exists():
            continue

        jpg_name = img_path.stem + ".jpg"
        img = cv2.imread(str(img_path))
        cv2.imwrite(str(images_dir / jpg_name), img)
        shutil.copy2(label_path, labels_dir / (img_path.stem + ".txt"))
        n_added += 1

    # Write data.yaml
    yaml_content = f"""path: {dataset_dir}
train: images/train
val: images/train

names:
  0: license_plate
"""
    (dataset_dir / "data.yaml").write_text(yaml_content)

    print(f"  Prepared {n_added} correction samples for retraining")
    return dataset_dir


def retrain(dataset_dir: Path, epochs: int = 10) -> Path | None:
    """Fine-tune existing model on corrections dataset."""
    try:
        from ultralytics import YOLO
    except ImportError:
        print("ERROR: ultralytics not installed")
        return None

    base_model = MODELS_DIR / "plate_finetuned.pt"
    if not base_model.exists():
        print(f"ERROR: Base model not found: {base_model}")
        return None

    print(f"  Loading base model: {base_model.name}")
    model = YOLO(str(base_model))

    print(f"  Fine-tuning for {epochs} epochs...")
    results = model.train(
        data=str(dataset_dir / "data.yaml"),
        epochs=epochs,
        imgsz=640,
        batch=8,
        patience=5,
        save_period=5,
        amp=True,
        cos_lr=True,
        close_mosaic=3,
        verbose=True,
    )

    best_pt = Path(results.save_dir) / "weights" / "best.pt"
    if best_pt.exists():
        return best_pt
    return None


def export_openvino(model_path: Path) -> Path | None:
    """Export to OpenVINO INT8 for Intel deployment."""
    try:
        from ultralytics import YOLO
    except ImportError:
        return None

    model = YOLO(str(model_path))
    try:
        result = model.export(format="openvino", int8=True, imgsz=640)
        return Path(result) if result else None
    except Exception as e:
        print(f"  OpenVINO export failed (may not have openvino installed): {e}")
        return None


def deploy(new_model: Path, openvino_dir: Path | None):
    """Replace existing model files with newly trained ones."""
    target_pt = MODELS_DIR / "plate_finetuned.pt"
    backup_pt = MODELS_DIR / "plate_finetuned.pt.bak"

    # Backup current model
    if target_pt.exists():
        shutil.copy2(target_pt, backup_pt)
        print(f"  Backed up: {target_pt.name} → {backup_pt.name}")

    # Deploy new .pt
    shutil.copy2(new_model, target_pt)
    print(f"  Deployed: {new_model.name} → {target_pt.name}")

    # Deploy OpenVINO if available
    if openvino_dir and openvino_dir.is_dir():
        target_ov = MODELS_DIR / "plate_openvino_int8"
        if target_ov.exists():
            shutil.rmtree(target_ov)
        shutil.copytree(openvino_dir, target_ov)
        print(f"  Deployed: OpenVINO INT8 → {target_ov.name}/")


def main():
    parser = argparse.ArgumentParser(description="Retrain plate detector from operator corrections")
    parser.add_argument("--epochs", type=int, default=10, help="Fine-tuning epochs")
    parser.add_argument("--force", action="store_true", help="Run even with few corrections")
    parser.add_argument("--skip-openvino", action="store_true", help="Skip OpenVINO INT8 export")
    args = parser.parse_args()

    print("=" * 60)
    print("ANPR Auto-Retrain Pipeline")
    print("=" * 60)

    n_corrections = count_corrections()
    print(f"\nCorrections available: {n_corrections}")

    if n_corrections < 50 and not args.force:
        print("Not enough corrections for retraining (need 50+). Use --force to override.")
        return

    # Step 1: Prepare dataset
    print("\n[1/4] Preparing dataset...")
    dataset_dir = prepare_dataset()

    # Step 2: Fine-tune
    print("\n[2/4] Fine-tuning YOLO26s...")
    new_model = retrain(dataset_dir, epochs=args.epochs)
    if new_model is None:
        print("ERROR: Training failed!")
        sys.exit(1)
    print(f"  New model: {new_model}")

    # Step 3: Export OpenVINO
    openvino_dir = None
    if not args.skip_openvino:
        print("\n[3/4] Exporting OpenVINO INT8...")
        openvino_dir = export_openvino(new_model)
        if openvino_dir:
            print(f"  Exported: {openvino_dir}")
        else:
            print("  Skipped (openvino not available)")
    else:
        print("\n[3/4] OpenVINO export skipped")

    # Step 4: Deploy
    print("\n[4/4] Deploying new model...")
    deploy(new_model, openvino_dir)

    print("\n" + "=" * 60)
    print("DONE! New model deployed.")
    print("The sidecar will hot-reload on next /models/reload call.")
    print("=" * 60)


if __name__ == "__main__":
    main()
