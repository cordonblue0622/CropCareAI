from __future__ import annotations

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass, replace as dataclass_replace
from pathlib import Path

from .hf_assets import ensure_plantvillage_zip


DEFAULT_OUTPUT_DIR = Path("ml/artifacts/cropcare_v2")


@dataclass(frozen=True)
class TrainingRunConfig:
    output_dir: Path = DEFAULT_OUTPUT_DIR
    max_per_label: int | None = None
    min_per_label: int = 80
    epochs: int = 30
    batch_size: int = 32
    full: bool = False
    skip_install: bool = False
    plantvillage_zip_path: Path | None = None
    label_profile: str = "cropcare_v2_subset_100"
    digigreen_max_per_label: int = 1500


@dataclass(frozen=True)
class TrainingRunStep:
    name: str
    args: list[str]


def cpu_environment() -> dict[str, str]:
    env = dict(os.environ)
    env["CUDA_VISIBLE_DEVICES"] = "-1"
    env.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    return env


def build_run_steps(config: TrainingRunConfig) -> list[TrainingRunStep]:
    prepare_args = [
        sys.executable,
        "-m",
        "cropcare_training.prepare_dataset",
        "--output-dir",
        str(config.output_dir),
        "--download-images",
        "--label-profile",
        config.label_profile,
    ]
    if not config.full and config.max_per_label is not None:
        prepare_args.extend(["--max-per-label", str(config.max_per_label)])
    prepare_args.extend(
        [
            "--digigreen-max-per-label",
            str(config.digigreen_max_per_label),
            "--min-per-label",
            str(config.min_per_label),
            "--require-min-per-label",
        ]
    )
    if config.plantvillage_zip_path is not None:
        prepare_args.extend(["--plantvillage-zip-path", str(config.plantvillage_zip_path)])

    train_args = [
        sys.executable,
        "-m",
        "cropcare_training.train_efficientnet",
        "--data-dir",
        str(config.output_dir / "images_by_split"),
        "--output-dir",
        str(config.output_dir),
        "--epochs",
        str(config.epochs),
        "--batch-size",
        str(config.batch_size),
        "--label-profile",
        config.label_profile,
    ]
    return [
        TrainingRunStep("prepare-dataset", prepare_args),
        TrainingRunStep("train-efficientnet", train_args),
    ]


def run_training(config: TrainingRunConfig) -> None:
    env = cpu_environment()
    if config.plantvillage_zip_path is None:
        config = dataclass_replace(config, plantvillage_zip_path=ensure_plantvillage_zip())
    for step in build_run_steps(config):
        print(f"\n== {step.name} ==")
        print(" ".join(step.args))
        subprocess.run(step.args, check=True, env=env)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run CropCare v2 CPU training automation.")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--max-per-label", type=int, default=None)
    parser.add_argument("--digigreen-max-per-label", type=int, default=1500)
    parser.add_argument("--min-per-label", type=int, default=80)
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--plantvillage-zip-path", type=Path, default=None)
    parser.add_argument("--label-profile", default="cropcare_v2_subset_100")
    parser.add_argument(
        "--full",
        action="store_true",
        help="Use all mapped rows instead of the smoke-run max-per-label limit.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = TrainingRunConfig(
        output_dir=args.output_dir,
        max_per_label=args.max_per_label,
        min_per_label=args.min_per_label,
        epochs=args.epochs,
        batch_size=args.batch_size,
        full=args.full,
        plantvillage_zip_path=args.plantvillage_zip_path,
        label_profile=args.label_profile,
        digigreen_max_per_label=args.digigreen_max_per_label,
    )
    run_training(config)


if __name__ == "__main__":
    main()
