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
