from __future__ import annotations

import re
from dataclasses import dataclass


TARGET_LABELS: list[str] = [
    "tomato_bacterial_spot",
    "tomato_early_blight",
    "tomato_late_blight",
    "tomato_leaf_mold",
    "tomato_septoria_leaf_spot",
    "tomato_spider_mites",
    "tomato_target_spot",
    "tomato_yellow_leaf_curl_virus",
    "tomato_mosaic_virus",
    "tomato_healthy",
    "pepper_bacterial_spot",
    "pepper_healthy",
    "eggplant_healthy",
    "eggplant_insect_pest",
    "eggplant_leaf_spot",
    "eggplant_mosaic_virus",
    "squash_powdery_mildew",
]

TARGET_LABEL_SET = frozenset(TARGET_LABELS)

LABEL_METADATA: dict[str, dict[str, str]] = {
    "tomato_bacterial_spot": {"crop_type": "tomato", "display_name": "Tomato Bacterial Spot"},
    "tomato_early_blight": {"crop_type": "tomato", "display_name": "Tomato Early Blight"},
    "tomato_late_blight": {"crop_type": "tomato", "display_name": "Tomato Late Blight"},
    "tomato_leaf_mold": {"crop_type": "tomato", "display_name": "Tomato Leaf Mold"},
    "tomato_septoria_leaf_spot": {"crop_type": "tomato", "display_name": "Tomato Septoria Leaf Spot"},
    "tomato_spider_mites": {"crop_type": "tomato", "display_name": "Tomato Spider Mites"},
    "tomato_target_spot": {"crop_type": "tomato", "display_name": "Tomato Target Spot"},
    "tomato_yellow_leaf_curl_virus": {
        "crop_type": "tomato",
        "display_name": "Tomato Yellow Leaf Curl Virus",
    },
    "tomato_mosaic_virus": {"crop_type": "tomato", "display_name": "Tomato Mosaic Virus"},
    "tomato_healthy": {"crop_type": "tomato", "display_name": "Tomato Healthy"},
    "pepper_bacterial_spot": {"crop_type": "pepper", "display_name": "Bell Pepper Bacterial Spot"},
    "pepper_healthy": {"crop_type": "pepper", "display_name": "Bell Pepper Healthy"},
    "eggplant_healthy": {"crop_type": "eggplant", "display_name": "Eggplant Healthy"},
    "eggplant_insect_pest": {"crop_type": "eggplant", "display_name": "Eggplant Insect Pest"},
    "eggplant_leaf_spot": {"crop_type": "eggplant", "display_name": "Eggplant Leaf Spot"},
    "eggplant_mosaic_virus": {"crop_type": "eggplant", "display_name": "Eggplant Mosaic Virus"},
    "squash_powdery_mildew": {"crop_type": "squash", "display_name": "Squash Powdery Mildew"},
}

PLANTVILLAGE_LABEL_MAP: dict[str, str] = {
    "Pepper,_bell___Bacterial_spot": "pepper_bacterial_spot",
    "Pepper__bell___Bacterial_spot": "pepper_bacterial_spot",
    "Pepper,_bell___healthy": "pepper_healthy",
    "Pepper__bell___healthy": "pepper_healthy",
    "Squash___Powdery_mildew": "squash_powdery_mildew",
    "Tomato___Bacterial_spot": "tomato_bacterial_spot",
    "Tomato_Bacterial_spot": "tomato_bacterial_spot",
    "Tomato___Early_blight": "tomato_early_blight",
    "Tomato_Early_blight": "tomato_early_blight",
    "Tomato___Late_blight": "tomato_late_blight",
    "Tomato_Late_blight": "tomato_late_blight",
    "Tomato___Leaf_Mold": "tomato_leaf_mold",
    "Tomato_Leaf_Mold": "tomato_leaf_mold",
    "Tomato___Septoria_leaf_spot": "tomato_septoria_leaf_spot",
    "Tomato_Septoria_leaf_spot": "tomato_septoria_leaf_spot",
    "Tomato___Spider_mites Two-spotted_spider_mite": "tomato_spider_mites",
    "Tomato_Spider_mites_Two_spotted_spider_mite": "tomato_spider_mites",
    "Tomato___Target_Spot": "tomato_target_spot",
    "Tomato__Target_Spot": "tomato_target_spot",
    "Tomato___Tomato_Yellow_Leaf_Curl_Virus": "tomato_yellow_leaf_curl_virus",
    "Tomato__Tomato_YellowLeaf__Curl_Virus": "tomato_yellow_leaf_curl_virus",
    "Tomato___Tomato_mosaic_virus": "tomato_mosaic_virus",
    "Tomato__Tomato_mosaic_virus": "tomato_mosaic_virus",
    "Tomato___healthy": "tomato_healthy",
    "Tomato_healthy": "tomato_healthy",
}

CROP_ALIASES: dict[str, str] = {
    "tomato": "tomato",
    "pepper": "pepper",
    "bellpepper": "pepper",
    "capsicum": "pepper",
    "chilli": "pepper",
    "chili": "pepper",
    "chilipepper": "pepper",
    "brinjal": "eggplant",
    "eggplant": "eggplant",
    "aubergine": "eggplant",
    "squash": "squash",
    "pumpkin": "squash",
}

DIGIGREEN_DIAGNOSIS_MAP: dict[str, dict[str, str]] = {
    "tomato": {
        "healthy": "tomato_healthy",
        "bacterialspot": "tomato_bacterial_spot",
        "bacterialleafspot": "tomato_bacterial_spot",
        "earlyblight": "tomato_early_blight",
        "lateblight": "tomato_late_blight",
        "leafmold": "tomato_leaf_mold",
        "septorialeafspot": "tomato_septoria_leaf_spot",
        "spidermites": "tomato_spider_mites",
        "mites": "tomato_spider_mites",
        "targetspot": "tomato_target_spot",
        "leafcurlvirus": "tomato_yellow_leaf_curl_virus",
        "tomatoyellowleafcurlvirus": "tomato_yellow_leaf_curl_virus",
        "mosaicvirus": "tomato_mosaic_virus",
        "tobaccomosaicvirus": "tomato_mosaic_virus",
    },
    "pepper": {
        "healthy": "pepper_healthy",
        "bacterialspot": "pepper_bacterial_spot",
        "bacterialleafspot": "pepper_bacterial_spot",
    },
    "eggplant": {
        "healthy": "eggplant_healthy",
        "mites": "eggplant_insect_pest",
        "aphids": "eggplant_insect_pest",
        "thrips": "eggplant_insect_pest",
        "shootandfruitborer": "eggplant_insect_pest",
        "fruitborer": "eggplant_insect_pest",
        "leafminer": "eggplant_insect_pest",
        "leafspot": "eggplant_leaf_spot",
        "cercosporaleafspot": "eggplant_leaf_spot",
        "phomopsisblight": "eggplant_leaf_spot",
        "mosaicvirus": "eggplant_mosaic_virus",
        "tobaccomosaicvirus": "eggplant_mosaic_virus",
    },
    "squash": {
        "powderymildew": "squash_powdery_mildew",
    },
}


@dataclass(frozen=True)
class MappedLabel:
    label_key: str
    crop_type: str
    raw_crop: str
    raw_diagnosis: str


def normalize_key(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def split_diagnoses(value: str) -> list[str]:
    return [item.strip() for item in value.split(";") if item.strip()]


def crop_type_for_label(label_key: str) -> str:
    return LABEL_METADATA[label_key]["crop_type"]


def map_plantvillage_label(raw_label: str | None) -> str | None:
    if not raw_label:
        return None
    label = raw_label.strip()
    mapped = PLANTVILLAGE_LABEL_MAP.get(label)
    if mapped:
        return mapped

    normalized_lookup = {normalize_key(key): value for key, value in PLANTVILLAGE_LABEL_MAP.items()}
    return normalized_lookup.get(normalize_key(label))


def map_digigreen_row(crop: str, diagnosis: str) -> MappedLabel | None:
    crop_type = CROP_ALIASES.get(normalize_key(crop))
    if crop_type is None:
        return None

    crop_diagnoses = DIGIGREEN_DIAGNOSIS_MAP[crop_type]
    mapped_labels = {
        crop_diagnoses[normalize_key(part)]
        for part in split_diagnoses(diagnosis)
        if normalize_key(part) in crop_diagnoses
    }

    if len(mapped_labels) != 1:
        return None

    label_key = next(iter(mapped_labels))
    return MappedLabel(
        label_key=label_key,
        crop_type=crop_type_for_label(label_key),
        raw_crop=crop,
        raw_diagnosis=diagnosis,
    )


def validate_target_label_metadata() -> None:
    missing = [label for label in TARGET_LABELS if label not in LABEL_METADATA]
    extra = [label for label in LABEL_METADATA if label not in TARGET_LABEL_SET]
    if missing or extra:
        raise ValueError(f"Label metadata mismatch: missing={missing} extra={extra}")
