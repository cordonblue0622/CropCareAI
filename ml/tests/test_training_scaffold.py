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
        "promote-artifacts",
        "flutter-test",
        "flutter-build-apk",
    ]
    assert "--label-profile" in steps[0].args
    assert "cropcare_v2_subset_100" in steps[0].args
    assert "build" in steps[-1].args
    assert "apk" in steps[-1].args


def test_metric_gate_requires_macro_f1_and_per_class_recall() -> None:
    report = {
        "metrics": {
            "macro_f1": 0.81,
            "per_class_precision_recall": {
                "tomato_healthy": {"recall": 0.75},
                "pepper_healthy": {"recall": 0.70},
                "accuracy": 0.9,
            },
        }
    }

    validate_metric_gates(report, min_macro_f1=0.80, min_recall=0.70)

    report["metrics"]["per_class_precision_recall"]["pepper_healthy"]["recall"] = 0.69
    try:
        validate_metric_gates(report, min_macro_f1=0.80, min_recall=0.70)
    except ValueError as exc:
        message = str(exc)
    else:
        raise AssertionError("Expected recall gate to fail")

    assert "pepper_healthy recall 0.6900 < 0.7000" in message


def test_plantvillage_zip_downloader_reuses_cached_archive(tmp_path) -> None:
    cached = tmp_path / "plantvillage_data.zip"
    cached.write_bytes(b"cached")

    resolved = ensure_plantvillage_zip(cache_dir=tmp_path)

    assert resolved == cached
    assert resolved.read_bytes() == b"cached"


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
