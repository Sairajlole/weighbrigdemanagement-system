"""
Train YOLO26s for Indian license plate detection on Lightning AI.

Setup on Lightning AI Studio (teamspace=vision-model, studio=yolo26s-plate):
    1. Create a new Studio with L4 GPU (24GB)
    2. pip install ultralytics
    3. Download dataset: Diverse-LPD from Kaggle (fxmikf/diverse-lpd-training-ready)
    4. Run: python lightning_train_yolo26s.py

Dataset: https://www.kaggle.com/datasets/fxmikf/diverse-lpd-training-ready
    - 10K images (Diverse-LPD + Diverse-LPDv2 merged)
    - YOLO format: class 0 = license_plate
    - Split: 90% train / 10% val

Output:
    runs/detect/yolo26s_plate/weights/best.pt → deploy as plate_finetuned.pt
    best_openvino_int8_model/ → Intel deployment (2.5x speedup)
"""

import subprocess
import sys
from pathlib import Path


def install_deps():
    subprocess.run([sys.executable, "-m", "pip", "install", "-q",
                    "ultralytics"], check=True)


def download_dataset():
    """Download Diverse-LPD dataset from Kaggle and prepare train/val split."""
    dataset_dir = Path("datasets/plates")
    yaml_path = dataset_dir / "data.yaml"

    if yaml_path.exists():
        print(f"Dataset already prepared: {yaml_path}")
        return str(yaml_path)

    print("="*60)
    print("DATASET SETUP — Diverse-LPD (Kaggle)")
    print("="*60)

    # Download from Kaggle API (public dataset, no auth required for direct URL)
    zip_path = Path("datasets/diverse-lpd.zip")
    if not zip_path.exists():
        print("Downloading from Kaggle...")
        zip_path.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([
            "curl", "-L", "-o", str(zip_path),
            "https://www.kaggle.com/api/v1/datasets/download/fxmikf/diverse-lpd-training-ready",
            "--retry", "3", "--max-time", "600",
        ], check=True)

    # Extract
    extract_dir = Path("datasets/diverse-lpd")
    if not extract_dir.exists():
        print("Extracting...")
        subprocess.run(["unzip", "-q", str(zip_path), "-d", str(extract_dir)], check=True)

    # Merge Diverse-LPD + Diverse-LPDv2 into train/val split
    import random
    import shutil

    src_dirs = [
        ("v1_", extract_dir / "Diverse-LPD"),
        ("v2_", extract_dir / "Diverse-LPDv2"),
    ]

    all_samples = []
    for prefix, src in src_dirs:
        img_dir = src / "images"
        lbl_dir = src / "labels"
        if not img_dir.exists():
            continue
        for img in img_dir.iterdir():
            if img.suffix.lower() in ('.jpg', '.jpeg', '.png'):
                lbl = lbl_dir / (img.stem + '.txt')
                if lbl.exists():
                    all_samples.append((str(img), str(lbl), prefix + img.stem, img.suffix))

    print(f"Total paired samples: {len(all_samples)}")

    random.seed(42)
    random.shuffle(all_samples)
    split_idx = int(len(all_samples) * 0.9)

    for split in ['train', 'val']:
        (dataset_dir / split / 'images').mkdir(parents=True, exist_ok=True)
        (dataset_dir / split / 'labels').mkdir(parents=True, exist_ok=True)

    for img_path, lbl_path, new_name, ext in all_samples[:split_idx]:
        shutil.copy2(img_path, dataset_dir / 'train/images' / (new_name + ext))
        shutil.copy2(lbl_path, dataset_dir / 'train/labels' / (new_name + '.txt'))

    for img_path, lbl_path, new_name, ext in all_samples[split_idx:]:
        shutil.copy2(img_path, dataset_dir / 'val/images' / (new_name + ext))
        shutil.copy2(lbl_path, dataset_dir / 'val/labels' / (new_name + '.txt'))

    # Write data.yaml
    yaml_content = f"""path: {dataset_dir.resolve()}
train: train/images
val: val/images

nc: 1
names:
  0: license_plate
"""
    yaml_path.write_text(yaml_content)
    print(f"Dataset ready: {yaml_path}")
    return str(yaml_path)


def train(data_yaml: str):
    """Train YOLO26s on the plate dataset."""
    from ultralytics import YOLO

    print("="*60)
    print("TRAINING YOLO26s — Indian Plate Detection")
    print("="*60)

    # Load YOLO26s with COCO pretrained weights
    model = YOLO("yolo26s.pt")

    # Train
    results = model.train(
        data=data_yaml,
        epochs=50,
        imgsz=640,
        batch=16,
        device=0,
        save_period=10,
        patience=15,
        amp=True,
        workers=4,
        cos_lr=True,
        mosaic=1.0,
        close_mosaic=10,
        # Augmentations tuned for plates
        degrees=5.0,        # Slight rotation (plates aren't heavily tilted)
        translate=0.1,
        scale=0.5,          # Scale variation important (distant vs close plates)
        shear=2.0,
        perspective=0.0005,
        flipud=0.0,         # Never flip plates vertically
        fliplr=0.5,         # Horizontal flip OK
        hsv_h=0.015,
        hsv_s=0.4,          # Saturation variation (faded plates)
        hsv_v=0.4,          # Brightness variation (night/day)
        # Project config
        project="runs/detect",
        name="yolo26s_plate",
        exist_ok=True,
    )

    print(f"\nTraining complete!")
    print(f"Best mAP50: {results.results_dict.get('metrics/mAP50(B)', 'N/A')}")
    print(f"Best mAP50-95: {results.results_dict.get('metrics/mAP50-95(B)', 'N/A')}")

    return model


def export_models(model):
    """Export to multiple formats for deployment."""
    print("="*60)
    print("EXPORTING MODELS")
    print("="*60)

    best_path = Path("runs/detect/yolo26s_plate/weights/best.pt")
    if not best_path.exists():
        # Try alternate path
        best_path = Path("runs/detect/train/weights/best.pt")

    if best_path.exists():
        from ultralytics import YOLO
        best_model = YOLO(str(best_path))

        # TorchScript (universal, no deps)
        print("\nExporting TorchScript...")
        best_model.export(format="torchscript", imgsz=640)

        # OpenVINO INT8 (Intel CPUs — 2.5x speedup)
        print("\nExporting OpenVINO INT8...")
        try:
            best_model.export(format="openvino", int8=True, imgsz=640)
            print("OpenVINO INT8 export successful")
        except Exception as e:
            print(f"OpenVINO export failed (install openvino-dev): {e}")
            print("Run: pip install openvino-dev && retry export")

        # ONNX (cross-platform fallback)
        print("\nExporting ONNX...")
        best_model.export(format="onnx", imgsz=640, simplify=True)

        print(f"\nAll exports saved alongside: {best_path}")
        print(f"\nDeploy: copy best.pt → python_sidecar/models/anpr/plate_finetuned.pt")
    else:
        print(f"WARNING: best.pt not found at {best_path}")


def validate(model):
    """Run validation to print final metrics."""
    print("="*60)
    print("VALIDATION")
    print("="*60)

    best_path = Path("runs/detect/yolo26s_plate/weights/best.pt")
    if not best_path.exists():
        best_path = Path("runs/detect/train/weights/best.pt")

    if best_path.exists():
        from ultralytics import YOLO
        val_model = YOLO(str(best_path))
        metrics = val_model.val(imgsz=640)
        print(f"\nFinal Metrics:")
        print(f"  Precision: {metrics.box.mp:.3f}")
        print(f"  Recall:    {metrics.box.mr:.3f}")
        print(f"  mAP50:     {metrics.box.map50:.3f}")
        print(f"  mAP50-95:  {metrics.box.map:.3f}")


def main():
    install_deps()

    data_yaml = download_dataset()
    print(f"\nUsing dataset: {data_yaml}")

    model = train(data_yaml)
    export_models(model)
    validate(model)

    print("\n" + "="*60)
    print("DONE!")
    print("="*60)
    print(f"\nNext steps:")
    print(f"  1. Download best.pt from: runs/detect/yolo26s_plate/weights/best.pt")
    print(f"  2. Copy to your machine: python_sidecar/models/anpr/plate_finetuned.pt")
    print(f"  3. For Intel: also copy the _openvino_int8_model/ directory")
    print(f"  4. Restart sidecar: python3 main.py")


if __name__ == "__main__":
    main()
