# CropCare AI ML Scaffold

This folder is for preparing and training the CropCare image classifier.
It is intentionally outside the Flutter/FastAPI runtime path.

## Scope

**v2 trains the `cropcare_v2_subset_100` profile (13 labels):** 9 tomato
classes, 2 pepper classes, and `squash_powdery_mildew`. It does **not**
include eggplant — no permissively-licensed eggplant disease dataset is
reachable via Hugging Face, so eggplant data sourcing is deferred to v3.

The Flutter app now ships a single on-device model,
`cropcare_efficientnet_v2.tflite`, for tomato / pepper / squash scans.
Eggplant and pechay remain outside the local classifier label set until a
future retrain adds supported data for them.

Pechay remains knowledge-base only and is not a trainable v2 label. The
`cropcare_v2_full` and `cropcare_v2_base_parity` profiles are still
defined for future runs once eggplant data lands.

Production-eligible sources:

- `DigiGreen/Crop_Disease_Images` (`cc-by-4.0`)
- `mohanty/PlantVillage` (`cc-by-sa-3.0`)

Research/excluded sources:

- `wellCh4n/tomato-leaf-disease-image`: missing license
- `avinashhm/plant-disease-classification`: missing license
- `Mobiusi/Crop-Pest-and-Disease-Classification-Dataset`: non-commercial
- `susnato/plant_disease_detection_processed`: object detection, future non-classifier phase

## Setup

```powershell
py -3.11 -m venv ml\.venv
.\ml\.venv\Scripts\python.exe -m pip install --upgrade pip
.\ml\.venv\Scripts\python.exe -m pip install -r ml\requirements.txt
.\ml\.venv\Scripts\python.exe -m pip install -e ml
```

## Prepare Data

The release automation fetches everything from Hugging Face on its own:

- DigiGreen rows stream from `datasets.load_dataset(...)`. Only mapped
  + active-profile rows trigger an HTTP image download — unmapped or
  out-of-scope rows are skipped before any bytes hit disk.
- PlantVillage's `data.zip` (~2 GB) is auto-downloaded once via
  `cropcare_training.hf_assets.ensure_plantvillage_zip` and cached
  under `ml/data/plantvillage_data.zip`. You do **not** need to
  pre-download or pass `-PlantVillageZipPath` unless you want to use a
  local cached copy.

The minimum-per-label gate is `80`. Eggplant labels that occasionally
hover around 100 images during a run survive minor sampling noise.
PlantVillage rows are uncapped by default; DigiGreen rows are capped at
`1500/class` so the noisier real-field photos don't drown out the lab
imagery.

## Train and Release

The recommended path is the release script — it prepares data, trains,
runs the comparison harness, gates promotion, runs the Flutter test
suite, and (optionally) builds an APK:

```powershell
.\ml\run_model_release.ps1 -BuildAndroid
```

That uses these defaults from the spec:

| Flag | Default | Notes |
|---|---|---|
| `-LabelProfile` | `cropcare_v2_subset_100` | 13 labels: tomato + pepper + squash (no eggplant local runtime support yet) |
| `-Epochs` | `30` | 5 warm-up + ≤25 fine-tune |
| `-BatchSize` | `32` | |
| `-MaxPerLabel` | unset | PlantVillage uncapped |
| `-DigigreenMaxPerLabel` | `1500` | per-class cap on DigiGreen rows |
| `-MinPerLabel` | `80` | hard gate before training starts |

The release runs these steps in order:

1. **`prepare-dataset`** — fetches HF data, persists images under
   `ml/artifacts/cropcare_v2/images_by_split/{train,validation,test}/<label>/`.
2. **`train-efficientnet`** — two-phase training:
   - **Warm-up (5 epochs):** frozen EfficientNetB0 backbone, head only,
     Adam @ 1e-3, label-smoothed cross-entropy, EarlyStopping +
     ReduceLROnPlateau + BestMacroF1Checkpoint + CSVLogger.
   - **Fine-tune (≤25 epochs):** last 30 backbone layers unfrozen
     (BatchNorm stays frozen), AdamW @ cosine-decayed 1e-4 → 1e-6, MixUp
     (α=0.2) on the train pipeline, EarlyStopping (patience=5,
     restore_best_weights), BestMacroF1Checkpoint.
   - Augmentation (`flip → rotation → zoom → translation → contrast →
     brightness`) is in the model graph and a no-op at TFLite inference
     time. Eggplant rows get an extra zoom + brightness pass.
   - Class weights are inverse-frequency normalised to mean 1.0.
   - Exports float32 TFLite (`*_float.tflite` for sanity), Keras
     `*.keras`, and the production INT8 TFLite via post-training
     quantization with a 200-sample representative dataset.
3. **`compare-models`** — runs the currently shipped
  `assets/models/cropcare_efficientnet_v2.tflite` (base) and the
  candidate INT8 TFLite on the held-out test split, writes
   `comparison_report.json` and `comparison_report.md`, and exits non-zero
   if the verdict is BLOCK.
4. **`promote-artifacts`** — only copies `cropcare_efficientnet_v2.tflite`
   and `labels_v2.txt` into `assets/models/` if comparison verdict is
   PROMOTE.
5. **`flutter test`** — runs the Dart suite.
6. **`flutter build apk --release`** — only when `-BuildAndroid` is set.

### Promotion Gate (hard floors)

`assets/models/` is only updated when **every** condition holds against
the held-out test split:

- Overall macro-F1 ≥ **0.90**
- Overall accuracy ≥ **0.92**
- Every class: F1 ≥ 0.85 **AND** ≥ that class's base F1 (no regressions)
- Every class: precision ≥ 0.80, recall ≥ 0.80
- TFLite output tensor width == `len(labels_v2.txt)`

Final shipped `.tflite` size ≤ 7 MB is a *soft* target. If INT8
quantization regresses macro-F1 by more than 0.02, the float32 model
ships instead even though it exceeds 7 MB — accuracy beats size.

If the gate blocks, the existing `cropcare_efficientnet_v2.tflite`
remains the shipped artifact.

### Comparison Report

After every release run, `ml/artifacts/cropcare_v2/comparison_report.md`
contains:

- The PROMOTE/BLOCK verdict at the top, with reasons if blocked.
- Overall metrics table (base vs candidate vs Δ) for macro_f1 and
  accuracy.
- Per-class table with base F1, candidate F1, Δ F1, candidate
  precision, candidate recall.

The companion `comparison_report.json` carries the same numbers in
machine-readable form and is what `release.py promote` reads to decide
whether to copy artifacts.

### Manual Comparison

You can also run the harness against any candidate model standalone:

```powershell
.\ml\.venv\Scripts\python.exe -m cropcare_training.compare_models `
  --base assets/models/cropcare_efficientnet_v2.tflite `
  --base-labels assets/models/labels_v2.txt `
    --candidate ml/artifacts/cropcare_v2/cropcare_efficientnet_v2.tflite `
    --candidate-labels ml/artifacts/cropcare_v2/labels_v2.txt `
    --test-dir ml/artifacts/cropcare_v2/images_by_split/test `
    --report-dir ml/artifacts/cropcare_v2
```

It exits non-zero on BLOCK so it can be wired into other scripts.

### Smoke / smaller runs

The CPU smoke variant runs the same training defaults (30 epochs,
base-parity, batch 32) but without promotion or APK build:

```powershell
.\ml\run_cpu_training.ps1
```

Add `-Full` to use every mapped row instead of capping DigiGreen, or
`-MaxPerLabel 100` for a fast check.

## Generated artifacts

In `ml/artifacts/cropcare_v2/`:

- `dataset_manifest_v2.csv` — every row that survived the
  filter/cap/gate pipeline.
- `label_map_v2.csv` — taxonomy (`label_key`, `crop_type`,
  `display_name`, `trainable_v2`).
- `labels_v2.txt` — one label per line, in the order matching the
  TFLite output tensor.
- `training_report_v2.json` — training history, class counts, eval
  metrics, confusion matrix, per-class precision/recall/F1.
- `comparison_report.{json,md}` — base-vs-candidate verdict + tables.
- `training_log.csv` — per-epoch loss/accuracy/lr/val_macro_f1.
- `cropcare_efficientnet_v2_float.tflite` — sanity float32 model
  (never shipped).
- `cropcare_efficientnet_v2.tflite` — production INT8 model.
- `cropcare_efficientnet_v2.keras` — full Keras model for offline
  re-export or fine-tune resume.
- `images_by_split/{train,validation,test}/<label>/*.jpg` — persisted
  dataset (excluded from git).

## Runtime Handoff

The Flutter classifier
([lib/services/tflite_classifier_core.dart](../lib/services/tflite_classifier_core.dart))
auto-detects the TFLite input dtype at load time and dispatches to the
appropriate path:

- **Current shipped runtime** (`cropcare_efficientnet_v2.tflite`): packs
  raw RGB bytes into a flat `Uint8List`. Output is dequantized using the
  tensor's quantization scale/zero-point before softmax/argmax.
- **Float32 fallback support** remains in the classifier core for future
  exports and tests that use float input tensors.

Both work without changing any other Flutter code.
