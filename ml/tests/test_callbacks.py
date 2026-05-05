from pathlib import Path

import numpy as np
import pytest

tf = pytest.importorskip("tensorflow")


def _toy_classifier(num_classes: int):
    inputs = tf.keras.Input(shape=(4,))
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax")(inputs)
    model = tf.keras.Model(inputs=inputs, outputs=outputs)
    model.compile(optimizer="adam", loss="categorical_crossentropy")
    return model


def test_best_macro_f1_checkpoint_writes_weights_when_score_improves(
    tmp_path: Path,
) -> None:
    from cropcare_training.callbacks import BestMacroF1Checkpoint

    rng = np.random.default_rng(0)
    x_val = rng.normal(size=(8, 4)).astype(np.float32)
    y_val = np.zeros((8, 3), dtype=np.float32)
    y_val[np.arange(8), rng.integers(0, 3, size=8)] = 1.0

    checkpoint_path = tmp_path / "best.weights.h5"
    callback = BestMacroF1Checkpoint(
        validation_data=(x_val, y_val),
        filepath=str(checkpoint_path),
    )

    model = _toy_classifier(3)
    model.fit(
        x=rng.normal(size=(32, 4)).astype(np.float32),
        y=np.eye(3, dtype=np.float32)[rng.integers(0, 3, size=32)],
        batch_size=8,
        epochs=2,
        verbose=0,
        callbacks=[callback],
    )

    assert checkpoint_path.exists()
    assert callback.best_macro_f1 >= 0.0


def test_best_macro_f1_checkpoint_returns_zero_for_empty_validation(
    tmp_path: Path,
) -> None:
    from cropcare_training.callbacks import BestMacroF1Checkpoint

    callback = BestMacroF1Checkpoint(
        validation_data=(
            np.empty((0, 4), dtype=np.float32),
            np.empty((0, 3), dtype=np.float32),
        ),
        filepath=str(tmp_path / "best.weights.h5"),
    )

    score = callback._compute_macro_f1(
        np.empty((0, 3), dtype=np.float32),
        np.empty((0, 3), dtype=np.float32),
    )

    assert score == 0.0
