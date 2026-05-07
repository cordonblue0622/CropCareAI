from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class DatasetSource:
    dataset_id: str
    license_id: str | None
    task: str
    production_allowed: bool
    role: str
    notes: str


DATASET_SOURCES: tuple[DatasetSource, ...] = (
    DatasetSource(
        dataset_id="DigiGreen/Crop_Disease_Images",
        license_id="cc-by-4.0",
        task="image-classification",
        production_allowed=True,
        role="field-style expert annotations for current app crops",
        notes=(
            "Use rows whose crop/diagnosis pair maps to CropCare labels. "
            "Rows can contain multiple diagnoses; keep only unambiguous mappings."
        ),
    ),
    DatasetSource(
        dataset_id="mohanty/PlantVillage",
        license_id="cc-by-sa-3.0",
        task="image-classification",
        production_allowed=True,
        role="clean leaf images for tomato, pepper, and squash classes",
        notes=(
            "Share-alike obligations must be approved before shipping. "
            "Some HF rows may require inferring the label from image paths."
        ),
    ),
    DatasetSource(
        dataset_id="wellCh4n/tomato-leaf-disease-image",
        license_id=None,
        task="image-classification",
        production_allowed=False,
        role="research reference only",
        notes="License is missing on the dataset card; do not train shipped weights from it.",
    ),
    DatasetSource(
        dataset_id="avinashhm/plant-disease-classification",
        license_id=None,
        task="image-classification",
        production_allowed=False,
        role="research reference only",
        notes="License is missing on the dataset card; useful for label comparison only.",
    ),
    DatasetSource(
        dataset_id="Mobiusi/Crop-Pest-and-Disease-Classification-Dataset",
        license_id="cc-by-nc-sa-4.0",
        task="image-classification",
        production_allowed=False,
        role="excluded source",
        notes="Non-commercial license is incompatible with production deployment.",
    ),
    DatasetSource(
        dataset_id="susnato/plant_disease_detection_processed",
        license_id="cc-by-4.0",
        task="object-detection",
        production_allowed=False,
        role="future object-detection phase reference",
        notes="Object-detection data is intentionally out of scope for classifier v1 expansion.",
    ),
)


def production_sources() -> list[DatasetSource]:
    return [source for source in DATASET_SOURCES if source.production_allowed]


def research_only_sources() -> list[DatasetSource]:
    return [source for source in DATASET_SOURCES if not source.production_allowed]


def source_for_dataset(dataset_id: str) -> DatasetSource:
    for source in DATASET_SOURCES:
        if source.dataset_id == dataset_id:
            return source
    raise KeyError(f"Unknown dataset source: {dataset_id}")
