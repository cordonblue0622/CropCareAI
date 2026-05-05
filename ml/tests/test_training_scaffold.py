from cropcare_training.label_mapping import (
    TARGET_LABELS,
    map_digigreen_row,
    map_plantvillage_label,
    split_diagnoses,
)
from cropcare_training.label_profiles import (
    labels_for_profile,
    excluded_labels_for_profile,
)
from cropcare_training.hf_assets import ensure_plantvillage_zip
from cropcare_training.manifest import ManifestRow, write_label_file, write_training_report_stub
from cropcare_training.prepare_dataset import (
    assert_minimum_label_counts,
    assign_balanced_splits,
    filter_rows_to_labels,
    infer_plantvillage_label,
    load_dataset_split,
)
from cropcare_training.release import (
    ReleaseConfig,
    build_release_steps,
    validate_metric_gates,
)
from cropcare_training.sources import production_sources, research_only_sources
from cropcare_training.automation import TrainingRunConfig, build_run_steps, cpu_environment


def test_target_labels_match_cropcare_v2_scope() -> None:
    assert TARGET_LABELS == [
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
        "squash_powdery_mildew",
    ]


def test_plantvillage_labels_map_to_app_label_keys() -> None:
    assert (
        map_plantvillage_label("Tomato___Spider_mites Two-spotted_spider_mite")
        == "tomato_spider_mites"
    )
    assert map_plantvillage_label("Pepper,_bell___healthy") == "pepper_healthy"
    assert (
        map_plantvillage_label("Squash___Powdery_mildew")
        == "squash_powdery_mildew"
    )
    assert map_plantvillage_label("Potato___healthy") is None


def test_digigreen_maps_field_crop_aliases_and_single_supported_diagnosis() -> None:
    mapped = map_digigreen_row(crop="Brinjal", diagnosis="Mites")

    assert mapped is not None
    assert mapped.crop_type == "eggplant"
    assert mapped.label_key == "eggplant_insect_pest"
    assert mapped.raw_crop == "Brinjal"
    assert mapped.raw_diagnosis == "Mites"


def test_digigreen_skips_ambiguous_multiple_supported_labels() -> None:
    assert (
        map_digigreen_row(
            crop="Tomato",
            diagnosis="Leaf Curl Virus; Early Blight",
        )
        is None
    )


def test_split_diagnoses_handles_semicolon_lists() -> None:
    assert split_diagnoses("Leaf Curl Virus; Thrips; Mites") == [
        "Leaf Curl Virus",
        "Thrips",
        "Mites",
    ]


def test_source_policy_keeps_only_commercial_sources_in_production() -> None:
    production_ids = {source.dataset_id for source in production_sources()}
    research_ids = {source.dataset_id for source in research_only_sources()}

    assert production_ids == {
        "DigiGreen/Crop_Disease_Images",
        "mohanty/PlantVillage",
    }
    assert "Mobiusi/Crop-Pest-and-Disease-Classification-Dataset" in research_ids
    assert "wellCh4n/tomato-leaf-disease-image" in research_ids

    for source in production_sources():
        assert source.production_allowed
        assert source.license_id in {"cc-by-4.0", "cc-by-sa-3.0"}


def test_training_report_records_efficientnet_preprocessing_contract(tmp_path) -> None:
    report_path = tmp_path / "training_report_v2.json"
    write_training_report_stub(
        report_path,
        rows=[
            ManifestRow(
                row_id="row-1",
                image_uri="https://example.com/image.jpg",
                label_key="tomato_healthy",
                crop_type="tomato",
                split="train",
                source_dataset="DigiGreen/Crop_Disease_Images",
                source_split="train",
                source_license="cc-by-4.0",
                raw_crop="Tomato",
                raw_label="Healthy",
            )
        ],
        sources=production_sources(),
        skipped_rows={},
    )

    report = report_path.read_text(encoding="utf-8")
    assert "efficientnet_internal_preprocessing" in report
    assert "must not divide pixels by 255" in report


def test_cpu_training_automation_sets_cuda_disabled_environment() -> None:
    env = cpu_environment()

    assert env["CUDA_VISIBLE_DEVICES"] == "-1"
    assert env["TF_CPP_MIN_LOG_LEVEL"] == "2"


def test_cpu_training_automation_builds_prepare_and_train_steps() -> None:
    config = TrainingRunConfig(max_per_label=3, epochs=1, batch_size=4)

    steps = build_run_steps(config)

    assert steps[0].name == "prepare-dataset"
    assert "--download-images" in steps[0].args
    assert "--max-per-label" in steps[0].args
    assert "3" in steps[0].args
    assert "--require-min-per-label" in steps[0].args
    assert steps[1].name == "train-efficientnet"
    assert "--epochs" in steps[1].args
    assert "1" in steps[1].args
    assert "--batch-size" in steps[1].args
    assert "4" in steps[1].args


def test_label_writer_can_emit_actual_trained_subset(tmp_path) -> None:
    labels_path = tmp_path / "labels_v2.txt"
    write_label_file(labels_path, ["tomato_healthy", "pepper_healthy"])

    assert labels_path.read_text(encoding="utf-8").splitlines() == [
        "tomato_healthy",
        "pepper_healthy",
    ]


def test_hf_loader_uses_default_config_for_dataset_viewer_sources(monkeypatch) -> None:
    calls = []

    def fake_load_dataset(dataset_id, name=None, split=None):
        calls.append((dataset_id, name, split))
        return []

    monkeypatch.setattr("cropcare_training.prepare_dataset.load_dataset", fake_load_dataset)

    assert load_dataset_split("mohanty/PlantVillage", "train") == []
    assert calls == [("mohanty/PlantVillage", "default", "train")]


def test_balanced_split_assigns_train_and_validation_per_label_for_training() -> None:
    rows = [
        ManifestRow(
            row_id=f"row-{index}",
            image_uri=f"https://example.com/{index}.jpg",
            label_key="tomato_healthy",
            crop_type="tomato",
            split="unassigned",
            source_dataset="DigiGreen/Crop_Disease_Images",
            source_split="train",
            source_license="cc-by-4.0",
            raw_crop="Tomato",
            raw_label="Healthy",
        )
        for index in range(2)
    ]

    balanced = assign_balanced_splits(rows, require_validation=True)

    assert [row.split for row in balanced] == ["train", "validation"]


def test_balanced_split_uses_80_10_10_for_hundred_image_classes() -> None:
    rows = [
        ManifestRow(
            row_id=f"row-{index:03d}",
            image_uri=f"https://example.com/{index}.jpg",
            label_key="tomato_healthy",
            crop_type="tomato",
            split="unassigned",
            source_dataset="mohanty/PlantVillage",
            source_split="train",
            source_license="cc-by-sa-3.0",
            raw_crop="tomato",
            raw_label="Tomato___healthy",
        )
        for index in range(100)
    ]

    balanced = assign_balanced_splits(rows, require_validation=True)
    counts = {split: sum(row.split == split for row in balanced) for split in ["train", "validation", "test"]}

    assert counts == {"train": 80, "validation": 10, "test": 10}


def test_plantvillage_label_can_be_inferred_from_text_path() -> None:
    row = {
        "text": "raw/color/Tomato___Bacterial_spot/example.JPG",
    }

    assert infer_plantvillage_label(row) == "Tomato___Bacterial_spot"


def test_minimum_label_count_gate_reports_short_labels() -> None:
    rows = [
        ManifestRow(
            row_id="row-1",
            image_uri="https://example.com/1.jpg",
            label_key="tomato_healthy",
            crop_type="tomato",
            split="train",
            source_dataset="DigiGreen/Crop_Disease_Images",
            source_split="train",
            source_license="cc-by-4.0",
            raw_crop="Tomato",
            raw_label="Healthy",
        )
    ]

    try:
        assert_minimum_label_counts(
            rows,
            min_per_label=2,
            labels=["tomato_healthy", "pepper_healthy"],
        )
    except ValueError as exc:
        message = str(exc)
    else:
        raise AssertionError("Expected minimum label gate to fail")

    assert "tomato_healthy=1/2" in message
    assert "pepper_healthy=0/2" in message


def test_subset_100_profile_trains_tomato_pepper_and_squash_only() -> None:
    labels = labels_for_profile("cropcare_v2_subset_100")
    excluded = excluded_labels_for_profile("cropcare_v2_subset_100")

    assert "tomato_bacterial_spot" in labels
    assert "pepper_bacterial_spot" in labels
    assert "squash_powdery_mildew" in labels
    assert "eggplant_healthy" not in labels
    assert "eggplant_mosaic_virus" in excluded
    assert len(labels) == 13


def test_filter_rows_to_release_profile_removes_excluded_labels() -> None:
    rows = [
        ManifestRow(
            row_id="tomato-1",
            image_uri="https://example.com/tomato.jpg",
            label_key="tomato_healthy",
            crop_type="tomato",
            split="train",
            source_dataset="DigiGreen/Crop_Disease_Images",
            source_split="train",
            source_license="cc-by-4.0",
            raw_crop="Tomato",
            raw_label="Healthy",
        ),
        ManifestRow(
            row_id="eggplant-1",
            image_uri="https://example.com/eggplant.jpg",
            label_key="eggplant_healthy",
            crop_type="eggplant",
            split="train",
            source_dataset="DigiGreen/Crop_Disease_Images",
            source_split="train",
            source_license="cc-by-4.0",
            raw_crop="Brinjal",
            raw_label="Healthy",
        ),
    ]

    filtered = filter_rows_to_labels(
        rows,
        labels_for_profile("cropcare_v2_subset_100"),
    )

    assert [row.label_key for row in filtered] == ["tomato_healthy"]


def test_release_steps_train_then_promote_then_build_android() -> None:
    config = ReleaseConfig(
        label_profile="cropcare_v2_subset_100",
        max_per_label=100,
        min_per_label=100,
        epochs=12,
        batch_size=32,
        build_android=True,
    )

    steps = build_release_steps(config)

    assert [step.name for step in steps] == [
        "train-efficientnet-release",
        "compare-models",
        "promote-artifacts",
        "flutter-test",
        "flutter-build-apk",
    ]
    assert "--label-profile" in steps[0].args
    assert "cropcare_v2_subset_100" in steps[0].args
    assert "build" in steps[-1].args
    assert "apk" in steps[-1].args


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
    digigreen = [
        row for row in capped if row.source_dataset == "DigiGreen/Crop_Disease_Images"
    ]
    plantvillage = [
        row for row in capped if row.source_dataset == "mohanty/PlantVillage"
    ]

    assert len(digigreen) == 2
    assert len(plantvillage) == 7


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
    assert any(
        "cropcare_efficientnet_with_eggplant.tflite" in arg for arg in compare_args
    )
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


def test_metric_gate_requires_macro_f1_and_per_class_recall() -> None:
    report = {
        "metrics": {
            "macro_f1": 0.91,
            "per_class_precision_recall": {
                "tomato_healthy": {"recall": 0.85},
                "pepper_healthy": {"recall": 0.80},
                "accuracy": 0.9,
            },
        }
    }

    validate_metric_gates(report, min_macro_f1=0.90, min_recall=0.80)

    report["metrics"]["per_class_precision_recall"]["pepper_healthy"]["recall"] = 0.79
    try:
        validate_metric_gates(report, min_macro_f1=0.90, min_recall=0.80)
    except ValueError as exc:
        message = str(exc)
    else:
        raise AssertionError("Expected recall gate to fail")

    assert "pepper_healthy recall 0.7900 < 0.8000" in message


def test_plantvillage_zip_downloader_reuses_cached_archive(tmp_path) -> None:
    cached = tmp_path / "plantvillage_data.zip"
    cached.write_bytes(b"cached")

    resolved = ensure_plantvillage_zip(cache_dir=tmp_path)

    assert resolved == cached
    assert resolved.read_bytes() == b"cached"


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
    # At least one trainable layer (we asked for 30; backbone has > 30 layers).
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


def test_base_parity_profile_matches_shipped_base_labels() -> None:
    labels = labels_for_profile("cropcare_v2_base_parity")
    excluded = excluded_labels_for_profile("cropcare_v2_base_parity")

    # Must equal the 16 labels currently shipped in
    # assets/models/labels_with_eggplant.txt (no squash for the v2
    # base-parity scope; squash stays in the wider full profile).
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
