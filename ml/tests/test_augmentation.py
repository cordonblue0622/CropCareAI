import numpy as np
import pytest

tf = pytest.importorskip("tensorflow")


def test_build_augmentation_block_returns_keras_sequential_with_six_layers() -> None:
    from cropcare_training.augmentation import build_augmentation_block

    block = build_augmentation_block(seed=7)

    assert isinstance(block, tf.keras.Sequential)
    layer_class_names = [layer.__class__.__name__ for layer in block.layers]
    assert layer_class_names == [
        "RandomFlip",
        "RandomRotation",
        "RandomZoom",
        "RandomTranslation",
        "RandomContrast",
        "RandomBrightness",
    ]


def test_augmentation_block_is_no_op_when_training_false() -> None:
    from cropcare_training.augmentation import build_augmentation_block

    block = build_augmentation_block(seed=7)
    image = tf.constant(
        np.full((1, 32, 32, 3), 128, dtype=np.float32),
        dtype=tf.float32,
    )

    output = block(image, training=False).numpy()

    np.testing.assert_array_equal(output, image.numpy())


def test_augmentation_block_modifies_inputs_when_training_true() -> None:
    from cropcare_training.augmentation import build_augmentation_block

    block = build_augmentation_block(seed=7)
    image = tf.constant(
        np.tile(np.arange(32, dtype=np.float32).reshape(1, 32, 1, 1), (1, 1, 32, 3)),
        dtype=tf.float32,
    )

    output = block(image, training=True).numpy()

    # With seed=7, the RandomFlip alone changes the tensor; we just need
    # ANY change vs identity.
    assert not np.array_equal(output, image.numpy())
