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


def mixup_pair(
    batch_a,
    batch_b,
    *,
    alpha: float = 0.2,
    seed: int | None = None,
):
    """Convex combination of two ``(images, one_hot_labels)`` batches.

    Used as a ``tf.data`` transform during the fine-tune phase. When
    ``alpha == 0.0`` the function returns ``batch_a`` unchanged so callers
    can use the same wired-up dataset for warm-up (no MixUp) and
    fine-tune (MixUp on).
    """
    import tensorflow as tf

    images_a, labels_a = batch_a
    if alpha <= 0.0:
        return images_a, labels_a

    images_b, labels_b = batch_b
    batch_size = tf.shape(images_a)[0]
    if seed is None:
        lam = tf.random.gamma((batch_size,), alpha) / (
            tf.random.gamma((batch_size,), alpha)
            + tf.random.gamma((batch_size,), alpha)
        )
    else:
        gen = tf.random.Generator.from_seed(seed)
        lam = gen.uniform((batch_size,), minval=alpha, maxval=1.0 - alpha)

    lam_images = tf.reshape(lam, (-1, 1, 1, 1))
    lam_labels = tf.reshape(lam, (-1, 1))
    mixed_images = lam_images * images_a + (1.0 - lam_images) * images_b
    mixed_labels = lam_labels * labels_a + (1.0 - lam_labels) * labels_b
    return mixed_images, mixed_labels
