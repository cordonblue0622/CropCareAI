# CropCare v2 Model Upgrade — Design

**Status:** approved (brainstorming) → implementation complete → revised mid-implementation to multi-model routing (see §13).
**Date:** 2026-05-06
**Owner:** Allain Legaspi
**Hardware target:** Local CPU (no GPU)
**Approach:** "Disciplined transfer-learning upgrade" (Approach 2 from brainstorming) **+ multi-model routing for eggplant** (added 2026-05-06 after dataset audit).

## 1. Goal

Replace the currently shipped `assets/models/cropcare_efficientnet_with_eggplant.tflite`
with a retrained EfficientNetB0 classifier whose validation macro-F1 is
**≥ 0.90 across all 16 base-parity labels** AND that does not regress on any
individual class versus the existing base model. Ship a side-by-side
comparison report alongside the new model so the delta vs. base is auditable.

## 2. Non-goals

- Adding new crops or new label keys beyond the 16 already in
  `assets/models/labels_with_eggplant.txt`.
- Switching backbone families (no Vision Transformer, no MobileNet swap).
- On-device fine-tuning, federated learning, or active learning loops.
- Re-architecting the existing `ml/cropcare_training/` package boundaries —
  we extend it, we don't rewrite it.
- Improvements to the FastAPI backend's TFLite harness beyond what is needed
  to consume the new label set.

## 3. Success criteria

A run is considered successful and may promote into `assets/models/` only if
**every** condition below is met against the held-out test split:

| Metric | Threshold |
|---|---|
| Overall macro-F1 (16 classes) | ≥ 0.90 |
| Overall accuracy | ≥ 0.92 |
| Per-class F1 (every class) | ≥ 0.85 AND ≥ base model's F1 for that class |
| Per-class recall (every class) | ≥ 0.80 |
| Per-class precision (every class) | ≥ 0.80 |
| TFLite output tensor width | == len(labels) |

A separate **soft** target — final shipped `.tflite` ≤ 7 MB — applies. If
INT8 post-training quantization (§6) loses more than 0.02 macro-F1
relative to the float32 candidate, we ship the float32 model (~16 MB)
even though it exceeds the soft size target. Size never blocks promotion;
accuracy and per-class regression checks do.

If any **hard** condition fails, automation aborts before promotion. The
existing `cropcare_efficientnet_with_eggplant.tflite` remains the shipped
artifact.

## 4. Architecture

### 4.1 Backbone

`tf.keras.applications.EfficientNetB0(include_top=False, weights="imagenet")`.
Same family as today; chosen for CPU-friendly inference on the Pixel 7a.
Input shape `(224, 224, 3)`, raw RGB pixel values in `[0, 255]` (EfficientNet's
internal preprocessing handles normalization — Dart side must NOT divide by
255 before inference, matching the existing v2 contract documented in
[ml/README.md](../../../ml/README.md)).

### 4.2 Augmentation block

Implemented as Keras layers placed immediately after the input so they bake
into the saved model and apply identically at training time and inference
time (when `training=True` is passed during fit, but **not** at TFLite
inference — Keras `RandomFoo` layers are no-ops when `training=False`,
which TFLite conversion preserves):

- `RandomFlip("horizontal")`
- `RandomRotation(factor=0.08)` (~±15°)
- `RandomZoom(height_factor=0.15, width_factor=0.15)`
- `RandomTranslation(height_factor=0.06, width_factor=0.06)`
- `RandomContrast(factor=0.15)`
- `RandomBrightness(factor=0.15)`

MixUp (α=0.2) is applied at the data-pipeline level (not as a layer) during
the fine-tune phase only. Implemented via a `tf.data.Dataset.map` that takes
two batches and produces convex combinations on both images and one-hot
labels. Disabled in warm-up.

### 4.3 Head

`GlobalAveragePooling2D → Dropout(0.3) → Dense(num_classes, activation="softmax", name="cropcare_label")`.

### 4.4 Loss & optimizer

- Loss: `CategoricalCrossentropy(label_smoothing=0.1)` for both phases.
- Warm-up phase optimizer: `Adam(learning_rate=1e-3)`.
- Fine-tune phase optimizer: `AdamW(learning_rate=schedule, weight_decay=1e-5)`
  where `schedule` is `tf.keras.optimizers.schedules.CosineDecay(initial_learning_rate=1e-4, decay_steps=fine_tune_steps, alpha=0.01)` (decays to 1e-6).

### 4.5 Two-phase training

**Phase 1 — Warm-up (5 epochs, frozen base)**
- `base_model.trainable = False`
- Train head only.
- Saves `head_warmup.weights.h5` to `output_dir/checkpoints/`.

**Phase 2 — Fine-tune (≤ 25 epochs, partial unfreeze, early-stopped)**
- Unfreeze the **last 30 layers** of EfficientNetB0 only (keeps early
  generic features frozen, adapts mid/high-level features to crop disease).
  BatchNormalization layers stay frozen (`layer.trainable = False`)
  regardless of unfreeze depth, to avoid the well-known fine-tuning batch
  statistics drift on small datasets.
- Resumes from warm-up weights.
- Early stops on `val_loss` patience=5, restoring best weights.

### 4.6 Class weighting

Compute inverse-frequency `class_weight` dict over the train split and pass
it to both `model.fit` calls. Eggplant labels are expected to be
under-represented relative to tomato; this prevents loss collapse onto the
majority class.

### 4.7 Callbacks (both phases)

- `EarlyStopping(monitor="val_loss", patience=5, restore_best_weights=True)`
- `ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=2, min_lr=1e-7)`
  (warm-up phase only; fine-tune uses the cosine schedule directly)
- `BestMacroF1Checkpoint` — custom callback that runs `f1_score(y_true, y_pred, average="macro")` on the validation set at end-of-epoch and saves `best.weights.h5` whenever it improves.
- `CSVLogger` writing per-epoch metrics to `output_dir/training_log.csv`.

## 5. Data pipeline

### 5.1 Source mix

Unchanged from today: PlantVillage (`mohanty/PlantVillage`) + DigiGreen
(`DigiGreen/Crop_Disease_Images`). Both are fetched via the existing
[hf_assets.py](../../../ml/cropcare_training/hf_assets.py) and
[prepare_dataset.py](../../../ml/cropcare_training/prepare_dataset.py)
modules — PlantVillage `data.zip` auto-downloads from HF on first run, and
DigiGreen rows stream from HF with per-row HTTP image fetches limited to
mapped + active labels.

### 5.2 Dataset cap changes

The current pipeline caps every label at 100 images, which is the single
biggest factor in v2's collapse. New caps:

| Setting | Old | New |
|---|---|---|
| `--max-per-label` (PlantVillage classes) | 100 | None (use everything) |
| DigiGreen per-class cap | 100 | 1500 |
| Minimum-per-label gate | 100 | 80 (lower so eggplant classes that hover around 100 do not get gated out by minor noise) |

A new `cropcare_v2_base_parity` label profile is added in
[label_profiles.py](../../../ml/cropcare_training/label_profiles.py),
matching the 16 labels in `assets/models/labels_with_eggplant.txt`.

### 5.3 Splits

Stratified 80/10/10 by class, deterministic via the existing
`assign_balanced_splits` SHA-1 bucketing in `prepare_dataset.py`. No code
change required there.

### 5.4 tf.data input

```
ds = image_dataset_from_directory(...)        # decoded uint8 [0,255]
       .cache()                               # cache decoded tensors only
       .shuffle(buffer=2048)
       .map(mixup_pair, num_parallel_calls=AUTOTUNE)   # fine-tune only
       .prefetch(AUTOTUNE)
```

`cache()` is placed after image decoding but before shuffle/augmentation,
so each epoch reuses decoded uint8 tensors but re-randomizes both the
shuffle order and (because augmentation lives inside the model graph
under §4.2) the augmentation perturbations. Total cached size after caps
is ≈ 30k images × 224 × 224 × 3 bytes ≈ 4.5 GB, which fits comfortably in
RAM on the target machine. If a future user has < 12 GB free RAM, fall
back to `.cache(filename="ml/artifacts/.cache")` for disk-backed caching;
this is exposed via a `--cache-mode {memory,disk,off}` CLI flag.

### 5.5 Eggplant-specific handling

Eggplant data comes only from DigiGreen (real-field photos, noisier than
PlantVillage's lab images). To keep eggplant per-class F1 ≥ 0.85:

- **Stronger augmentation** for eggplant only: an extra `RandomZoom(0.25)`
  pass and `RandomCrop` jitter applied via a label-conditional augmentation
  branch in the data pipeline.
- **Class weights** as described in §4.6.
- If after Phase 2 any eggplant per-class F1 still falls below 0.85, the
  promotion gate blocks the run. The comparison report documents which
  classes failed and by how much. **Scope reduction (shipping fewer than
  16 classes) is explicitly out of scope for this design** — a failed run
  surfaces the data quality issue, but the response is a follow-up
  iteration (more eggplant data, stronger augmentation, or a different
  loss), not a silent class drop in this release.

## 6. Export & quantization

After Phase 2 selects the best epoch:

1. Save Keras model as `cropcare_efficientnet_v2.keras`.
2. Convert to **float32 TFLite** at `output_dir/cropcare_efficientnet_v2_float.tflite` (sanity reference; never shipped).
3. Build a **representative dataset generator** that yields ~200 images
   sampled across all classes from the train split.
4. Convert to **INT8 TFLite** with full-integer post-training quantization
   (`tf.lite.Optimize.DEFAULT`,
   `representative_dataset=...`,
   `inference_input_type=tf.uint8`, `inference_output_type=tf.uint8`,
   `target_spec.supported_ops=[tf.lite.OpsSet.TFLITE_BUILTINS_INT8]`),
   writing `cropcare_efficientnet_v2.tflite` (the production artifact).
5. The Dart preprocessing path must handle uint8 input tensors (output of
   INT8 quantization). The existing
   [tflite_classifier_core.dart](../../../lib/services/tflite_classifier_core.dart)
   currently assumes float32 inputs in `[0, 255]`. Implementation will:
   (a) inspect the TFLite input tensor's dtype at load time, (b) for
   uint8, pass raw uint8 RGB bytes (no scaling, no `/255`), (c) for
   float32, keep current behaviour, (d) read the output tensor's dtype
   and dequantize uint8 logits using the per-tensor quantization
   parameters before applying softmax / argmax. This dispatch is verified
   by [test/tflite_classifier_core_test.dart](../../../test/tflite_classifier_core_test.dart)
   exercising both dtypes via fixture models.

## 7. Comparison harness

A new module `ml/cropcare_training/compare_models.py` is added. It:

1. Loads BOTH `assets/models/cropcare_efficientnet_with_eggplant.tflite`
   (base) and the candidate `cropcare_efficientnet_v2.tflite` (new) via the
   tflite_runtime / TF Python bindings.
2. Runs both on the held-out test split (`output_dir/images_by_split/test/`).
3. Computes accuracy, macro-F1, per-class precision/recall/F1, and
   confusion matrices for each.
4. Writes:
   - `output_dir/comparison_report.json` — full structured numbers.
   - `output_dir/comparison_report.md` — human-readable summary with the
     per-class delta table and a verdict (`PROMOTE` / `BLOCK`) based on the
     promotion-gate rules in §3.

The harness is also exposed as a stand-alone CLI:
```
python -m cropcare_training.compare_models \
    --base assets/models/cropcare_efficientnet_with_eggplant.tflite \
    --base-labels assets/models/labels_with_eggplant.txt \
    --candidate ml/artifacts/cropcare_v2/cropcare_efficientnet_v2.tflite \
    --candidate-labels ml/artifacts/cropcare_v2/labels_v2.txt \
    --test-dir ml/artifacts/cropcare_v2/images_by_split/test \
    --report-dir ml/artifacts/cropcare_v2
```

## 8. Promotion gate

Implemented inside [release.py](../../../ml/cropcare_training/release.py).
After training and the comparison harness run, release.py reads
`comparison_report.json`. If the verdict is not `PROMOTE`, it exits non-zero
and `assets/models/` is NOT touched. If `PROMOTE`, it copies:

- `cropcare_efficientnet_v2.tflite` → `assets/models/cropcare_efficientnet_v2.tflite`
- `labels_v2.txt` → `assets/models/labels_v2.txt`

The legacy `cropcare_efficientnet_with_eggplant.tflite` and
`labels_with_eggplant.txt` files are **kept** in `assets/models/` for one
release cycle so we can A/B at runtime if needed. They are not referenced
by the app code, which already points at the v2 filenames in
[app_constants.dart](../../../lib/core/constants/app_constants.dart).

## 9. File-level changes

### New files

- `ml/cropcare_training/augmentation.py` — Keras augmentation block + MixUp data-pipeline transform + eggplant-conditional augmentation branch.
- `ml/cropcare_training/callbacks.py` — `BestMacroF1Checkpoint` custom callback.
- `ml/cropcare_training/compare_models.py` — comparison harness (§7).
- `ml/tests/test_augmentation.py`, `ml/tests/test_callbacks.py`, `ml/tests/test_compare_models.py` — unit tests.
- `docs/superpowers/specs/2026-05-06-cropcare-v2-model-upgrade-design.md` — this file.

### Modified files

- `ml/cropcare_training/train_efficientnet.py` — split into `_warmup_phase` and `_fine_tune_phase` helpers; wire augmentation, class weights, callbacks, INT8 export.
- `ml/cropcare_training/label_profiles.py` — add `cropcare_v2_base_parity` (16 labels matching base) profile.
- `ml/cropcare_training/automation.py` and `release.py` — pass the new label profile, run the comparison harness, enforce the promotion gate.
- `ml/run_model_release.ps1` — default `--LabelProfile` to `cropcare_v2_base_parity`, `--Epochs` to 30 (warm-up 5 + fine-tune ≤ 25), `--BatchSize` to 32; remove `--MaxPerLabel` from the default invocation.
- `ml/run_cpu_training.ps1` — same defaults (it's the smoke variant).
- `lib/services/tflite_classifier_core.dart` — accept uint8 inputs (output of INT8 quantization) in addition to float32. Probe input tensor dtype and dispatch.

### Untouched

The Flutter app code paths beyond the TFLite core (UI, navigation, scan
screens) do not change. The Supabase backend and FastAPI service do not
change.

## 10. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Eggplant per-class F1 < 0.85 because DigiGreen images are noisy | medium | Class weights + eggplant-specific augmentation (§5.5). Promotion gate blocks regression. |
| INT8 quantization drops macro-F1 by > 0.02 | low | Compare float32 vs INT8 in the harness; if INT8 fails the gate but float32 passes, ship float32 (~16 MB tflite) and document the size regression. |
| `cache()` of decoded images exhausts RAM on user's machine | low | Cap PlantVillage at 4000/class as a hard ceiling if RAM probe shows < 12 GB free; expose `--ram-budget-gb` flag. |
| HF rate-limits or `data.zip` URL changes | low | `ensure_plantvillage_zip` already supports `HF_TOKEN` env var; document fallback path of letting the user pre-download. |
| Wall-clock exceeds the user's overnight window | medium | Phase 2's early-stopping bounds it; `--epochs-cap` env var lets the user shorten if needed. Estimated 6–9 h on a strong CPU. |
| Base model has no archived metrics, so per-class comparison's "regression" check uses freshly-computed base numbers, which can vary by ±0.01 due to random subsampling | low | Comparison harness uses fixed deterministic test split, no augmentation, batch size 1; numbers are reproducible. |

## 13. Revision: multi-model routing for eggplant (2026-05-06)

After implementing tasks 1–17 of the plan, the first release run surfaced a
data constraint that wasn't visible during design: DigiGreen on Hugging
Face only has **9** `eggplant_healthy` rows, **0** `eggplant_mosaic_virus`
rows, and **7** `eggplant_leaf_spot` rows. Mainstream PlantVillage has no
eggplant classes at all, and a survey of HF datasets found **no
permissively-licensed eggplant disease dataset** (the only large NC
candidate, `Saon110/bd-crop-vegetable-plant-disease-dataset`, has no
eggplant either; `Mobiusi/Crop-Pest-and-Disease-Classification-Dataset`
publishes only 5 sample rows on HF).

Reaching the §3 hard floor of macro-F1 ≥ 0.90 across all 16 base-parity
labels with that data is therefore impossible without an external
(non-HF) eggplant dataset.

The accepted resolution is **multi-model routing in the Flutter classifier**:

- v2 trains on the **`cropcare_v2_subset_100`** profile (13 classes:
  9 tomato + 2 pepper + 1 squash + healthy variants — no eggplant).
  This is achievable from the available data and gives a real accuracy
  improvement on the 12 classes that overlap with base.
- The **legacy `cropcare_efficientnet_with_eggplant.tflite` stays
  shipped** alongside the new v2 model. It is loaded lazily and used
  only when the caller's `cropType == "eggplant"`. Tomato, pepper,
  squash, and unknown crops route to the v2 model.
- Both interpreters live in
  [LocalClassifierService](../../../lib/services/local_classifier_service_io.dart);
  the eggplant model is loaded on-demand. If its asset is missing the
  service falls back to the v2 model rather than crashing.

§3's promotion gate stays — it now applies only against the 12 labels
that overlap between base and the new v2 model (the comparison harness
already intersects label sets correctly).

This reframes the goal:

- **What we ship:** a measurably better classifier for tomato, pepper,
  and squash + unchanged eggplant capability.
- **What we don't ship:** a regression. Nothing in the legacy eggplant
  classes degrades.
- **What's deferred:** retraining eggplant. A v3 pass adds eggplant
  once a usable dataset is sourced (Kaggle / Roboflow / direct upload),
  at which point the legacy model can finally retire.

## 11. Out of scope (parking lot)

- Adding `pechay` and other non-PlantVillage crops once licensed data exists.
- Knowledge-distilling EfficientNetB0 → MobileNetV3-small for sub-3 MB tflite.
- ONNX export for cross-runtime inference.
- Backend-side TFLite version of this model in [ai_backend/](../../../ai_backend/) — the backend currently uses LLM-based diagnosis and is unaffected.

## 12. Verification before merge

- `flutter test` passes (no app-side regressions from the dtype change).
- `python -m pytest ml/tests/` passes.
- `comparison_report.md` shows verdict `PROMOTE` and the per-class delta table is included in the PR description.
- A debug APK builds and the app loads the new tflite without runtime errors on the Pixel 7a.
- Manual smoke: scan one image of each crop on-device, confirm the predicted label matches expectations.
