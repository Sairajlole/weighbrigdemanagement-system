"""
Fine-tune pretrained YOLO26s on Indian plate dataset (Lightning AI).

Prerequisites:
    - Stage 1 pretrained weights: yolo26s_plate_pretrained.pt (from Diverse-LPD training)
    - Dataset: python_sidecar/datasets/plates/ (2,445 train + 618 val + 321 test)

Setup on Lightning AI Studio (teamspace=vision-model, studio=yolo26s-plate):
    1. Upload pretrained weights (best.pt from stage 1) as yolo26s_plate_pretrained.pt
    2. Upload datasets/plates/ directory
    3. pip install ultralytics
    4. python lightning_finetune_yolo26s.py

Strategy:
    - Stage A: Freeze backbone (first 10 layers), train head only — 15 epochs
    - Stage B: Unfreeze all, low LR — 15 epochs
    - Total: ~30 epochs, prevents catastrophic forgetting of general plate features
"""

import subprocess
import sys
from pathlib import Path


def install_deps():
    subprocess.run([sys.executable, "-m", "pip", "install", "-q",
                    "ultralytics"], check=True)


def find_pretrained() -> str:
    """Locate pretrained weights from stage 1."""
    candidates = [
        Path("yolo26s_plate_pretrained.pt"),
        Path("runs/detect/yolo26s_plate/weights/best.pt"),
        Path("best.pt"),
    ]
    for p in candidates:
        if p.exists():
            print(f"Using pretrained weights: {p}")
            return str(p)

    print("ERROR: No pretrained weights found!")
    print("Upload your stage 1 best.pt as 'yolo26s_plate_pretrained.pt'")
    print("Or place it at: runs/detect/yolo26s_plate/weights/best.pt")
    sys.exit(1)


def prepare_dataset() -> str:
    """Ensure dataset is ready and return path to data.yaml."""
    dataset_dir = Path("datasets/plates")
    yaml_path = dataset_dir / "data.yaml"

    if not yaml_path.exists():
        print("ERROR: Dataset not found at datasets/plates/")
        print("Upload the plates dataset directory from your local machine:")
        print("  python_sidecar/datasets/plates/ → datasets/plates/")
        sys.exit(1)

    # Rewrite data.yaml with correct absolute path for this machine
    yaml_content = f"""path: {dataset_dir.resolve()}
train: train/images
val: valid/images
test: test/images

nc: 1
names:
  0: plate
"""
    yaml_path.write_text(yaml_content)

    train_count = len(list((dataset_dir / "train/images").glob("*")))
    val_count = len(list((dataset_dir / "valid/images").glob("*")))
    print(f"Dataset: {train_count} train, {val_count} val images")
    return str(yaml_path)


def finetune_stage_a(pretrained: str, data_yaml: str):
    """Stage A: Freeze backbone, train detection head only."""
    from ultralytics import YOLO

    print("=" * 60)
    print("STAGE A — Frozen backbone, head-only training")
    print("=" * 60)

    model = YOLO(pretrained)

    model.train(
        data=data_yaml,
        epochs=15,
        imgsz=640,
        batch=16,
        device=0,
        freeze=10,             # Freeze first 10 layers (backbone)
        lr0=0.005,             # Moderate LR for head
        lrf=0.1,
        warmup_epochs=2,
        patience=10,
        amp=True,
        workers=4,
        cos_lr=True,
        mosaic=1.0,
        close_mosaic=5,
        # Augmentations — Indian plate specific
        degrees=8.0,           # Plates on trucks can be tilted
        translate=0.1,
        scale=0.5,
        shear=3.0,
        perspective=0.001,
        flipud=0.0,
        fliplr=0.5,
        hsv_h=0.015,
        hsv_s=0.5,            # Faded yellow/white plates
        hsv_v=0.5,            # Night and harsh sunlight
        # Project
        project="runs/detect",
        name="yolo26s_finetune_a",
        exist_ok=True,
    )

    best_a = Path("runs/detect/yolo26s_finetune_a/weights/best.pt")
    print(f"\nStage A complete: {best_a}")
    return str(best_a)


def finetune_stage_b(stage_a_weights: str, data_yaml: str):
    """Stage B: Unfreeze all layers, low LR full fine-tune."""
    from ultralytics import YOLO

    print("=" * 60)
    print("STAGE B — Full model fine-tune, low LR")
    print("=" * 60)

    model = YOLO(stage_a_weights)

    model.train(
        data=data_yaml,
        epochs=15,
        imgsz=640,
        batch=12,              # Slightly smaller batch for full grad
        device=0,
        freeze=0,              # All layers trainable
        lr0=0.001,             # Low LR to preserve features
        lrf=0.01,
        warmup_epochs=1,
        patience=8,
        amp=True,
        workers=4,
        cos_lr=True,
        mosaic=0.8,
        close_mosaic=5,
        degrees=5.0,
        translate=0.1,
        scale=0.4,
        shear=2.0,
        perspective=0.0005,
        flipud=0.0,
        fliplr=0.5,
        hsv_h=0.015,
        hsv_s=0.4,
        hsv_v=0.4,
        # Project
        project="runs/detect",
        name="yolo26s_finetune_b",
        exist_ok=True,
    )

    best_b = Path("runs/detect/yolo26s_finetune_b/weights/best.pt")
    print(f"\nStage B complete: {best_b}")
    return str(best_b)


def export_models(best_path: str):
    """Export final fine-tuned model."""
    from ultralytics import YOLO

    print("=" * 60)
    print("EXPORTING FINAL MODEL")
    print("=" * 60)

    model = YOLO(best_path)

    # Validate first
    metrics = model.val(imgsz=640)
    print(f"\nFinal Metrics:")
    print(f"  Precision: {metrics.box.mp:.3f}")
    print(f"  Recall:    {metrics.box.mr:.3f}")
    print(f"  mAP50:     {metrics.box.map50:.3f}")
    print(f"  mAP50-95:  {metrics.box.map:.3f}")

    # Export ONNX
    print("\nExporting ONNX...")
    model.export(format="onnx", imgsz=640, simplify=True)

    # Export OpenVINO INT8
    print("\nExporting OpenVINO INT8...")
    try:
        model.export(format="openvino", int8=True, imgsz=640)
        print("OpenVINO INT8 export successful")
    except Exception as e:
        print(f"OpenVINO export skipped: {e}")

    # Copy as deployment artifact
    import shutil
    deploy_name = "yolo26s_indian_plate.pt"
    shutil.copy2(best_path, deploy_name)
    print(f"\nDeployment weights: {deploy_name}")
    print(f"Copy to your machine: python_sidecar/models/anpr/plate_finetuned.pt")


def main():
    install_deps()

    pretrained = find_pretrained()
    data_yaml = prepare_dataset()

    # Stage A: head-only
    stage_a_best = finetune_stage_a(pretrained, data_yaml)

    # Stage B: full fine-tune
    stage_b_best = finetune_stage_b(stage_a_best, data_yaml)

    # Export
    export_models(stage_b_best)

    print("\n" + "=" * 60)
    print("FINE-TUNING COMPLETE!")
    print("=" * 60)
    print("\nTwo-stage training done:")
    print("  Stage A: backbone frozen, 15 epochs → head adapted to Indian plates")
    print("  Stage B: full model, 15 epochs → refined detection boundaries")
    print("\nDownload: yolo26s_indian_plate.pt")
    print("Deploy:   python_sidecar/models/anpr/plate_finetuned.pt")


if __name__ == "__main__":
    main()
