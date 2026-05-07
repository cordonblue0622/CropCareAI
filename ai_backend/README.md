# CropCare AI Backend

FastAPI service for the online AI parts of CropCare AI:

- v2 TFLite disease detection
- GPT-5.4 mini chat orchestration
- Whisper transcription
- Supabase auth and storage integration

## What is ready

- FastAPI app scaffold
- `GET /health`
- `POST /v1/detect`
- `POST /v1/chat`
- `POST /v1/transcribe`
- optional bearer-token auth guard
- mock responses enabled by default until your models and API keys are ready

The backend can run in mock mode on Python 3.14 using the base requirements.
For faster-whisper extras, use Python 3.11 or 3.12 and install the ML dependencies from `requirements-ml.txt`.

## Project layout

```text
ai_backend/
  app/
    api/
    core/
    schemas/
    services/
    utils/
    main.py
  models/
    whisper/
  tests/
  .env.example
  requirements.txt
  Dockerfile
```

## Local setup

```powershell
cd ai_backend
.\setup.ps1
.\run.ps1
```

If Python is not installed yet, `setup.ps1` will stop and tell you the exact `winget` command to run.

## Windows quick start

Python 3.14 is fine for mock mode and API integration.
Use Python 3.11 or 3.12 when you are ready to install faster-whisper dependencies from `requirements-ml.txt`.

1. Install Python 3.11:

```powershell
winget install -e --id Python.Python.3.11
```

2. Close and reopen PowerShell.

3. Bootstrap the backend:

```powershell
cd ai_backend
.\setup.ps1
```

4. Edit `.env` with your real keys when ready.

5. Start the API:

```powershell
.\run.ps1
```

If you already installed Python 3.14, you can use it now for mock mode.
Later, install Python 3.11 alongside it for the real ML runtime.

## ML dependency setup later

When you are ready to install faster-whisper extras, use Python 3.11 or 3.12:

```powershell
cd ai_backend
py -3.11 -m venv .venv-ml
.\.venv-ml\Scripts\python.exe -m pip install --upgrade pip
.\.venv-ml\Scripts\python.exe -m pip install -r requirements.txt -r requirements-ml.txt
```

At that point, set `ENABLE_MOCK_SERVICES=false` in `.env` and run the backend from that ML-capable environment.

Open `http://127.0.0.1:8000/docs` for Swagger UI.

## Environment variables

Fill these in as your stack becomes available:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `OPENAI_API_KEY`
- `TFLITE_MODEL_PATH`
- `TFLITE_LABELS_PATH`
- `WHISPER_MODEL_SIZE`

For the first run, leave `ENABLE_MOCK_SERVICES=true` so the endpoints work before your trained weights are ready.

## Recommended next steps

1. Keep `assets/models/cropcare_efficientnet_v2.tflite` and `assets/models/labels_v2.txt` in sync with the Flutter app if you want live `/v1/detect` responses.
2. Replace mock transcription in `app/services/whisper_service.py` with your chosen Whisper runtime.
3. Connect `app/services/knowledge_service.py` to your curated FAO and Department of Agriculture knowledge records in Supabase.
4. Lock the Flutter app to these route contracts before the model files are finalized.