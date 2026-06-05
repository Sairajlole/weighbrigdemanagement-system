"""
Train DINOv2 linear probe for vehicle classification.

Uses labeled captures from the labeling UI (~/.weighbridge/vehicle_captures/).
Only trains a single Linear layer on top of frozen DINOv2 features.

Requirements:
- At least 30 labeled images per class (for meaningful training)
- At least 3 classes with sufficient images

Run: python scripts/train_vehicle_classifier.py
Output: models/vehicle/dinov2_head.pt
"""

import json
import sys
from collections import Counter
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import DataLoader, Dataset
from torchvision import transforms as T

CAPTURES_DIR = Path.home() / ".weighbridge" / "vehicle_captures"
LABELS_FILE = CAPTURES_DIR / "labels.jsonl"
OUTPUT_DIR = Path(__file__).parent.parent / "models" / "vehicle"
OUTPUT_PATH = OUTPUT_DIR / "dinov2_head.pt"
CLASSES_FILE = Path(__file__).parent.parent / "anpr" / "vehicle_classes.json"

MIN_SAMPLES_PER_CLASS = 30
MIN_CLASSES = 3


class VehicleDataset(Dataset):
    def __init__(self, samples: list[dict], class_to_idx: dict, transform):
        self.samples = samples
        self.class_to_idx = class_to_idx
        self.transform = transform

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        sample = self.samples[idx]
        img = cv2.imread(sample["path"])
        img = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        from PIL import Image
        pil_img = Image.fromarray(img)
        tensor = self.transform(pil_img)
        label = self.class_to_idx[sample["label"]]
        return tensor, label


def load_labeled_data() -> list[dict]:
    if not LABELS_FILE.exists():
        return []

    samples = []
    for line in LABELS_FILE.read_text().strip().split("\n"):
        if not line:
            continue
        record = json.loads(line)
        if record.get("labeled") and record.get("label"):
            img_path = CAPTURES_DIR / f"{record['id']}.jpg"
            if img_path.exists():
                record["path"] = str(img_path)
                samples.append(record)
    return samples


def main():
    print("Loading labeled data...")
    samples = load_labeled_data()

    if not samples:
        print("No labeled data found. Label some vehicles at http://localhost:8765/labeler first.")
        sys.exit(1)

    # Count per class
    class_counts = Counter(s["label"] for s in samples)
    print(f"\nTotal labeled: {len(samples)}")
    print(f"Classes: {len(class_counts)}")
    for cls, count in class_counts.most_common(20):
        status = "OK" if count >= MIN_SAMPLES_PER_CLASS else "LOW"
        print(f"  {cls}: {count} [{status}]")

    # Filter to classes with enough samples
    valid_classes = [cls for cls, count in class_counts.items() if count >= MIN_SAMPLES_PER_CLASS]
    if len(valid_classes) < MIN_CLASSES:
        print(f"\nNeed at least {MIN_CLASSES} classes with {MIN_SAMPLES_PER_CLASS}+ samples.")
        print(f"Currently have {len(valid_classes)} valid classes.")
        print("Keep labeling!")
        sys.exit(1)

    # Filter samples to valid classes only
    samples = [s for s in samples if s["label"] in valid_classes]
    class_to_idx = {cls: i for i, cls in enumerate(sorted(valid_classes))}
    idx_to_class = {i: cls for cls, i in class_to_idx.items()}
    num_classes = len(class_to_idx)

    print(f"\nTraining with {len(samples)} samples across {num_classes} classes")

    # Train/val split (80/20)
    import random
    random.seed(42)
    random.shuffle(samples)
    split = int(len(samples) * 0.8)
    train_samples = samples[:split]
    val_samples = samples[split:]

    # Transforms
    train_transform = T.Compose([
        T.RandomResizedCrop(224, scale=(0.7, 1.0)),
        T.RandomHorizontalFlip(),
        T.ColorJitter(brightness=0.3, contrast=0.3, saturation=0.2),
        T.ToTensor(),
        T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])
    val_transform = T.Compose([
        T.Resize(256, T.InterpolationMode.BICUBIC),
        T.CenterCrop(224),
        T.ToTensor(),
        T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
    ])

    train_ds = VehicleDataset(train_samples, class_to_idx, train_transform)
    val_ds = VehicleDataset(val_samples, class_to_idx, val_transform)
    train_loader = DataLoader(train_ds, batch_size=32, shuffle=True, num_workers=4)
    val_loader = DataLoader(val_ds, batch_size=32, shuffle=False, num_workers=4)

    # Load DINOv2 backbone (frozen)
    print("\nLoading DINOv2 ViT-B/14...")
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    backbone = torch.hub.load("facebookresearch/dinov2", "dinov2_vitb14", pretrained=True)
    backbone = backbone.eval().to(device)
    for p in backbone.parameters():
        p.requires_grad = False

    # Linear head
    head = nn.Linear(768, num_classes).to(device)
    optimizer = torch.optim.AdamW(head.parameters(), lr=0.001, weight_decay=0.01)
    scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=30)
    criterion = nn.CrossEntropyLoss()

    # Training loop
    print(f"Training linear head ({768} → {num_classes}) on {device}...")
    best_acc = 0.0

    for epoch in range(30):
        head.train()
        total_loss = 0.0
        correct = 0
        total = 0

        for imgs, labels in train_loader:
            imgs, labels = imgs.to(device), labels.to(device)
            with torch.no_grad():
                features = backbone(imgs)
            logits = head(features)
            loss = criterion(logits, labels)

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()

            total_loss += loss.item() * imgs.size(0)
            correct += (logits.argmax(1) == labels).sum().item()
            total += imgs.size(0)

        scheduler.step()
        train_acc = correct / total

        # Validation
        head.eval()
        val_correct = 0
        val_total = 0
        with torch.no_grad():
            for imgs, labels in val_loader:
                imgs, labels = imgs.to(device), labels.to(device)
                features = backbone(imgs)
                logits = head(features)
                val_correct += (logits.argmax(1) == labels).sum().item()
                val_total += imgs.size(0)

        val_acc = val_correct / val_total if val_total > 0 else 0

        if val_acc > best_acc:
            best_acc = val_acc
            OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
            torch.save(head.state_dict(), OUTPUT_PATH)

        if (epoch + 1) % 5 == 0:
            print(f"  Epoch {epoch+1}/30: train_acc={train_acc:.3f}, val_acc={val_acc:.3f}, best={best_acc:.3f}")

    print(f"\nDone! Best val accuracy: {best_acc:.3f}")
    print(f"Model saved: {OUTPUT_PATH}")

    # Save class mapping
    mapping_path = OUTPUT_DIR / "class_mapping.json"
    mapping_path.write_text(json.dumps(idx_to_class, indent=2))
    print(f"Class mapping saved: {mapping_path}")


if __name__ == "__main__":
    main()
