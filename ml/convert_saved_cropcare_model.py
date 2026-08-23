"""Convert a persisted CropCare Keras model into app-ready TFLite assets."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.python.framework.convert_to_constants import convert_variables_to_constants_v2


EXPECTED_TRAINING_LABELS = [
    "corn_common_rust",
    "corn_gray_leaf_spot",
    "corn_healthy",
    "corn_northern_leaf_blight",
    "eggplant_healthy",
    "eggplant_insect_pest",
    "eggplant_leaf_spot",
    "eggplant_mosaic_virus",
    "eggplant_small_leaf",
    "eggplant_white_mold",
    "eggplant_wilt",
    "pepper_bacterial_spot",
    "pepper_healthy",
    "squash_powdery_mildew",
    "tomato_bacterial_spot",
    "tomato_early_blight",
    "tomato_healthy",
    "tomato_late_blight",
    "tomato_leaf_mold",
    "tomato_mosaic_virus",
    "tomato_septoria_leaf_spot",
    "tomato_spider_mites",
    "tomato_target_spot",
    "tomato_yellow_leaf_curl_virus",
]

APP_LABELS = [
    "Corn_(maize)___Common_rust_",
    "Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot",
    "Corn_(maize)___healthy",
    "Corn_(maize)___Northern_Leaf_Blight",
    "Eggplant_healthy",
    "Eggplant_insect_pest",
    "Eggplant_leaf_spot",
    "Eggplant_mosaic_virus",
    "Eggplant_small_leaf",
    "Eggplant_white_mold",
    "Eggplant_wilt",
    "pepper_bacterial_spot",
    "pepper_healthy",
    "squash_powdery_mildew",
    "tomato_bacterial_spot",
    "tomato_early_blight",
    "tomato_healthy",
    "tomato_late_blight",
    "tomato_leaf_mold",
    "tomato_mosaic_virus",
    "tomato_septoria_leaf_spot",
    "tomato_spider_mites",
    "tomato_target_spot",
    "tomato_yellow_leaf_curl_virus",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--training-labels", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    return parser.parse_args()


def build_float32_inference_model(source_model: tf.keras.Model) -> tf.keras.Model:
    """Remove training augmentation and mixed-float16 head policies for export."""
    expected_layer_types = (
        tf.keras.layers.InputLayer,
        tf.keras.Sequential,
        tf.keras.Model,
        tf.keras.layers.GlobalAveragePooling2D,
        tf.keras.layers.BatchNormalization,
        tf.keras.layers.Dropout,
        tf.keras.layers.Dense,
    )
    if len(source_model.layers) != len(expected_layer_types) or any(
        not isinstance(layer, expected_type)
        for layer, expected_type in zip(source_model.layers, expected_layer_types)
    ):
        raise ValueError("Unexpected CropCare model layout; refusing to rebuild it for export.")

    source_backbone = source_model.layers[2]
    source_pool = source_model.layers[3]
    source_normalization = source_model.layers[4]
    source_dropout = source_model.layers[5]
    source_classifier = source_model.layers[6]

    export_input = tf.keras.Input(shape=(320, 320, 3), dtype=tf.float32)
    export_backbone = tf.keras.applications.EfficientNetV2S(
        include_top=False,
        weights=None,
        input_shape=(320, 320, 3),
        include_preprocessing=True,
    )
    export_backbone.set_weights(source_backbone.get_weights())
    output = export_backbone(export_input, training=False)
    output = tf.keras.layers.GlobalAveragePooling2D(name=source_pool.name)(output)
    export_classifier = tf.keras.layers.Dense(
        24,
        activation=source_classifier.activation,
        dtype=tf.float32,
        name=source_classifier.name,
    )
    output = export_classifier(output)
    export_model = tf.keras.Model(export_input, output, name="cropcare_inference")
    gamma, beta, mean, variance = source_normalization.get_weights()
    kernel, bias = source_classifier.get_weights()
    scale = gamma / np.sqrt(variance + source_normalization.epsilon)
    offset = beta - mean * scale
    fused_kernel = kernel * scale[:, np.newaxis]
    fused_bias = bias + offset @ kernel
    export_classifier.set_weights([fused_kernel, fused_bias])
    return export_model


def main() -> None:
    args = parse_args()
    training_labels = args.training_labels.read_text(encoding="utf-8").splitlines()

    if training_labels != EXPECTED_TRAINING_LABELS:
        raise ValueError(
            "The supplied training labels do not match the expected 24-class "
            "CropCare output order. Refusing to create mismatched app assets."
        )

    model = tf.keras.models.load_model(args.model, compile=False)
    if model.input_shape != (None, 320, 320, 3):
        raise ValueError(f"Expected input shape (None, 320, 320, 3), got {model.input_shape}.")
    if model.output_shape != (None, 24):
        raise ValueError(f"Expected output shape (None, 24), got {model.output_shape}.")

    export_model = build_float32_inference_model(model)
    sample_input = np.zeros((1, 320, 320, 3), dtype=np.float32)
    source_output = model(sample_input, training=False).numpy()
    export_output = export_model(sample_input, training=False).numpy()
    difference = np.max(np.abs(source_output - export_output))
    if np.argmax(source_output) != np.argmax(export_output) or difference > 0.02:
        raise RuntimeError(f"Float32 export model changed predictions (max difference {difference}).")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    labels_path = args.output_dir / "plant_disease_efficientnetv2s_labels.txt"
    model_path = args.output_dir / "plant_disease_efficientnetv2s.tflite"
    labels_path.write_text("\n".join(APP_LABELS), encoding="utf-8")

    @tf.function
    def serving(input_tensor: tf.Tensor) -> tf.Tensor:
        return export_model(input_tensor, training=False)

    concrete_function = serving.get_concrete_function(
        tf.TensorSpec((1, 320, 320, 3), tf.float32),
    )
    frozen_function = convert_variables_to_constants_v2(concrete_function)
    converter = tf.lite.TFLiteConverter.from_concrete_functions([frozen_function])
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    print("Converting Keras model to TFLite...", flush=True)
    tflite_bytes = converter.convert()
    model_path.write_bytes(tflite_bytes)

    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    input_detail = interpreter.get_input_details()[0]
    output_detail = interpreter.get_output_details()[0]
    expected_input = np.zeros((1, 320, 320, 3), dtype=input_detail["dtype"])
    interpreter.set_tensor(input_detail["index"], expected_input)
    interpreter.invoke()
    tflite_output = interpreter.get_tensor(output_detail["index"]).astype(np.float32)

    if tuple(input_detail["shape"]) != (1, 320, 320, 3):
        raise RuntimeError(f"Unexpected TFLite input shape: {input_detail['shape']}")
    if tuple(output_detail["shape"]) != (1, 24):
        raise RuntimeError(f"Unexpected TFLite output shape: {output_detail['shape']}")
    tflite_difference = np.max(np.abs(export_output - tflite_output))
    if np.argmax(export_output) != np.argmax(tflite_output) or tflite_difference > 0.05:
        raise RuntimeError(
            f"TFLite conversion changed predictions (max difference {tflite_difference})."
        )

    print(f"Saved model: {model_path}")
    print(f"Saved labels: {labels_path}")
    print(f"TFLite size: {model_path.stat().st_size / (1024 * 1024):.2f} MB")
    print(f"TFLite input: {input_detail['shape']} {input_detail['dtype']}")
    print(f"TFLite output: {output_detail['shape']} {output_detail['dtype']}")
    print(f"Source-to-float32 max logit difference: {difference:.6f}")
    print(f"Float32-to-TFLite max logit difference: {tflite_difference:.6f}")


if __name__ == "__main__":
    main()