"""Keras augmentation utilities for CropCare v2 training.

The base augmentation block is added to the model graph itself so it is
applied during training and is a no-op at inference time (Keras
``Random*`` layers turn off when called with ``training=False``, which
TFLite conversion preserves).
"""

from __future__ import annotations


def build_augmentation_block(seed: int = 1234):
    """Return a Sequential of Random* layers used in both training phases.

    The order matters: flip → rotation → zoom → translation → contrast →
    brightness mirrors the order documented in the design spec
    (§4.2 of 2026-05-06-cropcare-v2-model-upgrade-design.md).
    """
    try:
        import tensorflow as tf
    except ImportError as exc:  # pragma: no cover - environment guard
        raise RuntimeError(
            "Install ML dependencies first: python -m pip install -r ml/requirements.txt"
        ) from exc

    return tf.keras.Sequential(
        layers=[
            tf.keras.layers.RandomFlip(mode="horizontal", seed=seed),
            tf.keras.layers.RandomRotation(factor=0.08, seed=seed),
            tf.keras.layers.RandomZoom(
                height_factor=0.15,
                width_factor=0.15,
                seed=seed,
            ),
            tf.keras.layers.RandomTranslation(
                height_factor=0.06,
                width_factor=0.06,
                seed=seed,
            ),
            tf.keras.layers.RandomContrast(factor=0.15, seed=seed),
            tf.keras.layers.RandomBrightness(factor=0.15, seed=seed),
        ],
        name="cropcare_augmentation_block",
    )
