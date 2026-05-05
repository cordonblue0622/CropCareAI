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


def test_mixup_pair_blends_two_batches_when_alpha_positive() -> None:
    from cropcare_training.augmentation import mixup_pair

    images_a = tf.ones((2, 4, 4, 3), dtype=tf.float32) * 100.0
    images_b = tf.ones((2, 4, 4, 3), dtype=tf.float32) * 200.0
    labels_a = tf.constant([[1.0, 0.0], [1.0, 0.0]])
    labels_b = tf.constant([[0.0, 1.0], [0.0, 1.0]])

    mixed_images, mixed_labels = mixup_pair(
        (images_a, labels_a),
        (images_b, labels_b),
        alpha=0.2,
        seed=11,
    )

    img_arr = mixed_images.numpy()
    lab_arr = mixed_labels.numpy()

    # Mixed pixels must lie strictly between 100 and 200.
    assert (img_arr > 100.0).all() and (img_arr < 200.0).all()
    # Mixed one-hot labels must sum to 1 along the class axis (within tol).
    np.testing.assert_allclose(lab_arr.sum(axis=1), 1.0, atol=1e-6)


def test_mixup_pair_disabled_when_alpha_zero() -> None:
    from cropcare_training.augmentation import mixup_pair

    images_a = tf.ones((1, 2, 2, 3), dtype=tf.float32) * 50.0
    images_b = tf.ones((1, 2, 2, 3), dtype=tf.float32) * 250.0
    labels_a = tf.constant([[1.0, 0.0]])
    labels_b = tf.constant([[0.0, 1.0]])

    mixed_images, mixed_labels = mixup_pair(
        (images_a, labels_a),
        (images_b, labels_b),
        alpha=0.0,
        seed=11,
    )

    np.testing.assert_array_equal(mixed_images.numpy(), images_a.numpy())
    np.testing.assert_array_equal(mixed_labels.numpy(), labels_a.numpy())


def test_eggplant_conditional_augmentation_only_perturbs_eggplant_rows() -> None:
    from cropcare_training.augmentation import apply_eggplant_extra_aug

    # 4 samples: 0 = eggplant_healthy, 1 = tomato_healthy, 2 = eggplant_leaf_spot, 3 = pepper_healthy
    label_names = [
        "eggplant_healthy",
        "tomato_healthy",
        "eggplant_leaf_spot",
        "pepper_healthy",
    ]
    images = tf.constant(
        np.tile(
            np.linspace(0, 255, 64, dtype=np.float32).reshape(1, 8, 8, 1),
            (4, 1, 1, 3),
        ),
        dtype=tf.float32,
    )
    labels_one_hot = tf.eye(len(label_names), dtype=tf.float32)

    out_images = apply_eggplant_extra_aug(
        images,
        labels_one_hot,
        class_names=label_names,
        seed=42,
    ).numpy()

    # Tomato (idx 1) and pepper (idx 3) rows must be untouched.
    np.testing.assert_array_equal(out_images[1], images.numpy()[1])
    np.testing.assert_array_equal(out_images[3], images.numpy()[3])
    # Both eggplant rows must differ from input.
    assert not np.array_equal(out_images[0], images.numpy()[0])
    assert not np.array_equal(out_images[2], images.numpy()[2])
