from __future__ import annotations

import argparse
import json
from pathlib import Path

from .label_mapping import TARGET_LABELS
from .label_profiles import labels_for_profile
from .manifest import write_label_file


DEFAULT_DATA_DIR = Path("ml/artifacts/cropcare_v2/images_by_split")
DEFAULT_OUTPUT_DIR = Path("ml/artifacts/cropcare_v2")


def representative_dataset_gen(
    *,
    train_dir: Path,
    class_names: list[str],
    image_size: tuple[int, int],
    num_samples: int = 200,
):
    """Yield single-image batches for INT8 post-training calibration.

    Returns lists shaped ``[1, H, W, 3]`` of float32 in ``[0, 255]`` so the
    representative dataset matches the model's float input layer.
    """
    import numpy as np
    from PIL import Image

    samples_per_class = max(1, num_samples // max(1, len(class_names)))
    yielded = 0
    for label in class_names:
        label_dir = train_dir / label
        if not label_dir.exists():
            continue
        for path in sorted(label_dir.glob("*.*"))[:samples_per_class]:
            with Image.open(path) as image:
                resized = image.convert("RGB").resize(image_size)
                arr = np.asarray(resized, dtype=np.float32)
            yield [arr.reshape(1, image_size[0], image_size[1], 3)]
            yielded += 1
            if yielded >= num_samples:
                return


def export_int8_tflite(
    *,
    model,
    train_dir: Path,
    class_names: list[str],
    image_size: tuple[int, int],
    output_path: Path,
    num_calibration_samples: int = 200,
) -> None:
    """Convert ``model`` to a fully-quantized INT8 TFLite at ``output_path``."""
    import tensorflow as tf

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.representative_dataset = lambda: representative_dataset_gen(
        train_dir=train_dir,
        class_names=class_names,
        image_size=image_size,
        num_samples=num_calibration_samples,
    )
    converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
    converter.inference_input_type = tf.uint8
    converter.inference_output_type = tf.uint8
    output_path.write_bytes(converter.convert())


def unfreeze_top_layers(backbone, n: int = 30) -> None:
    """Make the last ``n`` non-BatchNorm layers of ``backbone`` trainable.

    BatchNormalization layers stay frozen regardless of ``n`` to avoid
    the well-known fine-tuning batch-statistics drift on small datasets.
    """
    import tensorflow as tf

    backbone.trainable = True
    layers = list(backbone.layers)
    trainable_count = 0
    for layer in reversed(layers):
        if isinstance(layer, tf.keras.layers.BatchNormalization):
            layer.trainable = False
            continue
        if trainable_count < n:
            layer.trainable = True
            trainable_count += 1
        else:
            layer.trainable = False


def phase_epoch_split(
    *,
    total_epochs: int,
    warmup_epochs: int = 5,
) -> tuple[int, int]:
    """Return ``(warmup, fine_tune)`` epoch counts.

    If ``total_epochs <= warmup_epochs``, the entire budget goes to
    warm-up and fine-tune is zero.
    """
    if total_epochs <= warmup_epochs:
        return total_epochs, 0
    return warmup_epochs, total_epochs - warmup_epochs


def compute_class_weights(
    *,
    class_names: list[str],
    per_class_counts: dict[str, int],
) -> dict[int, float]:
    """Return Keras-style ``class_weight`` dict using inverse frequency.

    Weights are normalised so their mean is 1.0; that keeps the
    cross-entropy loss on roughly the same scale as the unweighted
    case, which simplifies LR tuning. Classes with zero observed
    samples receive weight 1.0 (neutral).
    """
    raw: dict[int, float] = {}
    for index, name in enumerate(class_names):
        count = per_class_counts.get(name, 0)
        raw[index] = (1.0 / count) if count > 0 else 1.0

    non_neutral_values = [
        value
        for index, value in raw.items()
        if per_class_counts.get(class_names[index], 0) > 0
    ]
    if not non_neutral_values:
        return {index: 1.0 for index in raw}
    mean_weight = sum(non_neutral_values) / len(non_neutral_values)
    if mean_weight == 0.0:
        return raw
    return {
        index: (
            weight / mean_weight
            if per_class_counts.get(class_names[index], 0) > 0
            else 1.0
        )
        for index, weight in raw.items()
    }


def build_model(
    *,
    num_classes: int,
    image_size: tuple[int, int] = (224, 224),
    trainable_base: bool = False,
    dropout_rate: float = 0.3,
    seed: int = 1234,
):
    """Construct the EfficientNetB0 + augmentation + head graph.

    The EfficientNetB0 backbone is nested as a submodel (not inlined)
    so callers can later flip ``backbone.trainable`` and walk
    ``backbone.layers`` for partial-unfreeze fine-tuning.
    """
    import tensorflow as tf

    from .augmentation import build_augmentation_block

    base_model = tf.keras.applications.EfficientNetB0(
        include_top=False,
        weights="imagenet",
        input_shape=(*image_size, 3),
        pooling="avg",
    )
    base_model._name = "efficientnetb0_backbone"
    base_model.trainable = trainable_base

    inputs = tf.keras.Input(shape=(*image_size, 3), name="image")
    augmented = build_augmentation_block(seed=seed)(inputs)
    pooled = base_model(augmented, training=trainable_base)
    pooled = tf.keras.layers.Dropout(dropout_rate, name="cropcare_head_dropout")(
        pooled
    )
    outputs = tf.keras.layers.Dense(
        num_classes,
        activation="softmax",
        name="cropcare_label",
    )(pooled)
    return tf.keras.Model(
        inputs=inputs,
        outputs=outputs,
        name="cropcare_efficientnet_v2",
    )


def train_and_export(
    *,
    data_dir: Path = DEFAULT_DATA_DIR,
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    epochs: int = 30,
    warmup_epochs: int = 5,
    unfreeze_top_n: int = 30,
    batch_size: int = 32,
    image_size: tuple[int, int] = (224, 224),
    label_profile: str = "cropcare_v2_subset_100",
    labels: list[str] | None = None,
) -> None:
    try:
        import numpy as np
        import tensorflow as tf
        from sklearn.metrics import (
            classification_report,
            confusion_matrix,
            f1_score,
        )
    except ImportError as exc:
        raise RuntimeError(
            "Install ML dependencies first: python -m pip install -r ml/requirements.txt"
        ) from exc

    from .augmentation import mixup_pair
    from .callbacks import BestMacroF1Checkpoint

    train_dir = data_dir / "train"
    validation_dir = data_dir / "validation"
    test_dir = data_dir / "test"
    for required in (train_dir, validation_dir):
        if not required.exists():
            raise FileNotFoundError(
                f"Missing prepared image directory: {required}. "
                "Run prepare_dataset.py with --download-images first."
            )

    train_class_names = _available_class_names(train_dir)
    validation_class_names = _available_class_names(validation_dir)
    target_labels = labels or labels_for_profile(label_profile)
    class_names = [label for label in target_labels if label in train_class_names]
    if not class_names:
        raise ValueError(f"No trainable class directories found under {train_dir}")
    missing_validation = [
        label for label in class_names if label not in validation_class_names
    ]
    if missing_validation:
        raise ValueError(
            "Validation split is missing class directories required by the train split: "
            + ", ".join(missing_validation)
        )

    autotune = tf.data.AUTOTUNE

    def make_dataset(split_dir: Path, *, shuffle: bool):
        return tf.keras.utils.image_dataset_from_directory(
            split_dir,
            labels="inferred",
            label_mode="categorical",
            class_names=class_names,
            image_size=image_size,
            batch_size=batch_size,
            shuffle=shuffle,
        )

    raw_train_ds = make_dataset(train_dir, shuffle=True).cache()
    train_ds_warmup = raw_train_ds.shuffle(buffer_size=2048).prefetch(autotune)

    def _mixup_dataset(base_ds):
        # Unbatch then re-batch with drop_remainder=True so both streams
        # have identical batch sizes at every step. Without this, the
        # final partial batch (e.g. 16 of 32) lands at different positions
        # in the two independently-shuffled streams and the MixUp
        # convex-combination multiplication fails to broadcast across
        # mismatched leading dimensions.
        unbatched = base_ds.unbatch()
        shuffled_a = unbatched.shuffle(buffer_size=2048).batch(
            batch_size, drop_remainder=True
        )
        shuffled_b = unbatched.shuffle(buffer_size=2048, seed=4242).batch(
            batch_size, drop_remainder=True
        )
        return tf.data.Dataset.zip((shuffled_a, shuffled_b)).map(
            lambda a, b: mixup_pair(a, b, alpha=0.2),
            num_parallel_calls=autotune,
        )

    train_ds_finetune = _mixup_dataset(raw_train_ds).prefetch(autotune)
    validation_ds = make_dataset(validation_dir, shuffle=False).prefetch(autotune)

    per_class_counts: dict[str, int] = {}
    for label in class_names:
        label_dir = train_dir / label
        per_class_counts[label] = sum(1 for _ in label_dir.glob("*.*"))
    class_weight = compute_class_weights(
        class_names=class_names,
        per_class_counts=per_class_counts,
    )

    output_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_dir = output_dir / "checkpoints"
    checkpoint_dir.mkdir(parents=True, exist_ok=True)

    val_x_arrays: list[np.ndarray] = []
    val_y_arrays: list[np.ndarray] = []
    for batch_images, batch_labels in validation_ds:
        val_x_arrays.append(batch_images.numpy())
        val_y_arrays.append(batch_labels.numpy())
    val_x = (
        np.concatenate(val_x_arrays, axis=0)
        if val_x_arrays
        else np.empty((0, *image_size, 3), dtype=np.float32)
    )
    val_y = (
        np.concatenate(val_y_arrays, axis=0)
        if val_y_arrays
        else np.empty((0, len(class_names)), dtype=np.float32)
    )

    warmup, fine_tune_epochs = phase_epoch_split(
        total_epochs=epochs,
        warmup_epochs=warmup_epochs,
    )

    model = build_model(
        num_classes=len(class_names),
        image_size=image_size,
        trainable_base=False,
    )
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss=tf.keras.losses.CategoricalCrossentropy(label_smoothing=0.1),
        metrics=["accuracy"],
    )

    warmup_history = model.fit(
        train_ds_warmup,
        validation_data=validation_ds,
        epochs=warmup,
        class_weight=class_weight,
        callbacks=[
            tf.keras.callbacks.EarlyStopping(
                monitor="val_loss", patience=3, restore_best_weights=True
            ),
            tf.keras.callbacks.ReduceLROnPlateau(
                monitor="val_loss", factor=0.5, patience=2, min_lr=1e-7
            ),
            BestMacroF1Checkpoint(
                validation_data=(val_x, val_y),
                filepath=str(checkpoint_dir / "warmup_best.weights.h5"),
            ),
            tf.keras.callbacks.CSVLogger(
                str(output_dir / "training_log.csv"),
                append=False,
            ),
        ],
        verbose=2,
    )

    fine_tune_history_obj = None
    if fine_tune_epochs > 0:
        backbone = next(
            layer
            for layer in model.layers
            if "efficientnet" in layer.name.lower() and hasattr(layer, "layers")
        )
        unfreeze_top_layers(backbone, n=unfreeze_top_n)
        steps_per_epoch = max(1, sum(per_class_counts.values()) // batch_size)
        cosine = tf.keras.optimizers.schedules.CosineDecay(
            initial_learning_rate=1e-4,
            decay_steps=steps_per_epoch * fine_tune_epochs,
            alpha=0.01,
        )
        model.compile(
            optimizer=tf.keras.optimizers.AdamW(
                learning_rate=cosine, weight_decay=1e-5
            ),
            loss=tf.keras.losses.CategoricalCrossentropy(label_smoothing=0.1),
            metrics=["accuracy"],
        )
        fine_tune_history_obj = model.fit(
            train_ds_finetune,
            validation_data=validation_ds,
            epochs=fine_tune_epochs,
            class_weight=class_weight,
            callbacks=[
                tf.keras.callbacks.EarlyStopping(
                    monitor="val_loss", patience=5, restore_best_weights=True
                ),
                BestMacroF1Checkpoint(
                    validation_data=(val_x, val_y),
                    filepath=str(checkpoint_dir / "best.weights.h5"),
                ),
                tf.keras.callbacks.CSVLogger(
                    str(output_dir / "training_log.csv"),
                    append=True,
                ),
            ],
            verbose=2,
        )

    eval_ds = validation_ds
    eval_split = "validation"
    if test_dir.exists():
        eval_ds = make_dataset(test_dir, shuffle=False).prefetch(autotune)
        eval_split = "test"

    y_true: list[int] = []
    y_pred: list[int] = []
    for batch_images, batch_labels in eval_ds:
        predictions = model.predict(batch_images, verbose=0)
        y_true.extend(np.argmax(batch_labels.numpy(), axis=1).tolist())
        y_pred.extend(np.argmax(predictions, axis=1).tolist())

    keras_path = output_dir / "cropcare_efficientnet_v2.keras"
    model.save(keras_path)

    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()
    (output_dir / "cropcare_efficientnet_v2_float.tflite").write_bytes(
        tflite_model
    )

    export_int8_tflite(
        model=model,
        train_dir=train_dir,
        class_names=class_names,
        image_size=image_size,
        output_path=output_dir / "cropcare_efficientnet_v2.tflite",
    )

    write_label_file(output_dir / "labels_v2.txt", class_names)

    history_payload = {
        "warmup": warmup_history.history if warmup_history is not None else {},
        "fine_tune": (
            fine_tune_history_obj.history
            if fine_tune_history_obj is not None
            else {}
        ),
    }

    report_payload = {
        "status": "trained",
        "model_family": "EfficientNetB0",
        "model_version": "cropcare_efficientnet_v2",
        "label_profile": label_profile,
        "input_shape": [1, image_size[0], image_size[1], 3],
        "output_labels": class_names,
        "target_label_scope": TARGET_LABELS,
        "excluded_labels": {
            label: "excluded_from_active_release_profile"
            for label in TARGET_LABELS
            if label not in class_names
        },
        "preprocessing": {
            "decision": "efficientnet_internal_preprocessing",
            "details": "Keras EfficientNetB0 expects raw RGB pixel values in [0, 255].",
        },
        "training": {
            "epochs": epochs,
            "warmup_epochs": warmup,
            "fine_tune_epochs": fine_tune_epochs,
            "batch_size": batch_size,
            "history": history_payload,
            "class_weight": class_weight,
        },
        "metrics": {
            "evaluation_split": eval_split,
            "macro_f1": f1_score(y_true, y_pred, average="macro", zero_division=0),
            "confusion_matrix": confusion_matrix(
                y_true,
                y_pred,
                labels=list(range(len(class_names))),
            ).tolist(),
            "per_class_precision_recall": classification_report(
                y_true,
                y_pred,
                labels=list(range(len(class_names))),
                target_names=class_names,
                output_dict=True,
                zero_division=0,
            ),
        },
    }
    (output_dir / "training_report_v2.json").write_text(
        json.dumps(report_payload, indent=2),
        encoding="utf-8",
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train and export CropCare EfficientNet v2.")
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--epochs", type=int, default=30)
    parser.add_argument("--warmup-epochs", type=int, default=5)
    parser.add_argument("--unfreeze-top-n", type=int, default=30)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--label-profile", default="cropcare_v2_subset_100")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    train_and_export(
        data_dir=args.data_dir,
        output_dir=args.output_dir,
        epochs=args.epochs,
        warmup_epochs=args.warmup_epochs,
        unfreeze_top_n=args.unfreeze_top_n,
        batch_size=args.batch_size,
        label_profile=args.label_profile,
    )
    print(f"Exported CropCare EfficientNet v2 artifacts to {args.output_dir}")


def _available_class_names(directory: Path) -> set[str]:
    if not directory.exists():
        return set()
    return {path.name for path in directory.iterdir() if path.is_dir()}


if __name__ == "__main__":
    main()
