"""TFLite vs TFLite comparison harness with PROMOTE/BLOCK verdict."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def run_tflite_inference(
    *,
    model_path: Path,
    image,
):
    """Return softmax-style probability vector for one resized image.

    Handles both float32 and uint8 (post-quantization) TFLite models by
    inspecting the input/output tensor dtypes and dequantizing as
    needed.
    """
    import numpy as np
    import tensorflow as tf

    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()[0]
    output_details = interpreter.get_output_details()[0]

    input_height = int(input_details["shape"][1])
    input_width = int(input_details["shape"][2])

    image_array = np.asarray(image, dtype=np.float32).reshape(
        1, input_height, input_width, 3
    )

    if input_details["dtype"] == np.uint8:
        scale, zero_point = input_details["quantization"]
        if scale == 0:
            quantized = image_array.astype(np.uint8)
        else:
            quantized = np.clip(
                np.round(image_array / scale + zero_point),
                0,
                255,
            ).astype(np.uint8)
        interpreter.set_tensor(input_details["index"], quantized)
    else:
        interpreter.set_tensor(
            input_details["index"], image_array.astype(np.float32)
        )

    interpreter.invoke()
    raw_output = interpreter.get_tensor(output_details["index"])[0]

    if output_details["dtype"] == np.uint8:
        scale, zero_point = output_details["quantization"]
        if scale == 0:
            probabilities = raw_output.astype(np.float32) / 255.0
        else:
            probabilities = (
                raw_output.astype(np.float32) - zero_point
            ) * scale
    else:
        probabilities = raw_output.astype(np.float32)

    probabilities = np.clip(probabilities, 0.0, 1.0)
    total = float(probabilities.sum())
    if total > 0:
        probabilities = probabilities / total
    return probabilities


def evaluate_model(
    *,
    model_path: Path,
    labels: list[str],
    test_dir: Path,
) -> dict:
    """Run the TFLite model on every image under ``test_dir`` and aggregate."""
    import numpy as np
    import tensorflow as tf
    from PIL import Image
    from sklearn.metrics import classification_report, f1_score

    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    input_height = int(interpreter.get_input_details()[0]["shape"][1])
    input_width = int(interpreter.get_input_details()[0]["shape"][2])

    y_true: list[int] = []
    y_pred: list[int] = []
    for index, label in enumerate(labels):
        label_dir = test_dir / label
        if not label_dir.exists():
            continue
        for path in sorted(label_dir.glob("*.*")):
            with Image.open(path) as image:
                resized = image.convert("RGB").resize((input_width, input_height))
                arr = np.asarray(resized, dtype=np.float32)
            probs = run_tflite_inference(model_path=model_path, image=arr)
            y_true.append(index)
            y_pred.append(int(np.argmax(probs)))

    if not y_true:
        return {
            "accuracy": 0.0,
            "macro_f1": 0.0,
            "per_class": {
                label: {
                    "precision": 0.0,
                    "recall": 0.0,
                    "f1": 0.0,
                    "support": 0,
                }
                for label in labels
            },
        }

    report = classification_report(
        y_true,
        y_pred,
        labels=list(range(len(labels))),
        target_names=labels,
        output_dict=True,
        zero_division=0,
    )
    per_class = {
        label: {
            "precision": float(report[label]["precision"]),
            "recall": float(report[label]["recall"]),
            "f1": float(report[label]["f1-score"]),
            "support": int(report[label]["support"]),
        }
        for label in labels
    }
    accuracy = float(np.mean(np.array(y_true) == np.array(y_pred)))
    macro_f1 = float(
        f1_score(y_true, y_pred, average="macro", zero_division=0)
    )
    return {
        "accuracy": accuracy,
        "macro_f1": macro_f1,
        "per_class": per_class,
    }


def promotion_verdict(
    *,
    base_metrics: dict,
    candidate_metrics: dict,
    min_macro_f1: float = 0.90,
    min_accuracy: float = 0.92,
    min_per_class_f1: float = 0.85,
    min_per_class_precision: float = 0.80,
    min_per_class_recall: float = 0.80,
) -> dict:
    """Return ``{"status": "PROMOTE"|"BLOCK", "reasons": [...]}``."""
    reasons: list[str] = []

    if candidate_metrics["macro_f1"] < min_macro_f1:
        reasons.append(
            f"candidate macro_f1 {candidate_metrics['macro_f1']:.4f} "
            f"< floor {min_macro_f1:.4f}"
        )
    if candidate_metrics["accuracy"] < min_accuracy:
        reasons.append(
            f"candidate accuracy {candidate_metrics['accuracy']:.4f} "
            f"< floor {min_accuracy:.4f}"
        )

    base_per_class = base_metrics.get("per_class", {})
    for label, label_metrics in candidate_metrics.get("per_class", {}).items():
        f1 = float(label_metrics.get("f1", 0.0))
        precision = float(label_metrics.get("precision", 0.0))
        recall = float(label_metrics.get("recall", 0.0))
        if f1 < min_per_class_f1:
            reasons.append(
                f"{label} f1 {f1:.4f} < floor {min_per_class_f1:.4f}"
            )
        if precision < min_per_class_precision:
            reasons.append(
                f"{label} precision {precision:.4f} "
                f"< floor {min_per_class_precision:.4f}"
            )
        if recall < min_per_class_recall:
            reasons.append(
                f"{label} recall {recall:.4f} "
                f"< floor {min_per_class_recall:.4f}"
            )
        base_f1 = float(base_per_class.get(label, {}).get("f1", 0.0))
        if base_f1 > 0.0 and f1 < base_f1:
            reasons.append(
                f"regression on {label}: candidate f1 {f1:.4f} "
                f"< base f1 {base_f1:.4f}"
            )

    return {
        "status": "PROMOTE" if not reasons else "BLOCK",
        "reasons": reasons,
    }


def render_markdown_report(
    *,
    base: dict,
    candidate: dict,
    verdict: dict,
    labels: list[str],
    base_path: Path,
    candidate_path: Path,
) -> str:
    """Render a human-readable comparison report."""
    lines: list[str] = []
    lines.append("# CropCare v2 Model Comparison\n")
    lines.append(f"**Verdict:** `{verdict['status']}`\n")
    if verdict.get("reasons"):
        lines.append("**Block reasons:**\n")
        for reason in verdict["reasons"]:
            lines.append(f"- {reason}")
        lines.append("")

    lines.append(f"- **Base model:** `{base_path}`")
    lines.append(f"- **Candidate model:** `{candidate_path}`\n")

    lines.append("## Overall metrics\n")
    lines.append("| Metric | Base | Candidate | Δ |")
    lines.append("|---|---|---|---|")
    for key in ("macro_f1", "accuracy"):
        base_value = float(base.get(key, 0.0))
        candidate_value = float(candidate.get(key, 0.0))
        lines.append(
            f"| {key} | {base_value:.4f} | {candidate_value:.4f} "
            f"| {candidate_value - base_value:+.4f} |"
        )
    lines.append("")

    lines.append("## Per-class\n")
    lines.append(
        "| Label | Base F1 | Candidate F1 | Δ F1 | Candidate Precision | Candidate Recall |"
    )
    lines.append("|---|---|---|---|---|---|")
    for label in labels:
        base_metrics = base.get("per_class", {}).get(label, {})
        cand_metrics = candidate.get("per_class", {}).get(label, {})
        base_f1 = float(base_metrics.get("f1", 0.0))
        cand_f1 = float(cand_metrics.get("f1", 0.0))
        cand_p = float(cand_metrics.get("precision", 0.0))
        cand_r = float(cand_metrics.get("recall", 0.0))
        lines.append(
            f"| {label} | {base_f1:.4f} | {cand_f1:.4f} | "
            f"{cand_f1 - base_f1:+.4f} | {cand_p:.4f} | {cand_r:.4f} |"
        )
    lines.append("")
    return "\n".join(lines) + "\n"


def write_comparison_report(*, payload: dict, report_dir: Path) -> None:
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "comparison_report.json").write_text(
        json.dumps(payload, indent=2),
        encoding="utf-8",
    )
    markdown = render_markdown_report(
        base=payload["base_metrics"],
        candidate=payload["candidate_metrics"],
        verdict=payload["verdict"],
        labels=payload["labels"],
        base_path=Path(payload["base_path"]),
        candidate_path=Path(payload["candidate_path"]),
    )
    (report_dir / "comparison_report.md").write_text(markdown, encoding="utf-8")


def _read_labels(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare two TFLite models on a test split and emit a verdict."
    )
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--base-labels", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--candidate-labels", type=Path, required=True)
    parser.add_argument("--test-dir", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--min-macro-f1", type=float, default=0.90)
    parser.add_argument("--min-accuracy", type=float, default=0.92)
    parser.add_argument("--min-per-class-f1", type=float, default=0.85)
    parser.add_argument("--min-per-class-precision", type=float, default=0.80)
    parser.add_argument("--min-per-class-recall", type=float, default=0.80)
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    base_labels = _read_labels(args.base_labels)
    candidate_labels = _read_labels(args.candidate_labels)
    if base_labels != candidate_labels:
        # Compare on the intersection (preserves the candidate ordering for
        # row counts and matches the spec's per-class regression check).
        common = [label for label in candidate_labels if label in base_labels]
        if not common:
            raise ValueError(
                "Base and candidate label sets do not overlap; cannot compare."
            )
        labels = common
    else:
        labels = candidate_labels

    base_metrics = evaluate_model(
        model_path=args.base, labels=labels, test_dir=args.test_dir
    )
    candidate_metrics = evaluate_model(
        model_path=args.candidate, labels=labels, test_dir=args.test_dir
    )
    verdict = promotion_verdict(
        base_metrics=base_metrics,
        candidate_metrics=candidate_metrics,
        min_macro_f1=args.min_macro_f1,
        min_accuracy=args.min_accuracy,
        min_per_class_f1=args.min_per_class_f1,
        min_per_class_precision=args.min_per_class_precision,
        min_per_class_recall=args.min_per_class_recall,
    )
    payload = {
        "base_path": str(args.base),
        "candidate_path": str(args.candidate),
        "labels": labels,
        "base_metrics": base_metrics,
        "candidate_metrics": candidate_metrics,
        "verdict": verdict,
    }
    write_comparison_report(payload=payload, report_dir=args.report_dir)
    print(f"Wrote comparison report to {args.report_dir}")
    if verdict["status"] != "PROMOTE":
        raise SystemExit(2)


if __name__ == "__main__":
    main()
