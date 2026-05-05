from __future__ import annotations

import argparse
import json
from pathlib import Path

from .label_mapping import TARGET_LABELS
from .label_profiles import labels_for_profile
from .manifest import write_label_file


DEFAULT_DATA_DIR = Path("ml/artifacts/cropcare_v2/images_by_split")
DEFAULT_OUTPUT_DIR = Path("ml/artifacts/cropcare_v2")


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
    epochs: int = 12,
    batch_size: int = 32,
    image_size: tuple[int, int] = (224, 224),
    label_profile: str = "cropcare_v2_full",
    labels: list[str] | None = None,
) -> None:
    try:
        import numpy as np
        import tensorflow as tf
        from sklearn.metrics import classification_report, confusion_matrix, f1_score
    except ImportError as exc:
        raise RuntimeError(
            "Install ML dependencies first: python -m pip install -r ml/requirements.txt"
        ) from exc

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
    missing_validation = [label for label in class_names if label not in validation_class_names]
    if missing_validation:
        raise ValueError(
            "Validation split is missing class directories required by the train split: "
            + ", ".join(missing_validation)
        )

    train_ds = tf.keras.utils.image_dataset_from_directory(
        train_dir,
        labels="inferred",
        label_mode="categorical",
        class_names=class_names,
        image_size=image_size,
        batch_size=batch_size,
        shuffle=True,
    )
    validation_ds = tf.keras.utils.image_dataset_from_directory(
        validation_dir,
        labels="inferred",
        label_mode="categorical",
        class_names=class_names,
        image_size=image_size,
        batch_size=batch_size,
        shuffle=False,
    )

    autotune = tf.data.AUTOTUNE
    train_ds = train_ds.prefetch(autotune)
    validation_ds = validation_ds.prefetch(autotune)

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

    history = model.fit(train_ds, validation_data=validation_ds, epochs=epochs)

    eval_ds = validation_ds
    eval_split = "validation"
    if test_dir.exists():
        eval_ds = tf.keras.utils.image_dataset_from_directory(
            test_dir,
            labels="inferred",
            label_mode="categorical",
            class_names=class_names,
            image_size=image_size,
            batch_size=batch_size,
            shuffle=False,
        ).prefetch(autotune)
        eval_split = "test"

    y_true: list[int] = []
    y_pred: list[int] = []
    for batch_images, batch_labels in eval_ds:
        predictions = model.predict(batch_images, verbose=0)
        y_true.extend(np.argmax(batch_labels.numpy(), axis=1).tolist())
        y_pred.extend(np.argmax(predictions, axis=1).tolist())

    output_dir.mkdir(parents=True, exist_ok=True)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()
    (output_dir / "cropcare_efficientnet_v2.tflite").write_bytes(tflite_model)
    write_label_file(output_dir / "labels_v2.txt", class_names)

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
            "batch_size": batch_size,
            "history": history.history,
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
    parser.add_argument("--epochs", type=int, default=12)
    parser.add_argument("--batch-size", type=int, default=32)
    parser.add_argument("--label-profile", default="cropcare_v2_full")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    train_and_export(
        data_dir=args.data_dir,
        output_dir=args.output_dir,
        epochs=args.epochs,
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
