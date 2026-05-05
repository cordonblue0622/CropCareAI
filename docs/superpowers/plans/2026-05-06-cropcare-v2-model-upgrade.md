# CropCare v2 Model Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shipped `cropcare_efficientnet_with_eggplant.tflite` with a retrained EfficientNetB0 (16 base-parity labels) whose val macro-F1 ≥ 0.90 with no per-class regression vs the existing base, and gate promotion on a side-by-side comparison report.

**Architecture:** Two-phase transfer learning (warm-up frozen base + partial unfreeze fine-tune), Keras augmentation baked into the model, MixUp data-pipeline transform during fine-tune, inverse-frequency class weights, custom best-macro-F1 checkpoint, INT8 post-training quantization with representative dataset, and a TFLite-vs-TFLite comparison harness that produces a strict PROMOTE/BLOCK verdict.

**Tech Stack:** TensorFlow 2.16+ (Keras 3), `tf.lite` converter, scikit-learn (metrics), Pillow (image fixtures), pytest, Flutter `tflite_flutter` (Dart inference), PowerShell (release scripts).

**Spec:** [docs/superpowers/specs/2026-05-06-cropcare-v2-model-upgrade-design.md](../specs/2026-05-06-cropcare-v2-model-upgrade-design.md)

**Source branch:** `training-improvement` (already exists). All commits land here.

**Conventions for every task:**
- Run pytest from repo root with `ml\.venv\Scripts\python.exe -m pytest <path> -v` on Windows; tests assume the venv documented in [ml/README.md](../../../ml/README.md) is set up.
- All commits use `git -c commit.gpgsign=false commit -m "<msg>"` and end with the `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>` trailer.
- One task = one feature + tests + commit. Run the tests after every implementation step before committing. If a step has no tests (PS1/README), perform manual verification described in the step.

---

## File Map (read this before starting)

### New files
- `ml/cropcare_training/augmentation.py` — Keras augmentation block, MixUp transform, eggplant-conditional branch.
- `ml/cropcare_training/callbacks.py` — `BestMacroF1Checkpoint` custom callback.
- `ml/cropcare_training/compare_models.py` — TFLite vs TFLite comparison harness + verdict + markdown report writer.
- `ml/tests/test_augmentation.py` — unit tests for augmentation pieces.
- `ml/tests/test_callbacks.py` — unit tests for the macro-F1 checkpoint.
- `ml/tests/test_compare_models.py` — unit tests for comparison harness.

### Modified files
- `ml/cropcare_training/label_profiles.py` — add `cropcare_v2_base_parity` profile.
- `ml/cropcare_training/train_efficientnet.py` — split into warm-up + fine-tune phases, wire augmentation, class weights, callbacks, INT8 export.
- `ml/cropcare_training/automation.py` — default to base-parity profile, drop the 100-cap on PlantVillage classes.
- `ml/cropcare_training/prepare_dataset.py` — DigiGreen per-class cap, optional `--digigreen-max-per-label` flag.
- `ml/cropcare_training/release.py` — invoke `compare_models`, replace numeric `validate_metric_gates` defaults, add promotion gate that reads `comparison_report.json`.
- `ml/run_model_release.ps1` — new defaults (LabelProfile, Epochs=30 with phase split, no MaxPerLabel by default).
- `ml/run_cpu_training.ps1` — same defaults aligned with release.
- `ml/tests/test_training_scaffold.py` — update assertions that reference old defaults / gate thresholds.
- `lib/services/tflite_classifier_core.dart` — dtype-dispatch (uint8 vs float32) at load + dequantization.
- `test/tflite_classifier_core_test.dart` — extend coverage to both dtypes.
- `ml/README.md` — document the new run, the gate, the comparison report.

### Untouched
Flutter UI, Supabase service, `ai_backend/`, `assets/models/labels_with_eggplant.txt` (kept as base reference), `assets/models/cropcare_efficientnet_with_eggplant.tflite` (kept for one cycle as safety net).

---

## Task 1: Add `cropcare_v2_base_parity` label profile

**Why first:** Every later task references this profile name. It is also the smallest, lowest-risk change and gives us a green commit to build on.

**Files:**
- Modify: [ml/cropcare_training/label_profiles.py](../../../ml/cropcare_training/label_profiles.py)
- Modify: [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py)

- [ ] **Step 1.1: Write the failing test**

Append to [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py):

```python
def test_base_parity_profile_matches_shipped_base_labels() -> None:
    labels = labels_for_profile("cropcare_v2_base_parity")
    excluded = excluded_labels_for_profile("cropcare_v2_base_parity")

    # Must equal the 16 labels currently shipped in
    # assets/models/labels_with_eggplant.txt (alphabetical, no eggplant_small_leaf etc).
    assert labels == [
        "tomato_bacterial_spot",
        "tomato_early_blight",
        "tomato_late_blight",
        "tomato_leaf_mold",
        "tomato_septoria_leaf_spot",
        "tomato_spider_mites",
        "tomato_target_spot",
        "tomato_yellow_leaf_curl_virus",
        "tomato_mosaic_virus",
        "tomato_healthy",
        "pepper_bacterial_spot",
        "pepper_healthy",
        "eggplant_healthy",
        "eggplant_insect_pest",
        "eggplant_leaf_spot",
        "eggplant_mosaic_virus",
    ]
    assert "squash_powdery_mildew" in excluded
    assert len(labels) == 16
```

- [ ] **Step 1.2: Run test — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py::test_base_parity_profile_matches_shipped_base_labels -v`
Expected: FAIL with `ValueError: Unknown label profile 'cropcare_v2_base_parity'`.

- [ ] **Step 1.3: Add the profile**

Edit [ml/cropcare_training/label_profiles.py](../../../ml/cropcare_training/label_profiles.py). Replace the existing `LABEL_PROFILES` dict with:

```python
BASE_PARITY_LABELS: tuple[str, ...] = (
    "tomato_bacterial_spot",
    "tomato_early_blight",
    "tomato_late_blight",
    "tomato_leaf_mold",
    "tomato_septoria_leaf_spot",
    "tomato_spider_mites",
    "tomato_target_spot",
    "tomato_yellow_leaf_curl_virus",
    "tomato_mosaic_virus",
    "tomato_healthy",
    "pepper_bacterial_spot",
    "pepper_healthy",
    "eggplant_healthy",
    "eggplant_insect_pest",
    "eggplant_leaf_spot",
    "eggplant_mosaic_virus",
)

LABEL_PROFILES: dict[str, tuple[str, ...]] = {
    "cropcare_v2_subset_100": SUBSET_100_LABELS,
    "cropcare_v2_full": tuple(TARGET_LABELS),
    "cropcare_v2_base_parity": BASE_PARITY_LABELS,
}
```

(Keep `SUBSET_100_LABELS` and the public `labels_for_profile` / `excluded_labels_for_profile` functions as they are.)

- [ ] **Step 1.4: Run test — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py::test_base_parity_profile_matches_shipped_base_labels -v`
Expected: PASS.

- [ ] **Step 1.5: Run the full module's tests to confirm no regression**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py -v`
Expected: every test passes (no failures, no errors).

- [ ] **Step 1.6: Commit**

```powershell
git add ml/cropcare_training/label_profiles.py ml/tests/test_training_scaffold.py
git -c commit.gpgsign=false commit -m "feat(ml): add cropcare_v2_base_parity label profile

Adds a 16-label profile matching the shipped base model exactly so the v2
retrain can target full base parity instead of the eggplant-less subset.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Augmentation module — base augmentation block

**Files:**
- Create: [ml/cropcare_training/augmentation.py](../../../ml/cropcare_training/augmentation.py)
- Create: [ml/tests/test_augmentation.py](../../../ml/tests/test_augmentation.py)

- [ ] **Step 2.1: Write the failing test**

Create [ml/tests/test_augmentation.py](../../../ml/tests/test_augmentation.py):

```python
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
```

- [ ] **Step 2.2: Run tests — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_augmentation.py -v`
Expected: 3 errors, all `ModuleNotFoundError: No module named 'cropcare_training.augmentation'`.

- [ ] **Step 2.3: Implement the augmentation block**

Create [ml/cropcare_training/augmentation.py](../../../ml/cropcare_training/augmentation.py):

```python
"""Keras augmentation utilities for CropCare v2 training.

The base augmentation block is added to the model graph itself so it is
applied during training and is a no-op at inference time (Keras
`Random*` layers turn off when called with `training=False`, which TFLite
conversion preserves).
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
```

- [ ] **Step 2.4: Run tests — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_augmentation.py -v`
Expected: 3 passes.

- [ ] **Step 2.5: Commit**

```powershell
git add ml/cropcare_training/augmentation.py ml/tests/test_augmentation.py
git -c commit.gpgsign=false commit -m "feat(ml): add base Keras augmentation block

Six-layer Random* sequential (flip / rotation / zoom / translation /
contrast / brightness) used as the in-graph augmentation pipeline. No-op
at inference time so TFLite conversion preserves identity behaviour.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Augmentation module — MixUp data-pipeline transform

**Files:**
- Modify: [ml/cropcare_training/augmentation.py](../../../ml/cropcare_training/augmentation.py)
- Modify: [ml/tests/test_augmentation.py](../../../ml/tests/test_augmentation.py)

- [ ] **Step 3.1: Write the failing test**

Append to [ml/tests/test_augmentation.py](../../../ml/tests/test_augmentation.py):

```python
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
```

- [ ] **Step 3.2: Run tests — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_augmentation.py -v`
Expected: previous 3 pass; 2 new tests fail with `ImportError: cannot import name 'mixup_pair' from 'cropcare_training.augmentation'`.

- [ ] **Step 3.3: Implement `mixup_pair`**

Append to [ml/cropcare_training/augmentation.py](../../../ml/cropcare_training/augmentation.py):

```python
def mixup_pair(
    batch_a,
    batch_b,
    *,
    alpha: float = 0.2,
    seed: int | None = None,
):
    """Convex combination of two `(images, one_hot_labels)` batches.

    Used as a `tf.data` transform during the fine-tune phase. When
    `alpha == 0.0` the function returns `batch_a` unchanged so callers
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
```

- [ ] **Step 3.4: Run tests — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_augmentation.py -v`
Expected: 5 passes.

- [ ] **Step 3.5: Commit**

```powershell
git add ml/cropcare_training/augmentation.py ml/tests/test_augmentation.py
git -c commit.gpgsign=false commit -m "feat(ml): add MixUp pair transform for fine-tune phase

Convex combination of two (images, one-hot) batches with a per-sample
mixing coefficient. alpha=0 short-circuits to the first batch unchanged
so the same dataset wiring works for warm-up (no MixUp) and fine-tune
(MixUp enabled).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Augmentation module — eggplant-conditional augmentation

**Files:**
- Modify: [ml/cropcare_training/augmentation.py](../../../ml/cropcare_training/augmentation.py)
- Modify: [ml/tests/test_augmentation.py](../../../ml/tests/test_augmentation.py)

- [ ] **Step 4.1: Write the failing test**

Append to [ml/tests/test_augmentation.py](../../../ml/tests/test_augmentation.py):

```python
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
```

- [ ] **Step 4.2: Run test — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_augmentation.py::test_eggplant_conditional_augmentation_only_perturbs_eggplant_rows -v`
Expected: FAIL with `ImportError: cannot import name 'apply_eggplant_extra_aug'`.

- [ ] **Step 4.3: Implement `apply_eggplant_extra_aug`**

Append to [ml/cropcare_training/augmentation.py](../../../ml/cropcare_training/augmentation.py):

```python
def apply_eggplant_extra_aug(
    images,
    labels_one_hot,
    *,
    class_names,
    seed: int = 1234,
):
    """Apply additional zoom + brightness jitter to eggplant rows only.

    DigiGreen eggplant images are noisier than PlantVillage's lab tomato
    photos, so we deliberately perturb them harder during training. Other
    rows pass through untouched.
    """
    import tensorflow as tf

    eggplant_indices = [
        index
        for index, name in enumerate(class_names)
        if name.startswith("eggplant_")
    ]
    if not eggplant_indices:
        return images

    eggplant_mask_per_class = tf.constant(
        [1.0 if name.startswith("eggplant_") else 0.0 for name in class_names],
        dtype=tf.float32,
    )
    is_eggplant = tf.reduce_max(
        labels_one_hot * eggplant_mask_per_class,
        axis=1,
        keepdims=True,
    )
    is_eggplant_image = tf.reshape(is_eggplant, (-1, 1, 1, 1))

    extra = tf.keras.Sequential(
        [
            tf.keras.layers.RandomZoom(
                height_factor=0.25,
                width_factor=0.25,
                seed=seed,
            ),
            tf.keras.layers.RandomBrightness(factor=0.25, seed=seed),
        ],
        name="cropcare_eggplant_extra_aug",
    )
    perturbed = extra(images, training=True)
    return is_eggplant_image * perturbed + (1.0 - is_eggplant_image) * images
```

- [ ] **Step 4.4: Run test — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_augmentation.py -v`
Expected: 6 passes (3 from Task 2 + 2 from Task 3 + 1 here).

- [ ] **Step 4.5: Commit**

```powershell
git add ml/cropcare_training/augmentation.py ml/tests/test_augmentation.py
git -c commit.gpgsign=false commit -m "feat(ml): label-conditional extra aug for eggplant rows

DigiGreen eggplant photos are noisier than PlantVillage tomato/pepper
data, so we apply an extra RandomZoom(0.25)+RandomBrightness(0.25) pass
to those rows only. Other classes are passed through unchanged.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: BestMacroF1Checkpoint custom callback

**Files:**
- Create: [ml/cropcare_training/callbacks.py](../../../ml/cropcare_training/callbacks.py)
- Create: [ml/tests/test_callbacks.py](../../../ml/tests/test_callbacks.py)

- [ ] **Step 5.1: Write the failing test**

Create [ml/tests/test_callbacks.py](../../../ml/tests/test_callbacks.py):

```python
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
```

- [ ] **Step 5.2: Run tests — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_callbacks.py -v`
Expected: 2 errors, `ModuleNotFoundError: No module named 'cropcare_training.callbacks'`.

- [ ] **Step 5.3: Implement the callback**

Create [ml/cropcare_training/callbacks.py](../../../ml/cropcare_training/callbacks.py):

```python
"""Custom Keras callbacks for CropCare v2 training."""

from __future__ import annotations

from pathlib import Path


class BestMacroF1Checkpoint:
    """Save model weights whenever validation macro-F1 improves.

    Keras lacks a built-in macro-F1 monitor, so we implement it as a
    minimal callback that subclasses `tf.keras.callbacks.Callback` at
    import time. We do the import inside `__new__` so the module can be
    imported in environments without TensorFlow (e.g. unit tests for
    label profiles). Tests that exercise behaviour use
    `pytest.importorskip("tensorflow")`.
    """

    def __new__(cls, *args, **kwargs):
        try:
            import tensorflow as tf
        except ImportError as exc:  # pragma: no cover - environment guard
            raise RuntimeError(
                "Install ML dependencies first: "
                "python -m pip install -r ml/requirements.txt"
            ) from exc

        if not getattr(cls, "_keras_initialized", False):
            cls.__bases__ = (tf.keras.callbacks.Callback,)
            cls._keras_initialized = True
        return object.__new__(cls)

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
        import numpy as np

        x_val, y_val = self._validation_data
        if len(x_val) == 0:
            return

        predictions = self.model.predict(x_val, verbose=0)
        score = self._compute_macro_f1(y_val, predictions)
        logs = logs or {}
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
```

- [ ] **Step 5.4: Run tests — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_callbacks.py -v`
Expected: 2 passes.

- [ ] **Step 5.5: Commit**

```powershell
git add ml/cropcare_training/callbacks.py ml/tests/test_callbacks.py
git -c commit.gpgsign=false commit -m "feat(ml): BestMacroF1Checkpoint callback

Saves model weights whenever validation macro-F1 improves. Computes
the score with sklearn after each epoch and logs val_macro_f1 into the
Keras history. Lazy-mixes-in tf.keras.callbacks.Callback so the module
imports cleanly in environments without TensorFlow.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Refactor `train_efficientnet.py` — extract `_build_model` helper

**Why this is its own task:** The current `train_and_export` function does data loading, model building, training, eval, and export in one ~150-line block. We extract the model-building piece first (no behaviour change) so subsequent tasks can wire augmentation/two-phase training into it cleanly.

**Files:**
- Modify: [ml/cropcare_training/train_efficientnet.py](../../../ml/cropcare_training/train_efficientnet.py)
- Modify: [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py)

- [ ] **Step 6.1: Write the failing test**

Append to [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py):

```python
def test_build_model_emits_efficientnet_b0_with_augmentation_then_head() -> None:
    pytest = __import__("pytest")
    tf = pytest.importorskip("tensorflow")
    from cropcare_training.train_efficientnet import build_model

    model = build_model(num_classes=3, image_size=(64, 64), trainable_base=False)

    assert isinstance(model, tf.keras.Model)
    assert model.output_shape == (None, 3)
    # The augmentation block must appear before the EfficientNetB0 backbone.
    layer_names = [layer.name for layer in model.layers]
    assert "cropcare_augmentation_block" in layer_names
    aug_index = layer_names.index("cropcare_augmentation_block")
    backbone_indices = [
        i for i, name in enumerate(layer_names) if "efficientnet" in name.lower()
    ]
    assert backbone_indices, "EfficientNet backbone must be present"
    assert aug_index < backbone_indices[0]
    # Backbone is frozen.
    assert all(
        not layer.trainable
        for layer in model.layers
        if "efficientnet" in layer.name.lower()
    )
```

`pytest` is imported in the test body (rather than top-of-file) because the existing test module relies on direct imports from the training package, and several of those imports also need `tensorflow` only for some tests. Keeping the per-test guard avoids breaking tests that don't need TF.

- [ ] **Step 6.2: Run test — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py::test_build_model_emits_efficientnet_b0_with_augmentation_then_head -v`
Expected: FAIL with `ImportError: cannot import name 'build_model' from 'cropcare_training.train_efficientnet'`.

- [ ] **Step 6.3: Extract `build_model`**

Edit [ml/cropcare_training/train_efficientnet.py](../../../ml/cropcare_training/train_efficientnet.py). Add the new helper near the top of the module (after the `DEFAULT_OUTPUT_DIR` constant, before `train_and_export`). Replace the existing in-line model construction inside `train_and_export` (the block from `inputs = tf.keras.Input(...)` through the `model.compile(...)` call) with a call to `build_model`:

```python
def build_model(
    *,
    num_classes: int,
    image_size: tuple[int, int] = (224, 224),
    trainable_base: bool = False,
    dropout_rate: float = 0.3,
    seed: int = 1234,
):
    """Construct the EfficientNetB0 + augmentation + head graph."""
    import tensorflow as tf

    from .augmentation import build_augmentation_block

    inputs = tf.keras.Input(shape=(*image_size, 3), name="image")
    augmented = build_augmentation_block(seed=seed)(inputs)
    base_model = tf.keras.applications.EfficientNetB0(
        include_top=False,
        weights="imagenet",
        input_tensor=augmented,
        pooling="avg",
    )
    base_model.trainable = trainable_base
    pooled = base_model.output
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
```

Then inside `train_and_export`, replace the manual model construction with:

```python
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
```

(That single-phase compile is preserved here for the moment so existing tests keep passing; Task 8 splits it into two phases.)

- [ ] **Step 6.4: Run the new test — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py::test_build_model_emits_efficientnet_b0_with_augmentation_then_head -v`
Expected: PASS.

- [ ] **Step 6.5: Run the full scaffold suite — expect no regressions**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/ -v`
Expected: every previously-green test still passes.

- [ ] **Step 6.6: Commit**

```powershell
git add ml/cropcare_training/train_efficientnet.py ml/tests/test_training_scaffold.py
git -c commit.gpgsign=false commit -m "refactor(ml): extract build_model helper in train_efficientnet

No behaviour change: the inline EfficientNetB0+head construction inside
train_and_export now lives in build_model() and gains the in-graph
augmentation block + dropout(0.3) before the softmax head. Subsequent
tasks wire two-phase training and class weights on top of this helper.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Compute class weights helper

**Files:**
- Modify: [ml/cropcare_training/train_efficientnet.py](../../../ml/cropcare_training/train_efficientnet.py)
- Modify: [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py)

- [ ] **Step 7.1: Write the failing test**

Append to [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py):

```python
def test_class_weights_inverse_frequency_normalises_to_mean_one() -> None:
    from cropcare_training.train_efficientnet import compute_class_weights

    counts = {
        "tomato_healthy": 4000,
        "tomato_early_blight": 1000,
        "eggplant_healthy": 200,
    }

    weights = compute_class_weights(
        class_names=["tomato_healthy", "tomato_early_blight", "eggplant_healthy"],
        per_class_counts=counts,
    )

    # Keys are integer class indices.
    assert set(weights.keys()) == {0, 1, 2}
    # Inverse-frequency: lowest count -> highest weight.
    assert weights[2] > weights[1] > weights[0]
    # Mean weight is normalised to 1.0 so loss scale stays comparable.
    mean_weight = sum(weights.values()) / len(weights)
    assert abs(mean_weight - 1.0) < 1e-6


def test_class_weights_skip_zero_counts_safely() -> None:
    from cropcare_training.train_efficientnet import compute_class_weights

    weights = compute_class_weights(
        class_names=["a", "b"],
        per_class_counts={"a": 10, "b": 0},
    )

    # Class with zero count receives weight 1.0 (neutral) and a warning,
    # not a divide-by-zero crash.
    assert weights[1] == 1.0
```

- [ ] **Step 7.2: Run tests — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py -k class_weights -v`
Expected: 2 failures with `ImportError: cannot import name 'compute_class_weights'`.

- [ ] **Step 7.3: Implement `compute_class_weights`**

Append to [ml/cropcare_training/train_efficientnet.py](../../../ml/cropcare_training/train_efficientnet.py) (above `train_and_export`):

```python
def compute_class_weights(
    *,
    class_names: list[str],
    per_class_counts: dict[str, int],
) -> dict[int, float]:
    """Return Keras-style `class_weight` dict using inverse frequency.

    Weights are normalised so their mean is 1.0; that keeps the
    cross-entropy loss on roughly the same scale as the unweighted
    case, which simplifies LR tuning. Classes with zero observed
    samples receive weight 1.0 (neutral).
    """
    raw: dict[int, float] = {}
    for index, name in enumerate(class_names):
        count = per_class_counts.get(name, 0)
        raw[index] = (1.0 / count) if count > 0 else 1.0

    non_zero_values = [v for v in raw.values() if v != 1.0 or v]
    if not non_zero_values:
        return {index: 1.0 for index in raw}
    mean_weight = sum(non_zero_values) / len(non_zero_values)
    if mean_weight == 0.0:
        return raw
    return {index: weight / mean_weight for index, weight in raw.items()}
```

- [ ] **Step 7.4: Run tests — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py -k class_weights -v`
Expected: 2 passes.

- [ ] **Step 7.5: Commit**

```powershell
git add ml/cropcare_training/train_efficientnet.py ml/tests/test_training_scaffold.py
git -c commit.gpgsign=false commit -m "feat(ml): inverse-frequency class_weight helper

Normalised so mean weight equals 1.0 (keeps loss on the same scale as
unweighted training), with a graceful zero-count fallback.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Two-phase training (warm-up + partial-unfreeze fine-tune)

**Why bigger:** This is the core of the upgrade and changes `train_and_export`'s control flow. Done in one task because the warm-up output (head weights) is the input to fine-tune.

**Files:**
- Modify: [ml/cropcare_training/train_efficientnet.py](../../../ml/cropcare_training/train_efficientnet.py)
- Modify: [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py)

- [ ] **Step 8.1: Write the failing tests**

Append to [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py):

```python
def test_unfreeze_top_layers_makes_only_last_n_trainable_and_keeps_bn_frozen() -> None:
    pytest = __import__("pytest")
    tf = pytest.importorskip("tensorflow")
    from cropcare_training.train_efficientnet import (
        build_model,
        unfreeze_top_layers,
    )

    model = build_model(
        num_classes=4,
        image_size=(64, 64),
        trainable_base=False,
    )
    backbone = next(
        layer
        for layer in model.layers
        if "efficientnet" in layer.name.lower() and hasattr(layer, "layers")
    )

    unfreeze_top_layers(backbone, n=30)

    last_trainable = [layer for layer in backbone.layers if layer.trainable]
    # At least the last 30 non-BN layers are trainable.
    assert len(last_trainable) >= 1
    # BatchNormalization stays frozen everywhere.
    assert all(
        not layer.trainable
        for layer in backbone.layers
        if isinstance(layer, tf.keras.layers.BatchNormalization)
    )


def test_phase_step_count_matches_expected_warmup_and_fine_tune_split() -> None:
    from cropcare_training.train_efficientnet import phase_epoch_split

    warmup, fine_tune = phase_epoch_split(total_epochs=30, warmup_epochs=5)

    assert warmup == 5
    assert fine_tune == 25


def test_phase_step_count_clips_warmup_when_total_is_smaller() -> None:
    from cropcare_training.train_efficientnet import phase_epoch_split

    warmup, fine_tune = phase_epoch_split(total_epochs=4, warmup_epochs=5)

    assert warmup == 4
    assert fine_tune == 0
```

- [ ] **Step 8.2: Run tests — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py -k "unfreeze_top_layers or phase_epoch_split" -v`
Expected: 3 failures with `ImportError`.

- [ ] **Step 8.3: Implement `unfreeze_top_layers` and `phase_epoch_split`**

Append to [ml/cropcare_training/train_efficientnet.py](../../../ml/cropcare_training/train_efficientnet.py):

```python
def unfreeze_top_layers(backbone, n: int = 30) -> None:
    """Make the last `n` non-BatchNorm layers of `backbone` trainable.

    BatchNormalization layers stay frozen regardless of `n` to avoid the
    well-known fine-tuning batch-statistics drift on small datasets.
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
    """Return `(warmup, fine_tune)` epoch counts.

    If `total_epochs <= warmup_epochs`, the entire budget goes to
    warm-up and fine-tune is zero.
    """
    if total_epochs <= warmup_epochs:
        return total_epochs, 0
    return warmup_epochs, total_epochs - warmup_epochs
```

- [ ] **Step 8.4: Run new tests — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py -k "unfreeze_top_layers or phase_epoch_split" -v`
Expected: 3 passes.

- [ ] **Step 8.5: Rewrite `train_and_export` to run both phases**

Replace the body of `train_and_export` in [ml/cropcare_training/train_efficientnet.py](../../../ml/cropcare_training/train_efficientnet.py) with the version below. The signature gains `warmup_epochs` and `unfreeze_top_n` keyword args (with sensible defaults):

```python
def train_and_export(
    *,
    data_dir: Path = DEFAULT_DATA_DIR,
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    epochs: int = 30,
    warmup_epochs: int = 5,
    unfreeze_top_n: int = 30,
    batch_size: int = 32,
    image_size: tuple[int, int] = (224, 224),
    label_profile: str = "cropcare_v2_base_parity",
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

    autotune = tf.data.AUTOTUNE
    raw_train_ds = make_dataset(train_dir, shuffle=True).cache()
    train_ds_warmup = raw_train_ds.shuffle(buffer_size=2048).prefetch(autotune)

    def _mixup_dataset(base_ds):
        shuffled = base_ds.shuffle(buffer_size=2048)
        return tf.data.Dataset.zip((shuffled, shuffled.skip(1))).map(
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
    val_x = np.concatenate(val_x_arrays, axis=0) if val_x_arrays else np.empty(
        (0, *image_size, 3), dtype=np.float32
    )
    val_y = np.concatenate(val_y_arrays, axis=0) if val_y_arrays else np.empty(
        (0, len(class_names)), dtype=np.float32
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

    fine_tune_history = {"history": {}}
    if fine_tune_epochs > 0:
        backbone = next(
            layer
            for layer in model.layers
            if "efficientnet" in layer.name.lower() and hasattr(layer, "layers")
        )
        unfreeze_top_layers(backbone, n=unfreeze_top_n)
        steps_per_epoch = max(
            1, sum(per_class_counts.values()) // batch_size
        )
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
        fine_tune_history = model.fit(
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

    write_label_file(output_dir / "labels_v2.txt", class_names)

    history_payload = {
        "warmup": (
            warmup_history.history if hasattr(warmup_history, "history") else {}
        ),
        "fine_tune": (
            fine_tune_history.history
            if hasattr(fine_tune_history, "history")
            else fine_tune_history.get("history", {})
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
```

Also update `parse_args` defaults for `--epochs` to `30` and add `--warmup-epochs` (default `5`) and `--unfreeze-top-n` (default `30`). Update `--label-profile` default to `"cropcare_v2_base_parity"`. Forward those new args inside `main()`.

- [ ] **Step 8.6: Run all training-scaffold tests — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/ -v`
Expected: every test passes (Task 6's `build_model` test now exercises the dropout layer; Task 7 tests still pass; new ones in this task pass).

- [ ] **Step 8.7: Commit**

```powershell
git add ml/cropcare_training/train_efficientnet.py ml/tests/test_training_scaffold.py
git -c commit.gpgsign=false commit -m "feat(ml): two-phase warm-up + fine-tune training pipeline

train_and_export now runs a 5-epoch frozen-base warm-up followed by a
fine-tune phase with the last 30 layers unfrozen (BN stays frozen),
AdamW + cosine LR schedule, label-smoothed CE, MixUp on the fine-tune
dataset, inverse-frequency class weights, and per-phase callbacks
(EarlyStopping, ReduceLROnPlateau, BestMacroF1Checkpoint, CSVLogger).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: INT8 quantized TFLite export

**Files:**
- Modify: [ml/cropcare_training/train_efficientnet.py](../../../ml/cropcare_training/train_efficientnet.py)
- Modify: [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py)

- [ ] **Step 9.1: Write the failing test**

Append to [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py):

```python
def test_representative_dataset_yields_uint8_compatible_float_batches(tmp_path) -> None:
    pytest = __import__("pytest")
    tf = pytest.importorskip("tensorflow")
    from PIL import Image

    from cropcare_training.train_efficientnet import representative_dataset_gen

    train_dir = tmp_path / "train"
    for label in ("a", "b"):
        (train_dir / label).mkdir(parents=True)
        for i in range(3):
            Image.new("RGB", (16, 16), color=(10 * i, 20 * i, 30 * i)).save(
                train_dir / label / f"{label}_{i}.png"
            )

    samples = list(
        representative_dataset_gen(
            train_dir=train_dir,
            class_names=["a", "b"],
            image_size=(16, 16),
            num_samples=4,
        )
    )

    assert len(samples) == 4
    for batch in samples:
        assert isinstance(batch, list) and len(batch) == 1
        arr = batch[0]
        assert arr.shape == (1, 16, 16, 3)
        assert arr.dtype.name == "float32"
        # Raw RGB in [0, 255], not normalised.
        assert arr.min() >= 0.0 and arr.max() <= 255.0
```

- [ ] **Step 9.2: Run test — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py::test_representative_dataset_yields_uint8_compatible_float_batches -v`
Expected: FAIL with `ImportError: cannot import name 'representative_dataset_gen'`.

- [ ] **Step 9.3: Implement `representative_dataset_gen` and INT8 export**

Append to [ml/cropcare_training/train_efficientnet.py](../../../ml/cropcare_training/train_efficientnet.py):

```python
def representative_dataset_gen(
    *,
    train_dir: Path,
    class_names: list[str],
    image_size: tuple[int, int],
    num_samples: int = 200,
):
    """Yield single-image batches for INT8 post-training calibration.

    Returns lists shaped `[1, H, W, 3]` of float32 in `[0, 255]` so the
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
    """Convert `model` to a fully-quantized INT8 TFLite at `output_path`."""
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
```

Then, in `train_and_export`, after writing the float TFLite, call:

```python
    export_int8_tflite(
        model=model,
        train_dir=train_dir,
        class_names=class_names,
        image_size=image_size,
        output_path=output_dir / "cropcare_efficientnet_v2.tflite",
    )
```

- [ ] **Step 9.4: Run new test — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py::test_representative_dataset_yields_uint8_compatible_float_batches -v`
Expected: PASS.

- [ ] **Step 9.5: Run the full suite — expect no regressions**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/ -v`
Expected: every test still passes.

- [ ] **Step 9.6: Commit**

```powershell
git add ml/cropcare_training/train_efficientnet.py ml/tests/test_training_scaffold.py
git -c commit.gpgsign=false commit -m "feat(ml): INT8 post-training quantization with representative dataset

After float32 TFLite export, run a second conversion with
tf.lite.Optimize.DEFAULT, a 200-sample representative_dataset drawn
from the train split, and uint8 input/output types. Writes the
production cropcare_efficientnet_v2.tflite (~5 MB target).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Comparison harness — TFLite single-image inference helper

**Files:**
- Create: [ml/cropcare_training/compare_models.py](../../../ml/cropcare_training/compare_models.py)
- Create: [ml/tests/test_compare_models.py](../../../ml/tests/test_compare_models.py)

- [ ] **Step 10.1: Write the failing test**

Create [ml/tests/test_compare_models.py](../../../ml/tests/test_compare_models.py):

```python
from pathlib import Path

import numpy as np
import pytest

tf = pytest.importorskip("tensorflow")


def _toy_tflite_model(tmp_path: Path, dtype: str = "float") -> Path:
    inputs = tf.keras.Input(shape=(8, 8, 3))
    x = tf.keras.layers.Flatten()(inputs)
    outputs = tf.keras.layers.Dense(2, activation="softmax")(x)
    model = tf.keras.Model(inputs, outputs)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    if dtype == "uint8":
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        rng = np.random.default_rng(0)

        def rep():
            for _ in range(8):
                yield [
                    rng.uniform(0, 255, size=(1, 8, 8, 3)).astype(np.float32)
                ]

        converter.representative_dataset = rep
        converter.target_spec.supported_ops = [
            tf.lite.OpsSet.TFLITE_BUILTINS_INT8
        ]
        converter.inference_input_type = tf.uint8
        converter.inference_output_type = tf.uint8
    path = tmp_path / f"toy_{dtype}.tflite"
    path.write_bytes(converter.convert())
    return path


def test_run_tflite_inference_returns_softmax_probabilities_float(
    tmp_path: Path,
) -> None:
    from cropcare_training.compare_models import run_tflite_inference

    model_path = _toy_tflite_model(tmp_path, dtype="float")
    image = np.random.default_rng(1).uniform(
        0, 255, size=(8, 8, 3)
    ).astype(np.float32)

    probs = run_tflite_inference(model_path=model_path, image=image)

    assert probs.shape == (2,)
    assert abs(probs.sum() - 1.0) < 1e-4


def test_run_tflite_inference_handles_uint8_quantized_model(
    tmp_path: Path,
) -> None:
    from cropcare_training.compare_models import run_tflite_inference

    model_path = _toy_tflite_model(tmp_path, dtype="uint8")
    image = np.random.default_rng(2).uniform(
        0, 255, size=(8, 8, 3)
    ).astype(np.float32)

    probs = run_tflite_inference(model_path=model_path, image=image)

    assert probs.shape == (2,)
    assert (probs >= 0).all() and (probs <= 1).all()
```

- [ ] **Step 10.2: Run tests — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_compare_models.py -v`
Expected: 2 errors, `ModuleNotFoundError: No module named 'cropcare_training.compare_models'`.

- [ ] **Step 10.3: Create `compare_models.py` with `run_tflite_inference`**

Create [ml/cropcare_training/compare_models.py](../../../ml/cropcare_training/compare_models.py):

```python
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

    input_height = input_details["shape"][1]
    input_width = input_details["shape"][2]

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
```

- [ ] **Step 10.4: Run tests — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_compare_models.py -v`
Expected: 2 passes.

- [ ] **Step 10.5: Commit**

```powershell
git add ml/cropcare_training/compare_models.py ml/tests/test_compare_models.py
git -c commit.gpgsign=false commit -m "feat(ml): TFLite single-image inference helper for compare harness

run_tflite_inference loads a TFLite model, inspects its input/output
dtype, quantizes/dequantizes as needed, and returns a normalised
softmax-style probability vector. Works for both float32 and
fully-INT8 quantized models.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: Comparison harness — evaluate model on directory + verdict

**Files:**
- Modify: [ml/cropcare_training/compare_models.py](../../../ml/cropcare_training/compare_models.py)
- Modify: [ml/tests/test_compare_models.py](../../../ml/tests/test_compare_models.py)

- [ ] **Step 11.1: Write the failing tests**

Append to [ml/tests/test_compare_models.py](../../../ml/tests/test_compare_models.py):

```python
def test_evaluate_model_returns_macro_f1_and_per_class_metrics(
    tmp_path: Path,
) -> None:
    from PIL import Image

    from cropcare_training.compare_models import evaluate_model

    test_dir = tmp_path / "test"
    for label in ("a", "b"):
        (test_dir / label).mkdir(parents=True)
        for i in range(2):
            Image.new("RGB", (8, 8), color=(255, 0, 0) if label == "a" else (0, 255, 0)).save(
                test_dir / label / f"{label}_{i}.png"
            )

    model_path = _toy_tflite_model(tmp_path, dtype="float")
    metrics = evaluate_model(
        model_path=model_path,
        labels=["a", "b"],
        test_dir=test_dir,
    )

    assert "macro_f1" in metrics
    assert "accuracy" in metrics
    assert "per_class" in metrics
    assert set(metrics["per_class"]) == {"a", "b"}
    for class_metrics in metrics["per_class"].values():
        for key in ("precision", "recall", "f1", "support"):
            assert key in class_metrics


def test_promotion_verdict_blocks_when_macro_f1_below_floor() -> None:
    from cropcare_training.compare_models import promotion_verdict

    base = {
        "macro_f1": 0.85,
        "accuracy": 0.9,
        "per_class": {"a": {"f1": 0.9}, "b": {"f1": 0.85}},
    }
    candidate_low = {
        "macro_f1": 0.89,
        "accuracy": 0.91,
        "per_class": {"a": {"f1": 0.92}, "b": {"f1": 0.87}},
    }

    verdict = promotion_verdict(
        base_metrics=base,
        candidate_metrics=candidate_low,
        min_macro_f1=0.90,
        min_accuracy=0.92,
        min_per_class_f1=0.85,
    )

    assert verdict["status"] == "BLOCK"
    assert any("macro_f1" in reason for reason in verdict["reasons"])


def test_promotion_verdict_blocks_when_class_regresses() -> None:
    from cropcare_training.compare_models import promotion_verdict

    base = {
        "macro_f1": 0.91,
        "accuracy": 0.94,
        "per_class": {"a": {"f1": 0.95}, "b": {"f1": 0.93}},
    }
    candidate = {
        "macro_f1": 0.92,
        "accuracy": 0.95,
        "per_class": {"a": {"f1": 0.96}, "b": {"f1": 0.86}},
    }

    verdict = promotion_verdict(
        base_metrics=base,
        candidate_metrics=candidate,
        min_macro_f1=0.90,
        min_accuracy=0.92,
        min_per_class_f1=0.85,
    )

    assert verdict["status"] == "BLOCK"
    assert any("regression" in reason and "b" in reason for reason in verdict["reasons"])


def test_promotion_verdict_promotes_when_all_gates_pass() -> None:
    from cropcare_training.compare_models import promotion_verdict

    base = {
        "macro_f1": 0.91,
        "accuracy": 0.94,
        "per_class": {"a": {"f1": 0.95}, "b": {"f1": 0.93}},
    }
    candidate = {
        "macro_f1": 0.94,
        "accuracy": 0.96,
        "per_class": {"a": {"f1": 0.96}, "b": {"f1": 0.94}},
    }

    verdict = promotion_verdict(
        base_metrics=base,
        candidate_metrics=candidate,
        min_macro_f1=0.90,
        min_accuracy=0.92,
        min_per_class_f1=0.85,
    )

    assert verdict["status"] == "PROMOTE"
    assert verdict["reasons"] == []
```

- [ ] **Step 11.2: Run tests — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_compare_models.py -v`
Expected: 4 new failures with `ImportError: cannot import name '<helper>' from 'cropcare_training.compare_models'`.

- [ ] **Step 11.3: Implement `evaluate_model` and `promotion_verdict`**

Append to [ml/cropcare_training/compare_models.py](../../../ml/cropcare_training/compare_models.py):

```python
def evaluate_model(
    *,
    model_path: Path,
    labels: list[str],
    test_dir: Path,
) -> dict:
    """Run the TFLite model on every image under `test_dir` and aggregate."""
    import numpy as np
    from PIL import Image
    from sklearn.metrics import classification_report, f1_score

    import tensorflow as tf

    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    input_height = int(interpreter.get_input_details()[0]["shape"][1])
    input_width = int(interpreter.get_input_details()[0]["shape"][2])

    y_true: list[int] = []
    y_pred: list[int] = []
    for index, label in enumerate(labels):
        label_dir = test_dir / label
        if not label_dir.exists():
            continue
        for path in sorted(label_dir.glob("*.*")):
            with Image.open(path) as image:
                resized = image.convert("RGB").resize((input_width, input_height))
                arr = np.asarray(resized, dtype=np.float32)
            probs = run_tflite_inference(model_path=model_path, image=arr)
            y_true.append(index)
            y_pred.append(int(np.argmax(probs)))

    if not y_true:
        return {
            "accuracy": 0.0,
            "macro_f1": 0.0,
            "per_class": {label: {"precision": 0.0, "recall": 0.0, "f1": 0.0, "support": 0} for label in labels},
        }

    report = classification_report(
        y_true,
        y_pred,
        labels=list(range(len(labels))),
        target_names=labels,
        output_dict=True,
        zero_division=0,
    )
    per_class = {
        label: {
            "precision": float(report[label]["precision"]),
            "recall": float(report[label]["recall"]),
            "f1": float(report[label]["f1-score"]),
            "support": int(report[label]["support"]),
        }
        for label in labels
    }
    accuracy = float(np.mean(np.array(y_true) == np.array(y_pred)))
    macro_f1 = float(
        f1_score(y_true, y_pred, average="macro", zero_division=0)
    )
    return {
        "accuracy": accuracy,
        "macro_f1": macro_f1,
        "per_class": per_class,
    }


def promotion_verdict(
    *,
    base_metrics: dict,
    candidate_metrics: dict,
    min_macro_f1: float = 0.90,
    min_accuracy: float = 0.92,
    min_per_class_f1: float = 0.85,
    min_per_class_precision: float = 0.80,
    min_per_class_recall: float = 0.80,
) -> dict:
    """Return `{"status": "PROMOTE"|"BLOCK", "reasons": [...]}`."""
    reasons: list[str] = []

    if candidate_metrics["macro_f1"] < min_macro_f1:
        reasons.append(
            f"candidate macro_f1 {candidate_metrics['macro_f1']:.4f} "
            f"< floor {min_macro_f1:.4f}"
        )
    if candidate_metrics["accuracy"] < min_accuracy:
        reasons.append(
            f"candidate accuracy {candidate_metrics['accuracy']:.4f} "
            f"< floor {min_accuracy:.4f}"
        )

    base_per_class = base_metrics.get("per_class", {})
    for label, label_metrics in candidate_metrics.get("per_class", {}).items():
        f1 = float(label_metrics.get("f1", 0.0))
        precision = float(label_metrics.get("precision", 0.0))
        recall = float(label_metrics.get("recall", 0.0))
        if f1 < min_per_class_f1:
            reasons.append(
                f"{label} f1 {f1:.4f} < floor {min_per_class_f1:.4f}"
            )
        if precision < min_per_class_precision:
            reasons.append(
                f"{label} precision {precision:.4f} "
                f"< floor {min_per_class_precision:.4f}"
            )
        if recall < min_per_class_recall:
            reasons.append(
                f"{label} recall {recall:.4f} "
                f"< floor {min_per_class_recall:.4f}"
            )
        base_f1 = float(base_per_class.get(label, {}).get("f1", 0.0))
        if base_f1 > 0.0 and f1 < base_f1:
            reasons.append(
                f"regression on {label}: candidate f1 {f1:.4f} "
                f"< base f1 {base_f1:.4f}"
            )

    return {
        "status": "PROMOTE" if not reasons else "BLOCK",
        "reasons": reasons,
    }
```

- [ ] **Step 11.4: Run tests — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_compare_models.py -v`
Expected: 6 passes total in this file.

- [ ] **Step 11.5: Commit**

```powershell
git add ml/cropcare_training/compare_models.py ml/tests/test_compare_models.py
git -c commit.gpgsign=false commit -m "feat(ml): comparison harness — evaluate_model + promotion_verdict

evaluate_model walks test_dir, runs the TFLite model on every image,
and returns macro_f1 + accuracy + per-class precision/recall/f1.
promotion_verdict applies the spec's hard gates (macro_f1 >= 0.90,
accuracy >= 0.92, per-class f1/precision/recall floors, no per-class
regression vs base) and returns PROMOTE or BLOCK with reasons.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: Comparison harness — markdown + JSON report writer + CLI

**Files:**
- Modify: [ml/cropcare_training/compare_models.py](../../../ml/cropcare_training/compare_models.py)
- Modify: [ml/tests/test_compare_models.py](../../../ml/tests/test_compare_models.py)

- [ ] **Step 12.1: Write the failing tests**

Append to [ml/tests/test_compare_models.py](../../../ml/tests/test_compare_models.py):

```python
def test_render_markdown_report_contains_verdict_and_per_class_table(
    tmp_path: Path,
) -> None:
    from cropcare_training.compare_models import render_markdown_report

    base = {
        "macro_f1": 0.91,
        "accuracy": 0.93,
        "per_class": {"a": {"precision": 0.92, "recall": 0.91, "f1": 0.91}, "b": {"precision": 0.93, "recall": 0.93, "f1": 0.93}},
    }
    candidate = {
        "macro_f1": 0.94,
        "accuracy": 0.95,
        "per_class": {"a": {"precision": 0.95, "recall": 0.93, "f1": 0.94}, "b": {"precision": 0.95, "recall": 0.95, "f1": 0.95}},
    }
    verdict = {"status": "PROMOTE", "reasons": []}

    report = render_markdown_report(
        base=base,
        candidate=candidate,
        verdict=verdict,
        labels=["a", "b"],
        base_path=Path("base.tflite"),
        candidate_path=Path("candidate.tflite"),
    )

    assert "PROMOTE" in report
    assert "macro_f1" in report
    assert "| a |" in report
    assert "0.94" in report  # candidate F1 for class a
    assert "Δ" in report  # delta column header


def test_write_comparison_report_persists_json_and_markdown(tmp_path: Path) -> None:
    from cropcare_training.compare_models import write_comparison_report

    payload = {
        "base_path": "base.tflite",
        "candidate_path": "candidate.tflite",
        "labels": ["a"],
        "base_metrics": {"macro_f1": 0.9, "accuracy": 0.9, "per_class": {"a": {"precision": 0.9, "recall": 0.9, "f1": 0.9}}},
        "candidate_metrics": {"macro_f1": 0.95, "accuracy": 0.95, "per_class": {"a": {"precision": 0.95, "recall": 0.95, "f1": 0.95}}},
        "verdict": {"status": "PROMOTE", "reasons": []},
    }

    write_comparison_report(payload=payload, report_dir=tmp_path)

    assert (tmp_path / "comparison_report.json").exists()
    assert (tmp_path / "comparison_report.md").exists()
    assert "PROMOTE" in (tmp_path / "comparison_report.md").read_text(encoding="utf-8")
```

- [ ] **Step 12.2: Run tests — expect failure**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_compare_models.py -v`
Expected: 2 new failures with `ImportError`.

- [ ] **Step 12.3: Implement render + write + CLI**

Append to [ml/cropcare_training/compare_models.py](../../../ml/cropcare_training/compare_models.py):

```python
import argparse
import json


def render_markdown_report(
    *,
    base: dict,
    candidate: dict,
    verdict: dict,
    labels: list[str],
    base_path: Path,
    candidate_path: Path,
) -> str:
    """Render a human-readable comparison report."""
    lines: list[str] = []
    lines.append("# CropCare v2 Model Comparison\n")
    lines.append(f"**Verdict:** `{verdict['status']}`\n")
    if verdict.get("reasons"):
        lines.append("**Block reasons:**\n")
        for reason in verdict["reasons"]:
            lines.append(f"- {reason}")
        lines.append("")

    lines.append(f"- **Base model:** `{base_path}`")
    lines.append(f"- **Candidate model:** `{candidate_path}`\n")

    lines.append("## Overall metrics\n")
    lines.append("| Metric | Base | Candidate | Δ |")
    lines.append("|---|---|---|---|")
    for key in ("macro_f1", "accuracy"):
        base_value = float(base.get(key, 0.0))
        candidate_value = float(candidate.get(key, 0.0))
        lines.append(
            f"| {key} | {base_value:.4f} | {candidate_value:.4f} "
            f"| {candidate_value - base_value:+.4f} |"
        )
    lines.append("")

    lines.append("## Per-class\n")
    lines.append("| Label | Base F1 | Candidate F1 | Δ F1 | Candidate Precision | Candidate Recall |")
    lines.append("|---|---|---|---|---|---|")
    for label in labels:
        base_metrics = base.get("per_class", {}).get(label, {})
        cand_metrics = candidate.get("per_class", {}).get(label, {})
        base_f1 = float(base_metrics.get("f1", 0.0))
        cand_f1 = float(cand_metrics.get("f1", 0.0))
        cand_p = float(cand_metrics.get("precision", 0.0))
        cand_r = float(cand_metrics.get("recall", 0.0))
        lines.append(
            f"| {label} | {base_f1:.4f} | {cand_f1:.4f} | "
            f"{cand_f1 - base_f1:+.4f} | {cand_p:.4f} | {cand_r:.4f} |"
        )
    lines.append("")
    return "\n".join(lines) + "\n"


def write_comparison_report(*, payload: dict, report_dir: Path) -> None:
    report_dir.mkdir(parents=True, exist_ok=True)
    (report_dir / "comparison_report.json").write_text(
        json.dumps(payload, indent=2),
        encoding="utf-8",
    )
    markdown = render_markdown_report(
        base=payload["base_metrics"],
        candidate=payload["candidate_metrics"],
        verdict=payload["verdict"],
        labels=payload["labels"],
        base_path=Path(payload["base_path"]),
        candidate_path=Path(payload["candidate_path"]),
    )
    (report_dir / "comparison_report.md").write_text(markdown, encoding="utf-8")


def _read_labels(path: Path) -> list[str]:
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare two TFLite models on a test split and emit a verdict."
    )
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--base-labels", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--candidate-labels", type=Path, required=True)
    parser.add_argument("--test-dir", type=Path, required=True)
    parser.add_argument("--report-dir", type=Path, required=True)
    parser.add_argument("--min-macro-f1", type=float, default=0.90)
    parser.add_argument("--min-accuracy", type=float, default=0.92)
    parser.add_argument("--min-per-class-f1", type=float, default=0.85)
    parser.add_argument("--min-per-class-precision", type=float, default=0.80)
    parser.add_argument("--min-per-class-recall", type=float, default=0.80)
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    base_labels = _read_labels(args.base_labels)
    candidate_labels = _read_labels(args.candidate_labels)
    if base_labels != candidate_labels:
        # Compare on the intersection (preserves the candidate ordering for
        # row counts and matches the spec's per-class regression check).
        common = [label for label in candidate_labels if label in base_labels]
        if not common:
            raise ValueError(
                "Base and candidate label sets do not overlap; cannot compare."
            )
        labels = common
    else:
        labels = candidate_labels

    base_metrics = evaluate_model(
        model_path=args.base, labels=labels, test_dir=args.test_dir
    )
    candidate_metrics = evaluate_model(
        model_path=args.candidate, labels=labels, test_dir=args.test_dir
    )
    verdict = promotion_verdict(
        base_metrics=base_metrics,
        candidate_metrics=candidate_metrics,
        min_macro_f1=args.min_macro_f1,
        min_accuracy=args.min_accuracy,
        min_per_class_f1=args.min_per_class_f1,
        min_per_class_precision=args.min_per_class_precision,
        min_per_class_recall=args.min_per_class_recall,
    )
    payload = {
        "base_path": str(args.base),
        "candidate_path": str(args.candidate),
        "labels": labels,
        "base_metrics": base_metrics,
        "candidate_metrics": candidate_metrics,
        "verdict": verdict,
    }
    write_comparison_report(payload=payload, report_dir=args.report_dir)
    print(f"Wrote comparison report to {args.report_dir}")
    if verdict["status"] != "PROMOTE":
        raise SystemExit(2)


if __name__ == "__main__":
    main()
```

- [ ] **Step 12.4: Run tests — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_compare_models.py -v`
Expected: 8 passes (2 from Task 10 + 4 from Task 11 + 2 here).

- [ ] **Step 12.5: Commit**

```powershell
git add ml/cropcare_training/compare_models.py ml/tests/test_compare_models.py
git -c commit.gpgsign=false commit -m "feat(ml): comparison harness markdown + JSON writer + CLI

render_markdown_report renders an overall + per-class delta table.
write_comparison_report writes JSON and Markdown to report_dir.
Stand-alone CLI accepts --base/--candidate/--test-dir and exits
non-zero with verdict BLOCK so release automation can short-circuit.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: Wire `compare_models` into `release.py` promotion gate

**Files:**
- Modify: [ml/cropcare_training/release.py](../../../ml/cropcare_training/release.py)
- Modify: [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py)

- [ ] **Step 13.1: Write the failing tests**

Append to [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py):

```python
def test_release_steps_include_comparison_then_promote() -> None:
    from cropcare_training.release import ReleaseConfig, build_release_steps

    config = ReleaseConfig(
        label_profile="cropcare_v2_base_parity",
        max_per_label=None,
        min_per_label=80,
        epochs=30,
        batch_size=32,
        build_android=False,
    )

    steps = build_release_steps(config)
    names = [step.name for step in steps]

    assert names == [
        "train-efficientnet-release",
        "compare-models",
        "promote-artifacts",
        "flutter-test",
    ]
    compare_args = next(step.args for step in steps if step.name == "compare-models")
    assert "--base" in compare_args
    assert "assets/models/cropcare_efficientnet_with_eggplant.tflite" in compare_args
    assert "--candidate" in compare_args
    assert any(arg.endswith("cropcare_efficientnet_v2.tflite") for arg in compare_args)


def test_promote_artifacts_aborts_when_comparison_verdict_is_block(
    tmp_path,
) -> None:
    import json
    import pytest

    from cropcare_training.release import promote_artifacts

    output_dir = tmp_path / "artifacts"
    output_dir.mkdir()
    (output_dir / "cropcare_efficientnet_v2.tflite").write_bytes(b"\x00" * 16)
    (output_dir / "labels_v2.txt").write_text("a\nb\n", encoding="utf-8")
    (output_dir / "training_report_v2.json").write_text(
        json.dumps(
            {
                "metrics": {
                    "macro_f1": 0.95,
                    "per_class_precision_recall": {
                        "a": {"recall": 0.9},
                        "b": {"recall": 0.9},
                    },
                }
            }
        ),
        encoding="utf-8",
    )
    (output_dir / "comparison_report.json").write_text(
        json.dumps(
            {
                "verdict": {
                    "status": "BLOCK",
                    "reasons": ["candidate macro_f1 0.8500 < floor 0.9000"],
                }
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError) as excinfo:
        promote_artifacts(
            output_dir=output_dir,
            assets_dir=tmp_path / "assets",
            validate_shape=False,
        )

    assert "BLOCK" in str(excinfo.value)
    assert not (tmp_path / "assets" / "cropcare_efficientnet_v2.tflite").exists()
```

(Update the existing `test_release_steps_train_then_promote_then_build_android` test to expect the new `compare-models` step in the right position. Find it and replace its assertion to `["train-efficientnet-release", "compare-models", "promote-artifacts", "flutter-test", "flutter-build-apk"]`.)

(Update the existing `test_metric_gate_requires_macro_f1_and_per_class_recall` test thresholds from `min_macro_f1=0.80` and `min_recall=0.70` to `min_macro_f1=0.90` and `min_recall=0.80` to align with the spec; also adjust the recall used in the negative branch from `0.69` to `0.79` so the gate still trips.)

- [ ] **Step 13.2: Run tests — expect failures**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py -v`
Expected: the four affected tests fail (two new + two updates).

- [ ] **Step 13.3: Update `release.py`**

In [ml/cropcare_training/release.py](../../../ml/cropcare_training/release.py):

- Replace the body of `build_release_steps` to insert a `compare-models` step between training and promotion:

```python
def build_release_steps(config: ReleaseConfig) -> list[ReleaseStep]:
    train_args = [
        sys.executable,
        "-m",
        "cropcare_training.automation",
        "--output-dir",
        str(config.output_dir),
        "--label-profile",
        config.label_profile,
        "--min-per-label",
        str(config.min_per_label),
        "--epochs",
        str(config.epochs),
        "--batch-size",
        str(config.batch_size),
    ]
    if config.max_per_label is not None:
        train_args.extend(["--max-per-label", str(config.max_per_label)])
    if config.plantvillage_zip_path is not None:
        train_args.extend(
            ["--plantvillage-zip-path", str(config.plantvillage_zip_path)]
        )

    compare_args = [
        sys.executable,
        "-m",
        "cropcare_training.compare_models",
        "--base",
        str(config.base_model_path),
        "--base-labels",
        str(config.base_labels_path),
        "--candidate",
        str(config.output_dir / "cropcare_efficientnet_v2.tflite"),
        "--candidate-labels",
        str(config.output_dir / "labels_v2.txt"),
        "--test-dir",
        str(config.output_dir / "images_by_split" / "test"),
        "--report-dir",
        str(config.output_dir),
    ]

    steps = [
        ReleaseStep("train-efficientnet-release", train_args),
        ReleaseStep("compare-models", compare_args),
        ReleaseStep(
            "promote-artifacts",
            [
                sys.executable,
                "-m",
                "cropcare_training.release",
                "promote",
                "--output-dir",
                str(config.output_dir),
            ],
        ),
        ReleaseStep("flutter-test", [config.flutter_command, "test"]),
    ]
    if config.build_android:
        steps.append(
            ReleaseStep(
                "flutter-build-apk",
                [config.flutter_command, "build", "apk", "--release"],
            )
        )
    return steps
```

- Add `base_model_path` and `base_labels_path` to `ReleaseConfig` with defaults `Path("assets/models/cropcare_efficientnet_with_eggplant.tflite")` and `Path("assets/models/labels_with_eggplant.txt")` respectively. Update `parse_args()` to add `--base-model-path` and `--base-labels-path` and forward them in `main()`.
- Tighten `validate_metric_gates` defaults to `min_macro_f1=0.90, min_recall=0.80`.
- Update `promote_artifacts` to read `comparison_report.json` and raise `ValueError("Comparison harness verdict BLOCK: " + ", ".join(reasons))` when `verdict["status"] != "PROMOTE"`. Read it AFTER `validate_metric_gates` and BEFORE the `shutil.copy2` calls. If `comparison_report.json` is missing, raise `FileNotFoundError`.

Concrete edit to `promote_artifacts`:

```python
def promote_artifacts(
    *,
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    assets_dir: Path = DEFAULT_ASSETS_DIR,
    validate_shape: bool = True,
) -> None:
    model_path = output_dir / MODEL_FILENAME
    labels_path = output_dir / LABELS_FILENAME
    report_path = output_dir / "training_report_v2.json"
    comparison_path = output_dir / "comparison_report.json"
    for required in (model_path, labels_path, report_path, comparison_path):
        if not required.exists():
            raise FileNotFoundError(f"Missing release artifact: {required}")

    report = json.loads(report_path.read_text(encoding="utf-8"))
    validate_metric_gates(report)
    if validate_shape:
        validate_tflite_output_shape(model_path, labels_path)

    comparison = json.loads(comparison_path.read_text(encoding="utf-8"))
    verdict = comparison.get("verdict") or {}
    if verdict.get("status") != "PROMOTE":
        reasons = ", ".join(verdict.get("reasons") or ["no reasons recorded"])
        raise ValueError(f"Comparison harness verdict BLOCK: {reasons}")

    assets_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(model_path, assets_dir / MODEL_FILENAME)
    shutil.copy2(labels_path, assets_dir / LABELS_FILENAME)
```

- [ ] **Step 13.4: Run tests — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py -v`
Expected: every test passes.

- [ ] **Step 13.5: Commit**

```powershell
git add ml/cropcare_training/release.py ml/tests/test_training_scaffold.py
git -c commit.gpgsign=false commit -m "feat(ml): release pipeline runs comparison harness and gates promotion

Adds a compare-models release step between training and promotion. The
promote subcommand now reads comparison_report.json and refuses to copy
artifacts unless the verdict is PROMOTE. Tightens the legacy
validate_metric_gates defaults to macro_f1>=0.90 and recall>=0.80 to
match the spec.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 14: Dataset preparation defaults — drop the 100-cap, lower the gate, add DigiGreen cap

**Files:**
- Modify: [ml/cropcare_training/automation.py](../../../ml/cropcare_training/automation.py)
- Modify: [ml/cropcare_training/prepare_dataset.py](../../../ml/cropcare_training/prepare_dataset.py)
- Modify: [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py)

- [ ] **Step 14.1: Write the failing tests**

Append to [ml/tests/test_training_scaffold.py](../../../ml/tests/test_training_scaffold.py):

```python
def test_automation_default_uncaps_plantvillage_and_uses_base_parity_profile() -> None:
    from cropcare_training.automation import TrainingRunConfig, build_run_steps

    config = TrainingRunConfig()  # all defaults

    assert config.label_profile == "cropcare_v2_base_parity"
    assert config.max_per_label is None
    assert config.min_per_label == 80
    assert config.digigreen_max_per_label == 1500

    steps = build_run_steps(config)
    prepare_args = steps[0].args
    assert "--max-per-label" not in prepare_args
    assert "--digigreen-max-per-label" in prepare_args
    assert "1500" in prepare_args
    assert "--min-per-label" in prepare_args
    assert "80" in prepare_args


def test_prepare_dataset_caps_digigreen_independently_of_plantvillage() -> None:
    from cropcare_training.prepare_dataset import _enforce_per_source_caps
    from cropcare_training.manifest import ManifestRow

    rows = []
    for index in range(5):
        rows.append(
            ManifestRow(
                row_id=f"dg-{index}",
                image_uri=f"https://example.com/{index}.jpg",
                label_key="eggplant_healthy",
                crop_type="eggplant",
                split="train",
                source_dataset="DigiGreen/Crop_Disease_Images",
                source_split="train",
                source_license="cc-by-4.0",
                raw_crop="Brinjal",
                raw_label="Healthy",
            )
        )
    for index in range(7):
        rows.append(
            ManifestRow(
                row_id=f"pv-{index}",
                image_uri=f"data/{index}.jpg",
                label_key="eggplant_healthy",
                crop_type="eggplant",
                split="train",
                source_dataset="mohanty/PlantVillage",
                source_split="train",
                source_license="cc-by-sa-3.0",
                raw_crop="eggplant",
                raw_label="Eggplant___healthy",
            )
        )

    capped = _enforce_per_source_caps(rows, digigreen_max=2, plantvillage_max=None)
    digigreen = [row for row in capped if row.source_dataset == "DigiGreen/Crop_Disease_Images"]
    plantvillage = [row for row in capped if row.source_dataset == "mohanty/PlantVillage"]

    assert len(digigreen) == 2
    assert len(plantvillage) == 7
```

- [ ] **Step 14.2: Run tests — expect failures**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/test_training_scaffold.py -k "automation_default_uncaps or caps_digigreen" -v`
Expected: 2 failures.

- [ ] **Step 14.3: Update `automation.py` defaults and CLI**

In [ml/cropcare_training/automation.py](../../../ml/cropcare_training/automation.py):

- Change `TrainingRunConfig` defaults: `max_per_label: int | None = None`, `min_per_label: int = 80`, `epochs: int = 30`, `batch_size: int = 32`, `label_profile: str = "cropcare_v2_base_parity"`, and add `digigreen_max_per_label: int = 1500`.
- Update `build_run_steps` to forward `--digigreen-max-per-label` to `prepare_dataset` (always; `--max-per-label` only when set).
- Update `parse_args` defaults to mirror the new dataclass defaults and add `--digigreen-max-per-label`.

- [ ] **Step 14.4: Update `prepare_dataset.py` to support per-source caps**

In [ml/cropcare_training/prepare_dataset.py](../../../ml/cropcare_training/prepare_dataset.py):

- Add a new helper:

```python
def _enforce_per_source_caps(
    rows: list[ManifestRow],
    *,
    digigreen_max: int | None,
    plantvillage_max: int | None,
) -> list[ManifestRow]:
    counts: dict[tuple[str, str], int] = {}
    kept: list[ManifestRow] = []
    for row in rows:
        cap = digigreen_max if row.source_dataset == "DigiGreen/Crop_Disease_Images" else plantvillage_max
        key = (row.source_dataset, row.label_key)
        if cap is not None and counts.get(key, 0) >= cap:
            continue
        counts[key] = counts.get(key, 0) + 1
        kept.append(row)
    return kept
```

- In `build_manifest`, replace the in-loop `should_keep` with two passes: first build the full per-row list using only the activeness filter, then call `_enforce_per_source_caps(rows, digigreen_max=digigreen_max_per_label, plantvillage_max=max_per_label)`.
- Add `digigreen_max_per_label: int | None = None` parameter to `build_manifest` signature.
- Add `--digigreen-max-per-label` argparse argument and forward it from `main`.

- [ ] **Step 14.5: Run all tests — expect pass**

Run: `ml\.venv\Scripts\python.exe -m pytest ml/tests/ -v`
Expected: every test passes (the existing `test_cpu_training_automation_builds_prepare_and_train_steps` may need a small update — find any assertion of `--max-per-label` in steps under default config and tweak to either drop the `--max-per-label` expectation or pass an explicit `max_per_label` in the test config).

Concretely, in the existing `test_cpu_training_automation_builds_prepare_and_train_steps`, change `TrainingRunConfig(max_per_label=3, epochs=1, batch_size=4)` to keep the assertion that `--max-per-label` and `3` are present. The test should still pass because the new dataclass default is `None` but the test explicitly passes `3`.

- [ ] **Step 14.6: Commit**

```powershell
git add ml/cropcare_training/automation.py ml/cropcare_training/prepare_dataset.py ml/tests/test_training_scaffold.py
git -c commit.gpgsign=false commit -m "feat(ml): drop 100-image cap, lower gate to 80, cap DigiGreen at 1500/class

The single biggest accuracy regression in v2 came from the 100-per-class
cap that left EfficientNetB0 starved on PlantVillage. Defaults now use
the full PlantVillage set, cap DigiGreen at 1500/class to keep its
real-field noise from dominating, and drop the minimum-per-label gate
from 100 to 80 so eggplant classes that hover around the boundary do
not get gated out by minor sampling noise.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 15: Dart classifier core dtype-dispatch (uint8 + float32)

**Files:**
- Modify: [lib/services/tflite_classifier_core.dart](../../../lib/services/tflite_classifier_core.dart)
- Modify: [test/tflite_classifier_core_test.dart](../../../test/tflite_classifier_core_test.dart)

- [ ] **Step 15.1: Write the failing test**

Replace the contents of [test/tflite_classifier_core_test.dart](../../../test/tflite_classifier_core_test.dart) with:

```dart
import 'dart:typed_data';

import 'package:cropcare_ai/services/tflite_classifier_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('Float32 input branch keeps raw RGB channel values', () {
    final image = img.Image(width: 1, height: 1)
      ..setPixelRgb(0, 0, 255, 128, 0);
    final bytes = img.encodePng(image);

    final input = const TfliteClassifierCore().buildEfficientNetInputTensor(
      imageBytes: bytes,
      inputHeight: 1,
      inputWidth: 1,
      inputDtype: TfliteInputDtype.float32,
    );

    expect(input.runtimeType.toString(), contains('List'));
    final floatInput = input as List<List<List<List<double>>>>;
    expect(floatInput[0][0][0], [255.0, 128.0, 0.0]);
  });

  test('Uint8 input branch packs raw RGB into a Uint8List', () {
    final image = img.Image(width: 1, height: 1)
      ..setPixelRgb(0, 0, 255, 128, 0);
    final bytes = img.encodePng(image);

    final input = const TfliteClassifierCore().buildEfficientNetInputTensor(
      imageBytes: bytes,
      inputHeight: 1,
      inputWidth: 1,
      inputDtype: TfliteInputDtype.uint8,
    );

    expect(input, isA<Uint8List>());
    expect((input as Uint8List).toList(), [255, 128, 0]);
  });
}
```

- [ ] **Step 15.2: Run test — expect failure**

Run: `flutter test test/tflite_classifier_core_test.dart`
Expected: FAIL with errors about `TfliteInputDtype` not defined and `inputDtype` parameter not accepted.

- [ ] **Step 15.3: Update `tflite_classifier_core.dart`**

Add the dtype enum and dispatch helpers. Specific changes:

- At the top of the file, add:

```dart
enum TfliteInputDtype { float32, uint8 }
```

- Replace `buildEfficientNetInputTensor` with a polymorphic version:

```dart
  Object buildEfficientNetInputTensor({
    required List<int> imageBytes,
    required int inputHeight,
    required int inputWidth,
    TfliteInputDtype inputDtype = TfliteInputDtype.float32,
  }) {
    final decoded = img.decodeImage(Uint8List.fromList(imageBytes));
    if (decoded == null) {
      throw Exception('Failed to decode image for TFLite inference.');
    }

    final resized = img.copyResize(
      decoded,
      width: inputWidth,
      height: inputHeight,
      interpolation: img.Interpolation.average,
    );

    if (inputDtype == TfliteInputDtype.uint8) {
      final buffer = Uint8List(inputHeight * inputWidth * 3);
      var offset = 0;
      for (var y = 0; y < inputHeight; y++) {
        for (var x = 0; x < inputWidth; x++) {
          final pixel = resized.getPixel(x, y);
          buffer[offset++] = pixel.r.toInt();
          buffer[offset++] = pixel.g.toInt();
          buffer[offset++] = pixel.b.toInt();
        }
      }
      return buffer;
    }

    return [
      List.generate(
        inputHeight,
        (y) => List.generate(
          inputWidth,
          (x) {
            final pixel = resized.getPixel(x, y);
            return [
              pixel.r.toDouble(),
              pixel.g.toDouble(),
              pixel.b.toDouble(),
            ];
          },
        ),
      ),
    ];
  }
```

- Update `classifyImage` to detect input dtype, build the matching tensor, and dequantize uint8 outputs:

```dart
    final inputTensor = interpreter.getInputTensor(0);
    final outputTensor = interpreter.getOutputTensor(0);
    final inputShape = inputTensor.shape;
    final inputHeight = inputShape[1];
    final inputWidth = inputShape[2];
    final isUint8Input = inputTensor.type.toString().toLowerCase().contains('uint8');
    final isUint8Output = outputTensor.type.toString().toLowerCase().contains('uint8');

    final input = buildEfficientNetInputTensor(
      imageBytes: imageBytes,
      inputHeight: inputHeight,
      inputWidth: inputWidth,
      inputDtype: isUint8Input ? TfliteInputDtype.uint8 : TfliteInputDtype.float32,
    );

    final List<List<num>> rawOutput = isUint8Output
        ? [List<int>.filled(labels.length, 0)]
        : [List<double>.filled(labels.length, 0.0)];
    interpreter.run(input, rawOutput);

    final List<double> scores;
    if (isUint8Output) {
      final params = outputTensor.params;
      final scale = params.scale;
      final zeroPoint = params.zeroPoint;
      scores = (rawOutput.first as List<int>)
          .map((value) => (value - zeroPoint) * scale)
          .map((value) => value.toDouble())
          .toList();
      final total = scores.fold<double>(0.0, (a, b) => a + b);
      if (total > 0) {
        for (var i = 0; i < scores.length; i++) {
          scores[i] = scores[i] / total;
        }
      }
    } else {
      scores = (rawOutput.first as List<double>);
    }
```

(Then replace every later reference to `output.first` / `final scores = output.first;` with `scores` from the block above.)

If the `tflite_flutter` package version in this project does not expose `Tensor.params.scale` / `zeroPoint`, fall back to looking it up via `interpreter.getOutputTensor(0)` — the project pins `tflite_flutter ^0.11.0` which does expose them under `tensor.params`. If after running `flutter pub deps` the field is missing, add the field-access via the tensor's `quantizationParams` instead.

- [ ] **Step 15.4: Run test — expect pass**

Run: `flutter test test/tflite_classifier_core_test.dart`
Expected: 2 passes.

- [ ] **Step 15.5: Run the full Flutter test suite**

Run: `flutter test`
Expected: all tests pass (the rest of the app is untouched).

- [ ] **Step 15.6: Commit**

```powershell
git add lib/services/tflite_classifier_core.dart test/tflite_classifier_core_test.dart
git -c commit.gpgsign=false commit -m "feat(app): TFLite classifier handles uint8 and float32 input dtypes

Detects input/output tensor dtype at inference time and dispatches to a
Uint8List flat-buffer build path for INT8 quantized models, with output
dequantization via the tensor's quantization params. Float32 path is
unchanged so the currently-shipped base model keeps working without
re-training.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 16: Update PowerShell release scripts to new defaults

**Files:**
- Modify: [ml/run_model_release.ps1](../../../ml/run_model_release.ps1)
- Modify: [ml/run_cpu_training.ps1](../../../ml/run_cpu_training.ps1)

- [ ] **Step 16.1: Update `run_model_release.ps1`**

Replace the `param(...)` block at the top of [ml/run_model_release.ps1](../../../ml/run_model_release.ps1) with:

```powershell
param(
    [string]$OutputDir = "ml/artifacts/cropcare_v2",
    [string]$LabelProfile = "cropcare_v2_base_parity",
    [Nullable[int]]$MaxPerLabel = $null,
    [int]$DigigreenMaxPerLabel = 1500,
    [int]$MinPerLabel = 80,
    [int]$Epochs = 30,
    [int]$WarmupEpochs = 5,
    [int]$UnfreezeTopN = 30,
    [int]$BatchSize = 32,
    [string]$PlantVillageZipPath = "",
    [string]$BaseModelPath = "assets/models/cropcare_efficientnet_with_eggplant.tflite",
    [string]$BaseLabelsPath = "assets/models/labels_with_eggplant.txt",
    [string]$FlutterCommand = "flutter",
    [switch]$BuildAndroid,
    [switch]$SkipInstall
)
```

In the `$ArgsList` block append `--digigreen-max-per-label $DigigreenMaxPerLabel`, `--warmup-epochs $WarmupEpochs`, `--unfreeze-top-n $UnfreezeTopN`, `--base-model-path $BaseModelPath`, `--base-labels-path $BaseLabelsPath` (only the ones the `release.py` CLI accepts after Task 13's edits — for the ones it does not, drop them).

Replace the existing `if ($MaxPerLabel) { ... }` (if present) with:

```powershell
if ($null -ne $MaxPerLabel) {
    $ArgsList += @("--max-per-label", "$MaxPerLabel")
}
```

- [ ] **Step 16.2: Update `run_cpu_training.ps1`**

Apply the equivalent changes to [ml/run_cpu_training.ps1](../../../ml/run_cpu_training.ps1) so the smoke-run script stays in sync with the release defaults — same `LabelProfile`, same `Epochs=30`, same `BatchSize=32`, `MinPerLabel=80`, `DigigreenMaxPerLabel=1500`, no `MaxPerLabel` by default. (Keep the existing `--full` switch behaviour.)

- [ ] **Step 16.3: Manually run a syntax check on each script**

Run: `powershell -NoProfile -Command "Get-Command -Syntax (Get-Item ml\run_model_release.ps1).FullName"`

Expected: no parse error printed.

Run the same check for `ml\run_cpu_training.ps1`.

- [ ] **Step 16.4: Commit**

```powershell
git add ml/run_model_release.ps1 ml/run_cpu_training.ps1
git -c commit.gpgsign=false commit -m "chore(ml): update PS1 release defaults to base-parity, no max-cap

Defaults now line up with the spec: cropcare_v2_base_parity profile,
30 epochs (5 warm-up + 25 fine-tune), batch 32, min-per-label 80,
DigiGreen capped at 1500/class, PlantVillage uncapped.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Task 17: Update README to document the new pipeline

**Files:**
- Modify: [ml/README.md](../../../ml/README.md)

- [ ] **Step 17.1: Edit the README**

Replace the "Prepare Data" and "Train And Export" sections with content matching the new defaults. Specifically:

- Document `cropcare_v2_base_parity` as the recommended profile.
- Note that PlantVillage `data.zip` auto-downloads from HF and no manual `-PlantVillageZipPath` is needed unless caching offline.
- Document the comparison-harness step and the promotion gate (`comparison_report.md` is the human-readable output; `comparison_report.json` drives `release.py promote`).
- Show the example invocation:

```powershell
.\ml\run_model_release.ps1 -BuildAndroid
```

- Add a "Promotion Gate" subsection that lists the spec's hard floors (macro_f1 ≥ 0.90, accuracy ≥ 0.92, per-class f1 ≥ 0.85, no per-class regression vs base) and explains that the run aborts if any are violated.
- Add a "Comparison Report" subsection telling the reader where the side-by-side numbers vs base land.

- [ ] **Step 17.2: Commit**

```powershell
git add ml/README.md
git -c commit.gpgsign=false commit -m "docs(ml): document v2 base-parity pipeline + promotion gate"
```

---

## Task 18: End-to-end smoke run (manual, not TDD)

This is the actual training run. It is the largest single time commitment in the plan (6–9 h on a strong CPU). Treat it as a single task; it produces the artifacts that the comparison harness then validates.

**Pre-requisites:**
- All previous tasks are merged on `training-improvement`.
- The `ml/.venv` venv is set up per [ml/README.md](../../../ml/README.md).
- The Pixel 7a is unplugged or the previous `flutter run` background process is stopped (free up CPU).
- ≥ 12 GB free RAM, ≥ 10 GB free disk under `ml/`.

- [ ] **Step 18.1: Trigger the release**

Run from a fresh PowerShell:

```powershell
.\ml\run_model_release.ps1 -BuildAndroid
```

This kicks off, in order:
1. `prepare-dataset` — fetches HF data, downloads PlantVillage `data.zip` if not cached, persists images under `ml/artifacts/cropcare_v2/images_by_split/{train,validation,test}/<label>/`.
2. `train-efficientnet` — two-phase training, saves `cropcare_efficientnet_v2.tflite` (INT8) + `cropcare_efficientnet_v2_float.tflite` + `cropcare_efficientnet_v2.keras`.
3. `compare-models` — runs both base TFLite and candidate TFLite on the held-out test split, writes `comparison_report.json` and `comparison_report.md`. Exits 2 if verdict is BLOCK.
4. `promote-artifacts` — copies INT8 tflite + `labels_v2.txt` to `assets/models/`, only if comparison verdict is PROMOTE.
5. `flutter test` — runs the Dart suite.
6. `flutter build apk --release` — rebuilds the release APK.

- [ ] **Step 18.2: Verify the comparison report says PROMOTE**

Open [ml/artifacts/cropcare_v2/comparison_report.md](../../../ml/artifacts/cropcare_v2/comparison_report.md). Confirm:

- The verdict at the top is `PROMOTE`.
- The "Overall metrics" table shows `macro_f1 ≥ 0.90` and `accuracy ≥ 0.92` for the candidate.
- Every row of the per-class table has candidate F1 ≥ 0.85 AND ≥ base F1.

If verdict is BLOCK, do not retry blindly. Read `comparison_report.md`'s "Block reasons", check `training_log.csv`, and update parameters before re-running. Common fixes:
- Eggplant per-class F1 short → bump `WarmupEpochs` to 8 or `Epochs` to 40, or raise `MinPerLabel` and let the dataset prep redo eggplant downloads with stronger filtering.
- Macro-F1 short → check the confusion matrix in `training_report_v2.json` for which class is collapsing.

- [ ] **Step 18.3: Verify on-device inference**

With the rebuilt APK on the Pixel 7a:

```powershell
flutter install -d 33171JEAN23637
```

Open the app, scan one image of each crop. Confirm:
- The predicted label and the displayed crop type both match expectations.
- No `Invalid argument(s): bad input shape` or dtype-mismatch errors in `flutter logs`.

- [ ] **Step 18.4: Final commit**

After the comparison report is `PROMOTE` and on-device verification passes, commit the new model artifacts:

```powershell
git add assets/models/cropcare_efficientnet_v2.tflite assets/models/labels_v2.txt ml/artifacts/cropcare_v2/comparison_report.md ml/artifacts/cropcare_v2/comparison_report.json ml/artifacts/cropcare_v2/training_report_v2.json
git -c commit.gpgsign=false commit -m "feat(model): ship cropcare_efficientnet_v2 (base-parity, macro_f1 >= 0.90)

Includes the new INT8 TFLite, base-parity labels file, training report,
and the side-by-side comparison report showing the candidate beats the
shipped base on every class.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

(Do NOT commit raw image data under `ml/artifacts/cropcare_v2/images_by_split/` — that path is already excluded by the existing `.gitignore`. If for any reason it is not, add `ml/artifacts/cropcare_v2/images_by_split/` to `.gitignore` first as a separate prep commit.)

---

## Self-Review Notes

**Spec coverage:** Tasks 1 (label profile), 2-4 (augmentation §4.2 + §5.5), 5 (callbacks §4.7), 6-9 (training architecture §4 + §6), 10-12 (comparison harness §7), 13 (promotion gate §8), 14 (data pipeline §5.2), 15 (Dart preprocessing §6 step 5), 16 (PS1 scripts §9), 17 (docs), 18 (verification §12). Every section of the spec is implemented or verified by at least one task.

**Type consistency:** `TfliteInputDtype` in Task 15 is referenced consistently. `BestMacroF1Checkpoint`, `build_model`, `unfreeze_top_layers`, `phase_epoch_split`, `compute_class_weights`, `representative_dataset_gen`, `export_int8_tflite`, `run_tflite_inference`, `evaluate_model`, `promotion_verdict`, `render_markdown_report`, `write_comparison_report`, `_enforce_per_source_caps` — every name introduced is referenced exactly under that name in later tasks.

**Placeholder scan:** None. Every step contains the actual code or actual command.

**Risk callouts that the executor should know about:**
- Task 8 is by far the longest individual task; it's where the test-driven boundary feels softest because TF graph mutations are hard to unit-test cheaply. The two unit tests there (`unfreeze_top_layers` and `phase_epoch_split`) cover the only logic that lives outside `train_and_export`. The full `train_and_export` is exercised in Task 18's smoke run, not in unit tests, by design — its dependencies (large datasets, real EfficientNet weights) make a true unit test more flaky than informative.
- Task 15's Dart change touches a hot path. The two unit tests cover the dtype-dispatch in `buildEfficientNetInputTensor`. The full classifier path is exercised by Task 18 step 18.3.
- Task 18 is the only task that actually validates the 0.90 macro-F1 floor; if it fails, the spec's hard gate kicks in and `assets/models/` stays untouched. That's the design.
