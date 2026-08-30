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

## Administrator portal

The protected administrator workspace is served at `http://127.0.0.1:8000/admin`
locally and `/admin` on the deployed backend. It manages users, disease library
records, treatments, crops, diagnoses, and system audit data.

Before using it:

1. Keep `REQUIRE_AUTH=true` and configure `SUPABASE_URL`,
  `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` on the backend.
2. Run `docs/supabase-admin-security.sql` once in the Supabase SQL editor.
3. Follow `docs/admin-access-setup.md` to bootstrap the first superadmin.
4. After that, a superadmin approves normal administrator registrations from
  **User management** in the portal. Never place administrator roles in
  `user_metadata`; users can update that metadata.
5. Open `/admin` over HTTPS in production and sign in with the approved account.

The service-role key is never returned to the browser. Administrator API routes
always require a bearer token and verify the trusted `app_metadata` role, even
when ordinary development API authentication is disabled. User removal is a
reversible suspension, records are archived instead of hard-deleted, API fields
are allowlisted, confidential auth fields and media URLs are excluded, and
mutations write audit metadata without storing changed values.

## Render deployment

Use Render only for the online augmentation endpoints.

- Keep scan classification inside the Flutter app with on-device TFLite.
- Host `POST /v1/chat`, `POST /v1/transcribe`, `POST /v1/progress`, and auth-backed knowledge access on Render.
- Do not depend on Render for the app's core offline path.

### What Render will handle

- GPT-backed chat using the uploaded image plus TFLite diagnosis context
- OpenAI Whisper transcription if you keep `OPENAI_API_KEY` set
- progress/assessment endpoints

### What stays inside the APK

- local TFLite scan and crop detection
- bundled disease knowledge and SQLite cache
- offline structured treatment replies when internet is unavailable

### Step-by-step Render guide

1. Push the latest repo to GitHub.

2. In Render, choose `New +` -> `Blueprint`.

3. Select this GitHub repository.

4. Render will detect the repository `render.yaml` file and create the `cropcare-ai-backend` web service from the `ai_backend` folder.

5. In the Render service dashboard, add these environment variables:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `OPENAI_API_KEY`
- `OPENAI_MODEL=gpt-5.4-mini`
- `ENABLE_MOCK_SERVICES=false`
- `REQUIRE_AUTH=true`
- `APP_ENV=production`
- `LOG_LEVEL=INFO`
- `CORS_ORIGINS=http://localhost:8080,http://127.0.0.1:8080`

If you will also call the backend from a hosted web frontend later, append that exact origin to `CORS_ORIGINS`.
Hosted AI routes require an authenticated Supabase session and return `401 Unauthorized` for unsigned requests.

6. Deploy the service.

7. After deploy finishes, open:

- `https://<your-render-service>.onrender.com/health`
- `https://<your-render-service>.onrender.com/docs`

8. Confirm `/health` reports:

- `status: ok`
- `mockServices: false`
- `openaiConfigured: true`

9. Keep in mind that Render will not run the Flutter-based TFLite helper path used by `/v1/detect` in local development. The mobile app should keep using the on-device TFLite classifier for scan detection.

### APK configuration after Render deploy

Build the APK with the hosted backend URL injected at compile time:

```powershell
flutter build apk --release --dart-define=AI_BACKEND_BASE_URL=https://<your-render-service>.onrender.com
```

That gives you this runtime behavior:

- online: the app uses Render for GPT chat, transcription, and progress features
- offline: the app falls back to on-device TFLite, bundled disease knowledge, and local structured replies

### APK verification checklist

After the Render deploy is live, test the APK in two passes.

Online pass:

1. Install the APK built with `AI_BACKEND_BASE_URL` pointing to Render.
2. Sign in with a Supabase account before using hosted AI requests.
3. Upload a crop photo.
4. Confirm TFLite still performs the initial scan locally.
5. Confirm the chat response is conversational and image-aware.
6. Confirm `/v1/chat` requests appear in Render logs.

Offline pass:

1. Turn on airplane mode.
2. Reopen the app.
3. Upload a supported crop photo.
4. Confirm the local TFLite scan still works.
5. Confirm the app returns a structured offline answer from bundled knowledge instead of failing.
6. Confirm no hosted-backend dependency blocks the core scan flow.

### If you use Render without Blueprint

You can also create the service manually with these settings:

- Runtime: `Python 3`
- Root Directory: `ai_backend`
- Build Command: `pip install --upgrade pip && pip install -r requirements.txt`
- Start Command: `uvicorn app.main:app --host 0.0.0.0 --port $PORT`
- Health Check Path: `/health`

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