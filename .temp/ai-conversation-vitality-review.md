# CropCare AI Conversation and Farm Vitality Review

Date: 2026-05-09  
Device observed: Pixel 7a, `33171JEAN23637`

## Scope

This review investigated two reported issues:

- AI chat conversations felt stale and generic.
- Farm Vitality appeared stuck at about `50%` and did not visibly change.

## Root Cause Summary

### 1. AI Chat Responses Were Falling Back To Local Canned Text

The Flutter app sends chat requests through `AiBackendService` to the FastAPI backend at `/v1/chat`.

On Android, the app previously defaulted to:

```text
http://10.0.2.2:8000
```

That address is correct for an Android emulator, but not for a physical phone. A physical phone needs the laptop LAN IP address, for example:

```text
http://192.168.0.153:8000
```

Because the physical device could not reach the backend, `ChatProvider` caught the failure and silently generated local fallback responses. Those fallback responses are rule-based and generic, which made every conversation feel stale.

### 2. Backend Was Not Running During Verification

Health checks failed for:

```text
http://127.0.0.1:8000/health
http://192.168.0.153:8000/health
http://192.168.254.133:8000/health
```

Report:

```text
Unable to connect to the remote server
```

This means the app currently has no reachable online AI service unless the backend is started and exposed to the phone.

### 3. Farm Vitality Was Using A Stale Stored Score

Farm Vitality reads from each crop's `latestHealthScore`.

The initial crop score is severity-based:

```dart
Severity.severe => 25.0
Severity.moderate => 50.0
Severity.mild => 70.0
_ => 55.0
```

So a moderate diagnosis starts at `50%`.

The score was mainly updated by the progress AI endpoint. If the backend was unreachable, progress scoring could fail instead of producing a useful score update. That made Farm Vitality appear stuck at the initial value.

## Changes Made

### AI Backend Configuration

Added a physical Android backend override:

```dart
AI_BACKEND_ANDROID_BASE_URL
```

Files:

- `lib/core/constants/app_constants.dart`
- `lib/data/remote/ai_backend_service.dart`

The app now resolves backend URLs in this order:

1. `AI_BACKEND_BASE_URL`
2. `AI_BACKEND_ANDROID_BASE_URL` for Android
3. `http://10.0.2.2:8000` for Android emulator fallback
4. `http://127.0.0.1:8000` for web/desktop fallback

### Chat Fallback Visibility

Changed chat fallback behavior so the user sees:

```text
Online AI is unavailable right now, so I am using offline crop guidance only.
```

Instead of silently showing generic local responses as if they came from the real AI backend.

File:

- `lib/features/chat/providers/chat_provider.dart`

### Farm Vitality Fallback Scoring

Added local health score estimation when progress AI is unavailable.

File:

- `lib/services/health_score_service.dart`

The local estimate uses:

- due treatment tasks
- completed treatment tasks
- latest diagnosis severity penalty

### Progress Check-In Resilience

Updated the crop check-in flow so if `/v1/progress` fails, it still computes and stores an estimated score from completed tasks.

File:

- `lib/features/crops/screens/crop_detail_screen.dart`

### Dashboard Refresh

Updated the dashboard so after returning from a crop detail screen, it refreshes crops and picks up the latest score.

File:

- `lib/features/home/dashboard/dashboard_screen.dart`

## What Was Tested

### Targeted Flutter Tests

Command:

```powershell
flutter test test/data/remote/ai_backend_service_test.dart test/services/health_score_service_current_test.dart
```

Result:

```text
All tests passed.
4/4 passing.
```

Covered behavior:

- configured backend URL wins over platform defaults
- Android-specific backend URL is used for physical-device builds
- emulator default remains `http://10.0.2.2:8000` when no override is configured
- health score changes based on completed tasks instead of staying at severity baseline

### Android Build Verification

Command:

```powershell
flutter build apk --debug
```

Result:

```text
Built build\app\outputs\flutter-apk\app-debug.apk
```

Build completed successfully.

### Flutter Analyze

Command:

```powershell
flutter analyze
```

Result:

```text
108 issues found.
```

Notes:

- The analyzer output is mostly existing warnings and info-level cleanup, especially `withOpacity` deprecations and existing unused elements.
- Two new warnings from the backend URL patch were fixed.
- Remaining analyzer output is not specific to the AI/vitality patch.

### Backend Reachability Check

Commands tested via PowerShell `Invoke-WebRequest`:

```text
http://127.0.0.1:8000/health
http://192.168.0.153:8000/health
http://192.168.254.133:8000/health
```

Result:

```text
Unable to connect to the remote server
```

Conclusion:

The backend was not reachable during testing.

## How To Make The AI Work On A Physical Device

### 1. Start The Backend

From the project root:

```powershell
cd ai_backend
.\run.ps1
```

Expected backend URL:

```text
http://0.0.0.0:8000
```

Check locally:

```powershell
Invoke-WebRequest http://127.0.0.1:8000/health
```

### 2. Confirm Required Backend Environment

Create or update:

```text
ai_backend/.env
```

Important values:

```text
OPENAI_API_KEY=...
OPENAI_MODEL=gpt-5.4-mini
REQUIRE_AUTH=false
ENABLE_MOCK_SERVICES=false
```

If `OPENAI_API_KEY` is missing, the backend will return knowledge/fallback responses instead of live OpenAI responses.

If Supabase knowledge should be used by the backend, also configure:

```text
SUPABASE_URL=...
SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...
```

### 3. Use The Laptop LAN IP For The Phone

Observed laptop IPv4 addresses:

```text
Ethernet: 192.168.254.133
Wi-Fi:    192.168.0.153
```

Use the IP on the same network as the phone.

Example:

```powershell
flutter run -d 33171JEAN23637 --dart-define=AI_BACKEND_ANDROID_BASE_URL=http://192.168.0.153:8000
```

For release builds:

```powershell
flutter build apk --release --dart-define=AI_BACKEND_ANDROID_BASE_URL=http://192.168.0.153:8000
adb -s 33171JEAN23637 install -r build\app\outputs\flutter-apk\app-release.apk
```

### 4. Allow Windows Firewall If Needed

If the backend works on `127.0.0.1` but not on the LAN IP, Windows Firewall may be blocking inbound port `8000`.

Allow Python/Uvicorn or open TCP port `8000` for the private network.

### 5. Keep Phone And Laptop On The Same Network

The phone cannot reach `192.168.0.153` unless it is on the same Wi-Fi/LAN subnet or routing allows it.

If the laptop is on Ethernet and the phone is on Wi-Fi, make sure both networks can talk to each other.

## Recommended Next Steps

1. Start `ai_backend` and verify `/health` locally.
2. Verify `/health` from the laptop LAN IP.
3. Run the app on the Pixel 7a with `AI_BACKEND_ANDROID_BASE_URL`.
4. Send a chat message and confirm metadata no longer shows `model: local-fallback`.
5. Submit a crop check-in and confirm Farm Vitality changes after the score update.
6. Consider adding a small in-app backend status indicator for development builds.
7. Consider adding retry/error UI for backend failures instead of relying only on chat text.

## Current Caveats

- `macos/Flutter/GeneratedPluginRegistrant.swift` was already modified before this review and was not touched.
- `flutter analyze` still reports project-wide pre-existing warnings.
- Live AI quality still depends on the FastAPI backend being reachable and `OPENAI_API_KEY` being configured.
- The physical-device URL must be supplied at build/run time unless a production backend URL is deployed.
