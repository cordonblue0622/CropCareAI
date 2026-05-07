from __future__ import annotations

import asyncio
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from app.core.config import Settings
from app.schemas.detect import BoundingBox, DetectResponse, DetectionItem, ModelInfo
from app.schemas.user import AuthenticatedUser


class DetectService:
    def __init__(self, settings: Settings):
        self._settings = settings

    async def detect_image(
        self,
        image_bytes: bytes,
        filename: str,
        crop_type: str | None,
        requested_by: AuthenticatedUser,
    ) -> DetectResponse:
        if self._can_use_tflite_backend():
            return await self._detect_with_tflite(
                image_bytes=image_bytes,
                filename=filename,
                crop_type=crop_type,
                requested_by=requested_by,
            )

        if self._settings.enable_mock_services:
            return DetectResponse(
                status="ok",
                source="mock-detector",
                crop_type=crop_type,
                detections=[
                    DetectionItem(
                        label="sample_disease_region",
                        label_key="sample_disease_region",
                        confidence=0.91,
                        bbox=BoundingBox(x=0.18, y=0.22, width=0.37, height=0.29),
                    )
                ],
                model=ModelInfo(name="mock-tflite-detector", version="0.1.0"),
                notes=[
                    f"Mock detection for {filename} requested by {requested_by.id}.",
                    "Disable mock services after the v2 detector is ready for live use.",
                ],
            )

        raise RuntimeError(
            "TFLite detection backend is unavailable. Ensure the v2 model, labels, "
            "helper test, and required runtime files are present."
        )

    def _can_use_tflite_backend(self) -> bool:
        return (
            self._settings.resolved_tflite_model_path.exists()
            and self._settings.resolved_tflite_labels_path.exists()
            and self._settings.tflite_helper_test_path.exists()
            and self._has_windows_tflite_runtime()
        )

    async def _detect_with_tflite(
        self,
        image_bytes: bytes,
        filename: str,
        crop_type: str | None,
        requested_by: AuthenticatedUser,
    ) -> DetectResponse:
        return await asyncio.to_thread(
            self._run_tflite_helper,
            image_bytes,
            filename,
            crop_type,
            requested_by,
        )

    def _run_tflite_helper(
        self,
        image_bytes: bytes,
        filename: str,
        crop_type: str | None,
        requested_by: AuthenticatedUser,
    ) -> DetectResponse:
        self._ensure_windows_tflite_runtime()

        flutter_executable = self._resolve_flutter_executable()
        if flutter_executable is None:
            raise RuntimeError(
                "Unable to resolve the Flutter executable for the backend TFLite helper. "
                "Set FLUTTER_COMMAND to an absolute Flutter path or ensure Flutter is on PATH."
            )

        temp_dir = Path(tempfile.mkdtemp(prefix="cropcare-tflite-"))
        image_suffix = Path(filename).suffix or ".jpg"
        image_path = temp_dir / f"upload{image_suffix}"
        output_path = temp_dir / "result.json"
        image_path.write_bytes(image_bytes)

        command = [
            str(flutter_executable),
            "test",
            str(self._settings.tflite_helper_test_path),
            "--plain-name",
            "backend_tflite_detect",
            f"--dart-define=TFLITE_IMAGE_PATH={image_path}",
            f"--dart-define=TFLITE_MODEL_PATH={self._settings.resolved_tflite_model_path}",
            f"--dart-define=TFLITE_LABELS_PATH={self._settings.resolved_tflite_labels_path}",
            f"--dart-define=TFLITE_OUTPUT_PATH={output_path}",
            f"--dart-define=TFLITE_FILENAME={filename}",
            f"--dart-define=TFLITE_CROP_TYPE={crop_type or ''}",
        ]

        try:
            result = subprocess.run(
                command,
                cwd=self._settings.workspace_root,
                capture_output=True,
                text=True,
                timeout=120,
                check=False,
            )
            if result.returncode != 0:
                raise RuntimeError(
                    "TFLite helper failed: "
                    f"stdout={result.stdout.strip()} stderr={result.stderr.strip()}"
                )

            if not output_path.exists():
                raise RuntimeError(
                    "TFLite helper completed without producing an output file: "
                    f"stdout={result.stdout.strip()} stderr={result.stderr.strip()}"
                )

            response_payload = self._parse_helper_output(output_path)
            detect_response = DetectResponse.model_validate(response_payload)
            detect_response.notes.insert(
                0,
                f"Backend TFLite inference requested by {requested_by.id}.",
            )
            return detect_response
        finally:
            try:
                output_path.unlink(missing_ok=True)
                image_path.unlink(missing_ok=True)
                temp_dir.rmdir()
            except OSError:
                pass

    def _parse_helper_output(self, output_path: Path) -> dict[str, object]:
        return json.loads(output_path.read_text(encoding="utf-8"))

    def _has_windows_tflite_runtime(self) -> bool:
        if not sys.platform.startswith("win"):
            return True

        project_dll_path = self._project_tflite_windows_dll_path
        engine_dll_path = self._resolve_flutter_engine_tflite_dll_path()
        return project_dll_path.exists() or (
            engine_dll_path is not None and engine_dll_path.exists()
        )

    def _ensure_windows_tflite_runtime(self) -> None:
        if not sys.platform.startswith("win"):
            return

        project_dll_path = self._project_tflite_windows_dll_path
        engine_dll_path = self._resolve_flutter_engine_tflite_dll_path()

        if engine_dll_path is None:
            raise RuntimeError(
                "Unable to resolve the Flutter SDK engine path for Windows TFLite runtime setup. "
                "Ensure FLUTTER_COMMAND points to a valid Flutter executable."
            )

        if engine_dll_path.exists():
            return

        if not project_dll_path.exists():
            raise RuntimeError(
                "Missing Windows TensorFlow Lite runtime. Place "
                "libtensorflowlite_c-win.dll in the project blobs folder at "
                f"{project_dll_path}."
            )

        engine_dll_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(project_dll_path, engine_dll_path)

    @property
    def _project_tflite_windows_dll_path(self) -> Path:
        return self._settings.workspace_root / "blobs" / "libtensorflowlite_c-win.dll"

    def _resolve_flutter_executable(self) -> Path | None:
        flutter_command = self._settings.flutter_command.strip()
        if not flutter_command:
            return None

        configured_path = Path(flutter_command)
        candidates: list[Path] = []

        if configured_path.is_absolute():
            candidates.append(configured_path)
        else:
            resolved_command = shutil.which(flutter_command)
            if resolved_command:
                candidates.append(Path(resolved_command))

            if sys.platform.startswith("win") and configured_path.name.lower() in {
                "flutter",
                "flutter.bat",
                "flutter.exe",
            }:
                candidates.extend(
                    [
                        Path.home() / ".vscode" / "flutter" / "bin" / "flutter.bat",
                        Path.home() / ".vscode" / "flutter" / "bin" / "flutter.exe",
                    ]
                )

        for candidate in candidates:
            if candidate.exists():
                return candidate

        return None

    def _resolve_flutter_engine_tflite_dll_path(self) -> Path | None:
        flutter_executable = self._resolve_flutter_executable()

        if flutter_executable is None or not flutter_executable.exists():
            return None

        flutter_sdk_root = flutter_executable.parent.parent
        return (
            flutter_sdk_root
            / "bin"
            / "cache"
            / "artifacts"
            / "engine"
            / "windows-x64"
            / "blobs"
            / "libtensorflowlite_c-win.dll"
        )