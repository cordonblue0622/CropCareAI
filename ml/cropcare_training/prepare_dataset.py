from __future__ import annotations

import argparse
import hashlib
import shutil
import urllib.request
import zipfile
from collections import Counter, defaultdict
from dataclasses import replace
from pathlib import Path
from typing import Any

from .label_mapping import (
    TARGET_LABELS,
    crop_type_for_label,
    map_digigreen_row,
    map_plantvillage_label,
    validate_target_label_metadata,
)
from .label_profiles import labels_for_profile
from .manifest import (
    ManifestRow,
    write_label_file,
    write_label_map_csv,
    write_manifest_csv,
    write_training_report_stub,
)
from .sources import production_sources, source_for_dataset


DEFAULT_OUTPUT_DIR = Path("ml/artifacts/cropcare_v2")
load_dataset = None


def load_dataset_split(dataset_id: str, split: str):
    global load_dataset
    if load_dataset is None:
        try:
            from datasets import load_dataset as datasets_load_dataset
        except ImportError as exc:
            raise RuntimeError(
                "Install ML dependencies first: python -m pip install -r ml/requirements.txt"
            ) from exc
        load_dataset = datasets_load_dataset
    return load_dataset(dataset_id, name="default", split=split)


def deterministic_split(row_key: str) -> str:
    bucket = int(hashlib.sha1(row_key.encode("utf-8")).hexdigest()[:8], 16) % 100
    if bucket < 80:
        return "train"
    if bucket < 90:
        return "validation"
    return "test"


def assign_balanced_splits(
    rows: list[ManifestRow],
    *,
    require_validation: bool = False,
) -> list[ManifestRow]:
    by_label: dict[str, list[ManifestRow]] = defaultdict(list)
    for row in rows:
        by_label[row.label_key].append(row)

    balanced: list[ManifestRow] = []
    for label_key in sorted(by_label):
        label_rows = sorted(by_label[label_key], key=lambda row: row.row_id)
        if require_validation and len(label_rows) < 2:
            continue
        train_count, validation_count = _split_counts(len(label_rows))
        for index, row in enumerate(label_rows):
            if index < train_count:
                split = "train"
            elif index < train_count + validation_count:
                split = "validation"
            else:
                split = "test"
            balanced.append(replace(row, split=split))
    return sorted(balanced, key=lambda row: (row.split, row.label_key, row.row_id))


def _split_counts(row_count: int) -> tuple[int, int]:
    if row_count == 1:
        return 1, 0
    if row_count == 2:
        return 1, 1

    validation_count = max(1, row_count // 10)
    test_count = max(1, row_count // 10)
    train_count = row_count - validation_count - test_count
    return train_count, validation_count


def assert_minimum_label_counts(
    rows: list[ManifestRow],
    *,
    min_per_label: int,
    labels: list[str] | tuple[str, ...] = TARGET_LABELS,
) -> None:
    counts = Counter(row.label_key for row in rows)
    short_labels = [
        f"{label_key}={counts.get(label_key, 0)}/{min_per_label}"
        for label_key in labels
        if counts.get(label_key, 0) < min_per_label
    ]
    if short_labels:
        raise ValueError(
            "Not enough prepared images for training. "
            f"Need at least {min_per_label} per label; short labels: "
            + ", ".join(short_labels)
        )


def filter_rows_to_labels(
    rows: list[ManifestRow],
    labels: list[str] | tuple[str, ...],
) -> list[ManifestRow]:
    allowed = set(labels)
    return [row for row in rows if row.label_key in allowed]


def _enforce_per_source_caps(
    rows: list[ManifestRow],
    *,
    digigreen_max: int | None,
    plantvillage_max: int | None,
) -> list[ManifestRow]:
    """Apply per-(dataset, label) caps so DigiGreen and PlantVillage can have
    different limits.

    DigiGreen images come from real fields and are noisier — we cap them
    so they don't drown out PlantVillage's lab quality. PlantVillage is
    typically uncapped (None) so the model trains on every image.
    """
    counts: dict[tuple[str, str], int] = {}
    kept: list[ManifestRow] = []
    for row in rows:
        cap = (
            digigreen_max
            if row.source_dataset == "DigiGreen/Crop_Disease_Images"
            else plantvillage_max
        )
        key = (row.source_dataset, row.label_key)
        if cap is not None and counts.get(key, 0) >= cap:
            continue
        counts[key] = counts.get(key, 0) + 1
        kept.append(row)
    return kept


def infer_plantvillage_label(row: dict[str, Any]) -> str | None:
    for key in ("label", "label_name", "class", "raw_label"):
        value = row.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()

    text = row.get("text")
    if isinstance(text, str) and text.strip():
        parts = Path(text.replace("\\", "/")).parts
        for part in reversed(parts[:-1]):
            mapped = map_plantvillage_label(part)
            if mapped:
                return part

    image = row.get("image")
    candidates: list[str] = []
    if isinstance(image, dict):
        for key in ("path", "src", "filename"):
            value = image.get(key)
            if isinstance(value, str):
                candidates.append(value)
    else:
        filename = getattr(image, "filename", None)
        if isinstance(filename, str):
            candidates.append(filename)

    for candidate in candidates:
        parts = Path(candidate.replace("\\", "/")).parts
        for part in reversed(parts[:-1]):
            mapped = map_plantvillage_label(part)
            if mapped:
                return part
    return None


def build_manifest(
    *,
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    max_per_label: int | None = None,
    digigreen_max_per_label: int | None = None,
    download_images: bool = False,
    include_plantvillage: bool = True,
    include_digigreen: bool = True,
    plantvillage_zip_path: Path | None = None,
    min_per_label: int | None = None,
    require_min_per_label: bool = False,
    label_profile: str = "cropcare_v2_full",
    labels: list[str] | None = None,
) -> list[ManifestRow]:
    validate_target_label_metadata()
    active_labels = labels or labels_for_profile(label_profile)
    active_label_set = set(active_labels)
    rows: list[ManifestRow] = []
    skipped_rows: Counter[str] = Counter()
    per_label: Counter[str] = Counter()

    # Per-source caps applied as a separate pass below; the in-loop
    # `should_keep` only enforces the global max_per_label budget so
    # DigiGreen and PlantVillage rows are gathered without prematurely
    # dropping anything that the per-source cap would later allow.
    def should_keep(label_key: str) -> bool:
        return max_per_label is None or per_label[label_key] < max_per_label

    if include_digigreen:
        dataset_id = "DigiGreen/Crop_Disease_Images"
        source = source_for_dataset(dataset_id)
        dataset = load_dataset_split(dataset_id, "train")
        for index, row in enumerate(dataset):
            mapped = map_digigreen_row(
                crop=str(row.get("crop", "")),
                diagnosis=str(row.get("diagnosis", "")),
            )
            if mapped is None:
                skipped_rows[f"{dataset_id}:unmapped"] += 1
                continue
            if mapped.label_key not in active_label_set:
                skipped_rows[f"{dataset_id}:inactive_label"] += 1
                continue
            if not should_keep(mapped.label_key):
                skipped_rows[f"{dataset_id}:max_per_label"] += 1
                continue

            row_id = f"digigreen-{index}"
            image_uri = str(row.get("image_url", ""))
            rows.append(
                ManifestRow(
                    row_id=row_id,
                    image_uri=image_uri,
                    label_key=mapped.label_key,
                    crop_type=mapped.crop_type,
                    split=deterministic_split(f"{dataset_id}:{row_id}:{mapped.label_key}"),
                    source_dataset=dataset_id,
                    source_split="train",
                    source_license=source.license_id or "",
                    raw_crop=mapped.raw_crop,
                    raw_label=mapped.raw_diagnosis,
                )
            )
            per_label[mapped.label_key] += 1

    if include_plantvillage:
        dataset_id = "mohanty/PlantVillage"
        source = source_for_dataset(dataset_id)
        for source_split in ("train", "test"):
            dataset = load_dataset_split(dataset_id, source_split)
            for index, row in enumerate(dataset):
                raw_label = infer_plantvillage_label(row)
                label_key = map_plantvillage_label(raw_label)
                if label_key is None:
                    skipped_rows[f"{dataset_id}:unmapped"] += 1
                    continue
                if label_key not in active_label_set:
                    skipped_rows[f"{dataset_id}:inactive_label"] += 1
                    continue
                if not should_keep(label_key):
                    skipped_rows[f"{dataset_id}:max_per_label"] += 1
                    continue

                row_id = f"plantvillage-{source_split}-{index}"
                image_uri = _image_uri(row.get("image")) or _text_image_uri(row)

                rows.append(
                    ManifestRow(
                        row_id=row_id,
                        image_uri=image_uri,
                        label_key=label_key,
                        crop_type=crop_type_for_label(label_key),
                        split=deterministic_split(f"{dataset_id}:{row_id}:{label_key}"),
                        source_dataset=dataset_id,
                        source_split=source_split,
                        source_license=source.license_id or "",
                        raw_crop=crop_type_for_label(label_key),
                        raw_label=raw_label or "",
                    )
                )
                per_label[label_key] += 1

    output_dir.mkdir(parents=True, exist_ok=True)
    rows = _enforce_per_source_caps(
        rows,
        digigreen_max=digigreen_max_per_label,
        plantvillage_max=max_per_label,
    )
    rows = assign_balanced_splits(rows, require_validation=download_images)
    if download_images:
        image_root = output_dir / "images_by_split"
        if image_root.exists():
            shutil.rmtree(image_root)
        rows = _persist_manifest_images(
            rows=rows,
            output_dir=output_dir,
            plantvillage_zip_path=plantvillage_zip_path,
        )

    if require_min_per_label:
        if min_per_label is None:
            raise ValueError("--require-min-per-label needs --min-per-label")
        assert_minimum_label_counts(
            rows,
            min_per_label=min_per_label,
            labels=active_labels,
        )

    write_manifest_csv(output_dir / "dataset_manifest_v2.csv", rows)
    write_label_file(output_dir / "labels_v2.txt", active_labels)
    write_label_map_csv(output_dir / "label_map_v2.csv", active_labels)
    write_training_report_stub(
        output_dir / "training_report_v2.json",
        rows,
        production_sources(),
        dict(skipped_rows),
        labels=active_labels,
        label_profile=label_profile,
    )
    return rows


def _image_uri(image: Any) -> str:
    if isinstance(image, dict):
        for key in ("src", "path", "filename"):
            value = image.get(key)
            if isinstance(value, str) and value:
                return value
    filename = getattr(image, "filename", None)
    return filename if isinstance(filename, str) else ""


def _text_image_uri(row: dict[str, Any]) -> str:
    value = row.get("image_path") or row.get("text")
    return value if isinstance(value, str) else ""


def _download_image(
    *,
    image_uri: str,
    output_dir: Path,
    split: str,
    label_key: str,
    filename: str,
) -> str:
    target = output_dir / "images_by_split" / split / label_key / filename
    target.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(image_uri, target)
    return str(target)


def _persist_manifest_images(
    *,
    rows: list[ManifestRow],
    output_dir: Path,
    plantvillage_zip_path: Path | None = None,
) -> list[ManifestRow]:
    persisted: list[ManifestRow] = []
    plantvillage_zip: zipfile.ZipFile | None = None
    if plantvillage_zip_path is not None:
        plantvillage_zip = zipfile.ZipFile(plantvillage_zip_path)

    for row in rows:
        filename = f"{row.row_id}.jpg"
        try:
            if row.image_uri.startswith(("http://", "https://")):
                local_path = _download_image(
                    image_uri=row.image_uri,
                    output_dir=output_dir,
                    split=row.split,
                    label_key=row.label_key,
                    filename=filename,
                )
            elif row.source_dataset == "mohanty/PlantVillage" and plantvillage_zip is not None:
                target = output_dir / "images_by_split" / row.split / row.label_key / filename
                target.parent.mkdir(parents=True, exist_ok=True)
                with plantvillage_zip.open(row.image_uri) as source, target.open("wb") as destination:
                    shutil.copyfileobj(source, destination)
                local_path = str(target)
            elif row.image_uri:
                target = output_dir / "images_by_split" / row.split / row.label_key / filename
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(row.image_uri, target)
                local_path = str(target)
            else:
                continue
        except (KeyError, OSError):
            continue
        persisted.append(replace(row, local_path=local_path))
    if plantvillage_zip is not None:
        plantvillage_zip.close()
    return persisted


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Prepare CropCare v2 HF training data.")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--max-per-label", type=int, default=None)
    parser.add_argument(
        "--digigreen-max-per-label",
        type=int,
        default=None,
        help="Optional separate per-(label) cap for DigiGreen rows.",
    )
    parser.add_argument(
        "--download-images",
        action="store_true",
        help="Persist images under output-dir/images_by_split for TensorFlow training.",
    )
    parser.add_argument("--skip-plantvillage", action="store_true")
    parser.add_argument("--skip-digigreen", action="store_true")
    parser.add_argument("--label-profile", default="cropcare_v2_full")
    parser.add_argument(
        "--plantvillage-zip-path",
        type=Path,
        default=None,
        help="Optional local mohanty/PlantVillage data.zip used to persist PlantVillage images.",
    )
    parser.add_argument("--min-per-label", type=int, default=None)
    parser.add_argument(
        "--require-min-per-label",
        action="store_true",
        help="Fail before training if any target label has fewer than min-per-label prepared rows.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rows = build_manifest(
        output_dir=args.output_dir,
        max_per_label=args.max_per_label,
        digigreen_max_per_label=args.digigreen_max_per_label,
        download_images=args.download_images,
        include_plantvillage=not args.skip_plantvillage,
        include_digigreen=not args.skip_digigreen,
        plantvillage_zip_path=args.plantvillage_zip_path,
        min_per_label=args.min_per_label,
        require_min_per_label=args.require_min_per_label,
        label_profile=args.label_profile,
    )
    print(f"Prepared {len(rows)} mapped rows in {args.output_dir}")
    missing = [label for label in TARGET_LABELS if all(row.label_key != label for row in rows)]
    if missing:
        print(f"Warning: labels with zero mapped rows: {', '.join(missing)}")


if __name__ == "__main__":
    main()
