from __future__ import annotations

import csv
import json
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

from .label_mapping import LABEL_METADATA, TARGET_LABELS
from .sources import DatasetSource


@dataclass(frozen=True)
class ManifestRow:
    row_id: str
    image_uri: str
    label_key: str
    crop_type: str
    split: str
    source_dataset: str
    source_split: str
    source_license: str
    raw_crop: str
    raw_label: str
    local_path: str = ""


def write_label_file(path: Path, labels: Iterable[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    label_values = list(labels or TARGET_LABELS)
    path.write_text("\n".join(label_values) + "\n", encoding="utf-8")


def write_label_map_csv(path: Path, labels: Iterable[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    label_values = list(labels or TARGET_LABELS)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["label_key", "crop_type", "display_name", "trainable_v2"],
        )
        writer.writeheader()
        for label_key in TARGET_LABELS:
            metadata = LABEL_METADATA[label_key]
            writer.writerow(
                {
                    "label_key": label_key,
                    "crop_type": metadata["crop_type"],
                    "display_name": metadata["display_name"],
                    "trainable_v2": str(label_key in label_values).lower(),
                }
            )


def write_manifest_csv(path: Path, rows: Iterable[ManifestRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(ManifestRow.__dataclass_fields__))
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def class_counts_by_split(
    rows: Iterable[ManifestRow],
    labels: Iterable[str] | None = None,
) -> dict[str, dict[str, int]]:
    counts: dict[str, Counter[str]] = defaultdict(Counter)
    label_values = list(labels or TARGET_LABELS)
    for row in rows:
        counts[row.split][row.label_key] += 1
    return {
        split: {label: counts[split].get(label, 0) for label in label_values}
        for split in ["train", "validation", "test"]
    }


def write_training_report_stub(
    path: Path,
    rows: list[ManifestRow],
    sources: Iterable[DatasetSource],
    skipped_rows: dict[str, int],
    labels: Iterable[str] | None = None,
    label_profile: str = "cropcare_v2_full",
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    label_values = list(labels or TARGET_LABELS)
    excluded_labels = [label for label in TARGET_LABELS if label not in label_values]
    payload = {
        "status": "dataset_prepared_not_trained",
        "model_family": "EfficientNetB0",
        "model_version": "cropcare_efficientnet_v2",
        "label_profile": label_profile,
        "input_shape": [1, 224, 224, 3],
        "output_labels": label_values,
        "excluded_labels": {
            label: "excluded_from_active_release_profile"
            for label in excluded_labels
        },
        "preprocessing": {
            "decision": "efficientnet_internal_preprocessing",
            "details": (
                "Keras EfficientNetB0 expects raw RGB pixel values in [0, 255] and "
                "performs its own preprocessing inside the exported model. Dart "
                "inference must not divide pixels by 255 when switching to v2 artifacts."
            ),
        },
        "metrics": {
            "validation_accuracy": None,
            "macro_f1": None,
            "confusion_matrix": None,
            "per_class_precision_recall": None,
        },
        "class_counts": class_counts_by_split(rows, label_values),
        "source_summary": [asdict(source) for source in sources],
        "skipped_rows": skipped_rows,
        "quality_gates": [
            "Populate validation_accuracy, macro_f1, confusion_matrix, and per-class precision/recall after training.",
            "Verify labels_v2.txt count matches the TFLite output tensor width.",
            "Run app/backend TFLite harness with one sample image per class before runtime replacement.",
        ],
    }
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
