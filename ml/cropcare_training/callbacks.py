"""Custom Keras callbacks for CropCare v2 training."""

from __future__ import annotations

from pathlib import Path

try:
    import tensorflow as tf

    _CallbackBase = tf.keras.callbacks.Callback
except ImportError:  # pragma: no cover - environment guard
    _CallbackBase = object


class BestMacroF1Checkpoint(_CallbackBase):
    """Save model weights whenever validation macro-F1 improves.

    Keras lacks a built-in macro-F1 monitor, so we compute it with
    sklearn at the end of each epoch and write the model weights to
    ``filepath`` when the score is strictly greater than the previous
    best. The score is also added to the ``logs`` dict under
    ``val_macro_f1`` so other callbacks (e.g. ``CSVLogger``) can record
    it.
    """

    def __init__(
        self,
        *,
        validation_data,
        filepath: str,
        verbose: int = 1,
    ) -> None:
        super().__init__()
        self._validation_data = validation_data
        self._filepath = Path(filepath)
        self._filepath.parent.mkdir(parents=True, exist_ok=True)
        self._verbose = verbose
        self.best_macro_f1: float = -1.0

    def on_epoch_end(self, epoch: int, logs: dict | None = None) -> None:
        x_val, y_val = self._validation_data
        if len(x_val) == 0:
            return

        predictions = self.model.predict(x_val, verbose=0)
        score = self._compute_macro_f1(y_val, predictions)
        logs = logs if logs is not None else {}
        logs["val_macro_f1"] = score

        if score > self.best_macro_f1:
            previous = self.best_macro_f1
            self.best_macro_f1 = score
            self.model.save_weights(self._filepath)
            if self._verbose:
                print(
                    f"\nEpoch {epoch + 1}: val_macro_f1 improved "
                    f"{previous:.4f} -> {score:.4f}; saved to {self._filepath}"
                )

    @staticmethod
    def _compute_macro_f1(y_true_one_hot, y_pred_probabilities) -> float:
        import numpy as np
        from sklearn.metrics import f1_score

        y_true = np.asarray(y_true_one_hot)
        y_pred = np.asarray(y_pred_probabilities)
        if y_true.size == 0 or y_pred.size == 0:
            return 0.0
        return float(
            f1_score(
                y_true.argmax(axis=1),
                y_pred.argmax(axis=1),
                average="macro",
                zero_division=0,
            )
        )
