"""TFLite vs TFLite comparison harness with PROMOTE/BLOCK verdict."""

from __future__ import annotations

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
