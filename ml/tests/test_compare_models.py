from pathlib import Path

import numpy as np
import pytest

tf = pytest.importorskip("tensorflow")


def _toy_tflite_model(tmp_path: Path, dtype: str = "float") -> Path:
    inputs = tf.keras.Input(shape=(8, 8, 3))
    x = tf.keras.layers.Flatten()(inputs)
    outputs = tf.keras.layers.Dense(2, activation="softmax")(x)
    model = tf.keras.Model(inputs, outputs)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    if dtype == "uint8":
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        rng = np.random.default_rng(0)

        def rep():
            for _ in range(8):
                yield [
                    rng.uniform(0, 255, size=(1, 8, 8, 3)).astype(np.float32)
                ]

        converter.representative_dataset = rep
        converter.target_spec.supported_ops = [
            tf.lite.OpsSet.TFLITE_BUILTINS_INT8
        ]
        converter.inference_input_type = tf.uint8
        converter.inference_output_type = tf.uint8
    path = tmp_path / f"toy_{dtype}.tflite"
    path.write_bytes(converter.convert())
    return path


def test_run_tflite_inference_returns_softmax_probabilities_float(
    tmp_path: Path,
) -> None:
    from cropcare_training.compare_models import run_tflite_inference

    model_path = _toy_tflite_model(tmp_path, dtype="float")
    image = np.random.default_rng(1).uniform(
        0, 255, size=(8, 8, 3)
    ).astype(np.float32)

    probs = run_tflite_inference(model_path=model_path, image=image)

    assert probs.shape == (2,)
    assert abs(probs.sum() - 1.0) < 1e-4


def test_run_tflite_inference_handles_uint8_quantized_model(
    tmp_path: Path,
) -> None:
    from cropcare_training.compare_models import run_tflite_inference

    model_path = _toy_tflite_model(tmp_path, dtype="uint8")
    image = np.random.default_rng(2).uniform(
        0, 255, size=(8, 8, 3)
    ).astype(np.float32)

    probs = run_tflite_inference(model_path=model_path, image=image)

    assert probs.shape == (2,)
    assert (probs >= 0).all() and (probs <= 1).all()


def test_evaluate_model_returns_macro_f1_and_per_class_metrics(
    tmp_path: Path,
) -> None:
    from PIL import Image

    from cropcare_training.compare_models import evaluate_model

    test_dir = tmp_path / "test"
    for label in ("a", "b"):
        (test_dir / label).mkdir(parents=True)
        for i in range(2):
            Image.new(
                "RGB",
                (8, 8),
                color=(255, 0, 0) if label == "a" else (0, 255, 0),
            ).save(test_dir / label / f"{label}_{i}.png")

    model_path = _toy_tflite_model(tmp_path, dtype="float")
    metrics = evaluate_model(
        model_path=model_path,
        labels=["a", "b"],
        test_dir=test_dir,
    )

    assert "macro_f1" in metrics
    assert "accuracy" in metrics
    assert "per_class" in metrics
    assert set(metrics["per_class"]) == {"a", "b"}
    for class_metrics in metrics["per_class"].values():
        for key in ("precision", "recall", "f1", "support"):
            assert key in class_metrics


def test_promotion_verdict_blocks_when_macro_f1_below_floor() -> None:
    from cropcare_training.compare_models import promotion_verdict

    base = {
        "macro_f1": 0.85,
        "accuracy": 0.9,
        "per_class": {"a": {"f1": 0.9}, "b": {"f1": 0.85}},
    }
    candidate_low = {
        "macro_f1": 0.89,
        "accuracy": 0.91,
        "per_class": {"a": {"f1": 0.92}, "b": {"f1": 0.87}},
    }

    verdict = promotion_verdict(
        base_metrics=base,
        candidate_metrics=candidate_low,
        min_macro_f1=0.90,
        min_accuracy=0.92,
        min_per_class_f1=0.85,
    )

    assert verdict["status"] == "BLOCK"
    assert any("macro_f1" in reason for reason in verdict["reasons"])


def test_promotion_verdict_blocks_when_class_regresses() -> None:
    from cropcare_training.compare_models import promotion_verdict

    base = {
        "macro_f1": 0.91,
        "accuracy": 0.94,
        "per_class": {"a": {"f1": 0.95}, "b": {"f1": 0.93}},
    }
    candidate = {
        "macro_f1": 0.92,
        "accuracy": 0.95,
        "per_class": {"a": {"f1": 0.96}, "b": {"f1": 0.86}},
    }

    verdict = promotion_verdict(
        base_metrics=base,
        candidate_metrics=candidate,
        min_macro_f1=0.90,
        min_accuracy=0.92,
        min_per_class_f1=0.85,
    )

    assert verdict["status"] == "BLOCK"
    assert any(
        "regression" in reason and "b" in reason for reason in verdict["reasons"]
    )


def test_promotion_verdict_promotes_when_all_gates_pass() -> None:
    from cropcare_training.compare_models import promotion_verdict

    base = {
        "macro_f1": 0.91,
        "accuracy": 0.94,
        "per_class": {
            "a": {"f1": 0.95, "precision": 0.95, "recall": 0.95},
            "b": {"f1": 0.93, "precision": 0.93, "recall": 0.93},
        },
    }
    candidate = {
        "macro_f1": 0.94,
        "accuracy": 0.96,
        "per_class": {
            "a": {"f1": 0.96, "precision": 0.96, "recall": 0.96},
            "b": {"f1": 0.94, "precision": 0.94, "recall": 0.94},
        },
    }

    verdict = promotion_verdict(
        base_metrics=base,
        candidate_metrics=candidate,
        min_macro_f1=0.90,
        min_accuracy=0.92,
        min_per_class_f1=0.85,
    )

    assert verdict["status"] == "PROMOTE"
    assert verdict["reasons"] == []


def test_render_markdown_report_contains_verdict_and_per_class_table(
    tmp_path: Path,
) -> None:
    from cropcare_training.compare_models import render_markdown_report

    base = {
        "macro_f1": 0.91,
        "accuracy": 0.93,
        "per_class": {
            "a": {"precision": 0.92, "recall": 0.91, "f1": 0.91},
            "b": {"precision": 0.93, "recall": 0.93, "f1": 0.93},
        },
    }
    candidate = {
        "macro_f1": 0.94,
        "accuracy": 0.95,
        "per_class": {
            "a": {"precision": 0.95, "recall": 0.93, "f1": 0.94},
            "b": {"precision": 0.95, "recall": 0.95, "f1": 0.95},
        },
    }
    verdict = {"status": "PROMOTE", "reasons": []}

    report = render_markdown_report(
        base=base,
        candidate=candidate,
        verdict=verdict,
        labels=["a", "b"],
        base_path=Path("base.tflite"),
        candidate_path=Path("candidate.tflite"),
    )

    assert "PROMOTE" in report
    assert "macro_f1" in report
    assert "| a |" in report
    assert "0.94" in report  # candidate F1 for class a
    assert "Δ" in report  # delta column header


def test_write_comparison_report_persists_json_and_markdown(
    tmp_path: Path,
) -> None:
    from cropcare_training.compare_models import write_comparison_report

    payload = {
        "base_path": "base.tflite",
        "candidate_path": "candidate.tflite",
        "labels": ["a"],
        "base_metrics": {
            "macro_f1": 0.9,
            "accuracy": 0.9,
            "per_class": {"a": {"precision": 0.9, "recall": 0.9, "f1": 0.9}},
        },
        "candidate_metrics": {
            "macro_f1": 0.95,
            "accuracy": 0.95,
            "per_class": {"a": {"precision": 0.95, "recall": 0.95, "f1": 0.95}},
        },
        "verdict": {"status": "PROMOTE", "reasons": []},
    }

    write_comparison_report(payload=payload, report_dir=tmp_path)

    assert (tmp_path / "comparison_report.json").exists()
    assert (tmp_path / "comparison_report.md").exists()
    assert "PROMOTE" in (
        tmp_path / "comparison_report.md"
    ).read_text(encoding="utf-8")
