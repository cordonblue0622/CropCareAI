from __future__ import annotations

import os
import shutil
import urllib.request
from pathlib import Path


PLANTVILLAGE_DATA_ZIP_URL = (
    "https://huggingface.co/datasets/mohanty/PlantVillage/resolve/main/data.zip"
)
DEFAULT_DATA_DIR = Path("ml/data")


def ensure_plantvillage_zip(
    *,
    cache_dir: Path = DEFAULT_DATA_DIR,
    hf_token: str | None = None,
) -> Path:
    cache_dir.mkdir(parents=True, exist_ok=True)
    target = cache_dir / "plantvillage_data.zip"
    if target.exists() and target.stat().st_size > 0:
        return target

    token = hf_token or os.environ.get("HF_TOKEN")
    request = urllib.request.Request(PLANTVILLAGE_DATA_ZIP_URL)
    if token:
        request.add_header("Authorization", f"Bearer {token}")

    with urllib.request.urlopen(request) as response, target.open("wb") as handle:
        shutil.copyfileobj(response, handle)
    return target
