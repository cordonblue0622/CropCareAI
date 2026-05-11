# CropCare AI — Real-User Deployment Guide

Date: 2026-05-10
Audience: shipping the app to real farmers (not workshop / LAN demo)

This guide covers what changes when you go from "phone on my laptop's Wi-Fi" to "an APK installed on a stranger's phone with their own internet". It is opinionated; substitute platforms you prefer where called out.

---

## 1. The split: what runs where

| Component | Where it lives in production |
|---|---|
| Flutter APK / iOS app | On the user's device (signed, distributed via store or APK) |
| `ai_backend` FastAPI | **Public HTTPS host** (Render, Fly.io, Cloud Run, Railway, or your VPS) |
| Supabase (auth, storage, KB, sync) | Already public — no change needed |
| OpenAI / Whisper | Called server-side from `ai_backend` (never from the app) |
| TFLite scanner | On-device — works fully offline |

The phone never talks to OpenAI directly; it always goes through your backend. That's why the backend URL must be reachable from any consumer network, which means it must be a real domain over HTTPS.

---

## 2. Pre-deploy hygiene (do these once)

### 2.1 Rotate the committed OpenAI key

`ai_backend/.env.example` was committed with a real `sk-proj-…` key. Treat it as compromised:

1. Open `https://platform.openai.com/api-keys` and **revoke** that key.
2. Generate a fresh key, store it only in your hosting provider's secret manager.
3. Replace the value in `ai_backend/.env.example` with a placeholder (`OPENAI_API_KEY=replace-me`) and commit that change.
4. Same drill for `SUPABASE_SERVICE_ROLE_KEY` if it was committed — service-role keys can read/write your entire database.

### 2.2 Decide on usage limits

OpenAI calls cost money per request. Before any public release:

- Set a hard **monthly spend cap** in the OpenAI dashboard.
- Set per-user rate limits in the backend (FastAPI middleware — `slowapi` is one option).
- Decide what happens when the cap is hit: degrade gracefully to local fallback, or return 429.

### 2.3 Lock down `REQUIRE_AUTH`

`ai_backend/.env.example` has `REQUIRE_AUTH=false`. For production, set `REQUIRE_AUTH=true` and verify the backend rejects unauthenticated `/v1/chat`, `/v1/detect`, `/v1/progress`, `/v1/transcribe` calls. Otherwise anyone who finds your URL can burn your OpenAI quota.

The Flutter app already attaches the Supabase access token — verify the FastAPI middleware actually validates it.

---

## 3. Deploy the backend

You need a public HTTPS URL. **No domain purchase required** — every option
below gives you a free `*.something.com` subdomain.

### Option A — Render (recommended for first deployment)

**See the dedicated step-by-step guide:** [render-setup-guide.md](render-setup-guide.md)

That guide is written for someone deploying for the first time and includes
every field value, env var, and gotcha. If you just want a working backend in
15 minutes, follow it end to end.

Free tier gives you `https://your-service.onrender.com`. Sleeps after 15 min
idle (first request takes ~30s); upgrade to Starter ($7/mo) when you need
"always on".

### Option B — Fly.io (cheaper at scale, uses the existing Dockerfile)

```powershell
# install flyctl, then:
cd ai_backend
fly launch          # generates fly.toml
fly secrets set OPENAI_API_KEY=sk-... SUPABASE_URL=... ...
fly deploy
```

`Dockerfile` already exists in `ai_backend/` so this works out of the box.
You get `https://your-app.fly.dev`. More terminal-heavy than Render but
cheaper once you outgrow the free tier.

### Option C — Google Cloud Run (pay-per-request, scales to zero)

```powershell
cd ai_backend
gcloud builds submit --tag gcr.io/PROJECT_ID/cropcare-ai
gcloud run deploy cropcare-ai --image gcr.io/PROJECT_ID/cropcare-ai --platform managed --region asia-southeast1 --allow-unauthenticated
```

Set env vars via `gcloud run services update --update-env-vars`. Cheap for
low traffic.

### Option D — Your own VPS (Hetzner, DO, etc.)

You handle TLS (Caddy or nginx + certbot), systemd unit for uvicorn, firewall,
log rotation, and updates. Don't pick this path unless you're comfortable.

### Why **not** Vercel for this backend

Vercel is great for the Flutter web build or a Next.js frontend, but its
serverless Python functions fight this FastAPI app:

- `/v1/transcribe` waits up to **60s** for Whisper; Vercel Hobby caps at 10s, Pro at 60s.
- `/v1/detect` and `/v1/progress` upload images that can exceed Vercel's **4.5 MB request body limit** on Hobby.
- Loads TFLite + Whisper models at startup → cold-start reload every few minutes when idle.
- The existing `ai_backend/Dockerfile` is unused — Vercel Python doesn't read it.

Chat-only would work on Vercel, but full feature parity won't. Stick with
Render / Fly / Cloud Run for this backend.

### Verify the deployment

Whichever option you pick, before moving on:

```powershell
Invoke-WebRequest https://your-backend-host/health
Invoke-WebRequest -Method POST https://your-backend-host/v1/chat `
  -Headers @{ 'content-type' = 'application/json' } `
  -Body '{"user_message":"hi"}'
```

The chat call should return JSON with a non-empty `answer` and a `model` field that is NOT `local-fallback`.

---

## 4. Build the production APK

Once the backend is on a real HTTPS URL:

```powershell
flutter build apk --release `
  --dart-define=AI_BACKEND_BASE_URL=https://your-backend-host
```

Note: `AI_BACKEND_BASE_URL` (not `AI_BACKEND_ANDROID_BASE_URL`) — the `_BASE_URL` form takes precedence and works on all platforms. The `_ANDROID_BASE_URL` override is only needed when you want different URLs per platform (e.g. localhost dev).

Output: `build/app/outputs/flutter-apk/app-release.apk`.

### Cleartext HTTP gotcha

Android release builds **block plain HTTP by default**. If you must point at an `http://` URL (don't, in production), you need to add a `network_security_config.xml` allow-listing the host and reference it from `AndroidManifest.xml`. The cleanest fix is just to terminate TLS at your hosting provider — Render/Fly/Cloud Run all do this automatically.

### Signing for store distribution

Debug-signed APKs work for sideloading but Play Store requires upload signing. If you don't already have one:

```powershell
keytool -genkey -v -keystore ~/cropcare-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Wire it into `android/key.properties` and `android/app/build.gradle` per the [Flutter docs](https://docs.flutter.dev/deployment/android#signing-the-app). Commit the `.gradle` reference but **never** commit the keystore or `key.properties`.

---

## 5. Distribute

| Channel | When |
|---|---|
| Direct APK download (your website / Drive link) | Beta testers, pilot farms |
| Play Store **Internal testing** track | Trusted testers, fast iteration, no review |
| Play Store **Closed testing** | Wider beta, requires a privacy policy URL |
| Play Store **Production** | Public launch — requires content rating, data-safety form, privacy policy, target API level compliance |

Plan for store review to take 2–7 days the first time.

---

## 6. Things you'll forget

- **Versioning:** bump `version:` in `pubspec.yaml` for every build. Play Store rejects duplicate `versionCode`.
- **Permissions:** the app uses camera, microphone, storage. Be ready to justify these in the Play Store data-safety form.
- **Privacy policy:** required for any app that collects user data (Supabase auth → yes, you do). Host one on your domain before submitting.
- **OpenAI cost monitoring:** add a billing alert at, say, 50% of your monthly cap.
- **Backend log retention:** failed `/v1/chat` calls are your only signal that something is wrong with prompts or model behavior. Don't deploy with logs disabled.
- **Schema migrations:** the local sqlite version is `dbVersion: 3` ([app_constants.dart](../lib/core/constants/app_constants.dart)). Bump it whenever you change a table — old installs will silently break otherwise.
- **APK update strategy:** sideloaded APKs do NOT auto-update. Plan to use the Play Store, or build an in-app update prompt that links to a download.

---

## 7. Operations checklist

Before clicking "publish" on Play Store, verify on a fresh install:

- [ ] Open the APK with no internet → app loads, scanner works, chat shows offline-fallback message
- [ ] Open with internet but stop the backend (`fly scale count 0` or pause the Render service) → chat shows the "Online AI is unavailable" prefix, not generic gibberish
- [ ] Resume backend → chat returns real OpenAI responses
- [ ] Mark a task DONE on dashboard → Farm Vitality % moves immediately (this session's fix)
- [ ] Submit a photo check-in → Farm Vitality reflects backend score; if backend down, score still updates from completed tasks
- [ ] Close + reopen app → state persists, no crash
- [ ] Sign in / sign out → no leftover data leaking between accounts
- [ ] OpenAI dashboard shows the request and a sane token count (no runaway prompts)

---

## 8. Cost ballpark (rough, 2026 prices)

| Component | Light usage (~100 active users) | Mid (~1k) |
|---|---|---|
| Render Starter | $7/mo | $25/mo (Pro instance) |
| OpenAI gpt-5.4-mini, ~5 chats/user/day | ~$10/mo | ~$100/mo |
| Whisper transcription, ~1 voice msg/user/day | ~$3/mo | ~$30/mo |
| Supabase Free → Pro | $0 → $25/mo | $25/mo |
| **Total** | **~$20/mo** | **~$180/mo** |

Don't deploy without putting a hard cap on the OpenAI account. One mis-prompted loop can cost hundreds of dollars in an afternoon.
