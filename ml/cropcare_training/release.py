from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_OUTPUT_DIR = Path("ml/artifacts/cropcare_v2")
DEFAULT_ASSETS_DIR = Path("assets/models")
MODEL_FILENAME = "cropcare_efficientnet_v2.tflite"
LABELS_FILENAME = "labels_v2.txt"
DEFAULT_BASE_MODEL_PATH = Path("assets/models/cropcare_efficientnet_v2.tflite")
DEFAULT_BASE_LABELS_PATH = Path("assets/models/labels_v2.txt")


@dataclass(frozen=True)
class ReleaseConfig:
    output_dir: Path = DEFAULT_OUTPUT_DIR
    label_profile: str = "cropcare_v2_subset_100"
    max_per_label: int | None = None
    min_per_label: int = 80
    epochs: int = 30
    batch_size: int = 32
    plantvillage_zip_path: Path | None = None
    build_android: bool = False
    flutter_command: str = "flutter"
    base_model_path: Path = DEFAULT_BASE_MODEL_PATH
    base_labels_path: Path = DEFAULT_BASE_LABELS_PATH
    digigreen_max_per_label: int = 1500


@dataclass(frozen=True)
class ReleaseStep:
    name: str
    args: list[str]


def build_release_steps(config: ReleaseConfig) -> list[ReleaseStep]:
    train_args = [
        sys.executable,
        "-m",
        "cropcare_training.automation",
        "--output-dir",
        str(config.output_dir),
        "--label-profile",
        config.label_profile,
        "--min-per-label",
        str(config.min_per_label),
        "--epochs",
        str(config.epochs),
        "--batch-size",
        str(config.batch_size),
        "--digigreen-max-per-label",
        str(config.digigreen_max_per_label),
    ]
    if config.max_per_label is not None:
        train_args.extend(["--max-per-label", str(config.max_per_label)])
    if config.plantvillage_zip_path is not None:
        train_args.extend(["--plantvillage-zip-path", str(config.plantvillage_zip_path)])

    compare_args = [
        sys.executable,
        "-m",
        "cropcare_training.compare_models",
        "--base",
        str(config.base_model_path),
        "--base-labels",
        str(config.base_labels_path),
        "--candidate",
        str(config.output_dir / "cropcare_efficientnet_v2.tflite"),
        "--candidate-labels",
        str(config.output_dir / "labels_v2.txt"),
        "--test-dir",
        str(config.output_dir / "images_by_split" / "test"),
        "--report-dir",
        str(config.output_dir),
    ]

    steps = [
        ReleaseStep("train-efficientnet-release", train_args),
        ReleaseStep("compare-models", compare_args),
        ReleaseStep(
            "promote-artifacts",
            [
                sys.executable,
                "-m",
                "cropcare_training.release",
                "promote",
                "--output-dir",
                str(config.output_dir),
            ],
        ),
        ReleaseStep("flutter-test", [config.flutter_command, "test"]),
    ]
    if config.build_android:
        steps.append(
            ReleaseStep(
                "flutter-build-apk",
                [config.flutter_command, "build", "apk", "--release"],
            )
        )
    return steps


def run_release(config: ReleaseConfig) -> None:
    for step in build_release_steps(config):
        print(f"\n== {step.name} ==")
        print(" ".join(step.args))
        subprocess.run(step.args, check=True)


def validate_metric_gates(
    report: dict[str, Any],
    *,
    min_macro_f1: float = 0.90,
    min_recall: float = 0.80,
) -> None:
    metrics = report.get("metrics") or {}
    macro_f1 = float(metrics.get("macro_f1") or 0.0)
    failures: list[str] = []
    if macro_f1 < min_macro_f1:
        failures.append(f"macro_f1 {macro_f1:.4f} < {min_macro_f1:.4f}")

    per_class = metrics.get("per_class_precision_recall") or {}
    for label, label_metrics in per_class.items():
        if label in {"accuracy", "macro avg", "weighted avg"}:
            continue
        recall = float((label_metrics or {}).get("recall") or 0.0)
        if recall < min_recall:
            failures.append(f"{label} recall {recall:.4f} < {min_recall:.4f}")

    if failures:
        raise ValueError("Training metric gates failed: " + ", ".join(failures))


def validate_tflite_output_shape(model_path: Path, labels_path: Path) -> None:
    try:
        import tensorflow as tf
    except ImportError as exc:
        raise RuntimeError(
            "Install ML dependencies first: python -m pip install -r ml/requirements.txt"
        ) from exc

    labels = _read_labels(labels_path)
    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    output_shape = interpreter.get_output_details()[0]["shape"].tolist()
    output_width = int(output_shape[-1])
    if output_width != len(labels):
        raise ValueError(
            f"TFLite output width {output_width} does not match label count {len(labels)}"
        )


def promote_artifacts(
    *,
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    assets_dir: Path = DEFAULT_ASSETS_DIR,
    validate_shape: bool = True,
) -> None:
    model_path = output_dir / MODEL_FILENAME
    labels_path = output_dir / LABELS_FILENAME
    report_path = output_dir / "training_report_v2.json"
    comparison_path = output_dir / "comparison_report.json"
    for required in (model_path, labels_path, report_path, comparison_path):
        if not required.exists():
            raise FileNotFoundError(f"Missing release artifact: {required}")

    report = json.loads(report_path.read_text(encoding="utf-8"))
    validate_metric_gates(report)
    if validate_shape:
        validate_tflite_output_shape(model_path, labels_path)

    comparison = json.loads(comparison_path.read_text(encoding="utf-8"))
    verdict = comparison.get("verdict") or {}
    if verdict.get("status") != "PROMOTE":
        reasons = ", ".join(verdict.get("reasons") or ["no reasons recorded"])
        raise ValueError(f"Comparison harness verdict BLOCK: {reasons}")

    assets_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(model_path, assets_dir / MODEL_FILENAME)
    shutil.copy2(labels_path, assets_dir / LABELS_FILENAME)


def _read_labels(labels_path: Path) -> list[str]:
    return [
        label.strip()
        for label in labels_path.read_text(encoding="utf-8").splitlines()
        if label.strip()
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run or promote a CropCare model release.")
    subparsers = parser.add_subparsers(dest="command")

    run_parser = subparsers.add_parser("run")
    run_parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    run_parser.add_argument("--label-profile", default="cropcare_v2_subset_100")
    run_parser.add_argument("--max-per-label", type=int, default=None)
    run_parser.add_argument("--min-per-label", type=int, default=80)
    run_parser.add_argument("--epochs", type=int, default=30)
    run_parser.add_argument("--batch-size", type=int, default=32)
    run_parser.add_argument("--plantvillage-zip-path", type=Path, default=None)
    run_parser.add_argument(
        "--base-model-path", type=Path, default=DEFAULT_BASE_MODEL_PATH
    )
    run_parser.add_argument(
        "--base-labels-path", type=Path, default=DEFAULT_BASE_LABELS_PATH
    )
    run_parser.add_argument("--digigreen-max-per-label", type=int, default=1500)
    run_parser.add_argument("--build-android", action="store_true")
    run_parser.add_argument("--flutter-command", default="flutter")

    promote_parser = subparsers.add_parser("promote")
    promote_parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    promote_parser.add_argument("--assets-dir", type=Path, default=DEFAULT_ASSETS_DIR)
    promote_parser.add_argument("--skip-shape-validation", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.command == "promote":
        promote_artifacts(
            output_dir=args.output_dir,
            assets_dir=args.assets_dir,
            validate_shape=not args.skip_shape_validation,
        )
        print(f"Promoted model artifacts from {args.output_dir} to {args.assets_dir}")
        return

    config = ReleaseConfig(
        output_dir=args.output_dir,
        label_profile=args.label_profile,
        max_per_label=args.max_per_label,
        min_per_label=args.min_per_label,
        epochs=args.epochs,
        batch_size=args.batch_size,
        plantvillage_zip_path=args.plantvillage_zip_path,
        build_android=args.build_android,
        flutter_command=args.flutter_command,
        base_model_path=args.base_model_path,
        base_labels_path=args.base_labels_path,
        digigreen_max_per_label=args.digigreen_max_per_label,
    )
    run_release(config)


if __name__ == "__main__":
    main()
