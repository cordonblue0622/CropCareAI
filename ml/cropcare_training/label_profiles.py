from __future__ import annotations

from .label_mapping import TARGET_LABELS


SUBSET_100_LABELS: tuple[str, ...] = (
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
    "squash_powdery_mildew",
)

# 16 labels matching the legacy pre-v2 baseline. Squash is intentionally
# excluded because the older baseline did not include squash classes.
BASE_PARITY_LABELS: tuple[str, ...] = (
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
)

LABEL_PROFILES: dict[str, tuple[str, ...]] = {
    "cropcare_v2_subset_100": SUBSET_100_LABELS,
    "cropcare_v2_full": tuple(TARGET_LABELS),
    "cropcare_v2_base_parity": BASE_PARITY_LABELS,
}


def labels_for_profile(profile: str) -> list[str]:
    try:
        return list(LABEL_PROFILES[profile])
    except KeyError as exc:
        known = ", ".join(sorted(LABEL_PROFILES))
        raise ValueError(f"Unknown label profile '{profile}'. Known profiles: {known}") from exc


def excluded_labels_for_profile(profile: str) -> list[str]:
    active = set(labels_for_profile(profile))
    return [label for label in TARGET_LABELS if label not in active]
