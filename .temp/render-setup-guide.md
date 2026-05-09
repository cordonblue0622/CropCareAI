# Deploying CropCare AI to Render — Step-by-Step

Time required: ~15 minutes.
Cost: **$0** if you stay within the free tier (and a small OpenAI usage charge
per chat / detection — typically under $1/month for personal testing).

---

## What you will end up with

A public HTTPS URL like `https://YOURNAME-cropcare-api.onrender.com` that you
own. You build the APK pointing at this URL, install it on any phone, and it
works on any internet connection — your laptop does **not** need to be on for
the app to work.

The OpenAI key, Supabase service-role key, and any other secrets stay in
Render's environment variable store. They never touch the APK or git.

---

## What you need before you start

1. A **GitHub account** ([github.com](https://github.com), free).
2. A **Render account** ([render.com](https://render.com), free; sign up with GitHub for one click).
3. Your own **OpenAI API key**:
   - Sign in at [platform.openai.com](https://platform.openai.com).
   - Go to **API keys** in the left sidebar → **Create new secret key** → copy it. It looks like `sk-proj-…`.
   - **Important:** put $5 of credit on the account (Settings → Billing) and set a hard monthly cap of $5–10 so you never get surprised.
4. The CropCare AI repo on **your own** GitHub fork (so Render can pull from it):
   - Go to the original repo on GitHub → click **Fork** in the top right → keep the default name → **Create fork**.

---

## Step 1 — Create the Web Service on Render

1. Sign in at [dashboard.render.com](https://dashboard.render.com).
2. Click **+ New** (top right) → **Web Service**.
3. Under **Source Code**, click **Connect account** if this is your first time, authorize Render to read your GitHub repos, then pick your forked `CropCareAI` repo from the list and click **Connect**.

You will land on a configuration form. Fill it in exactly like this:

| Field | Value |
|---|---|
| **Name** | `cropcare-api` (or any name; it becomes part of the URL) |
| **Region** | Whichever is closest to you (Singapore for PH/SEA users) |
| **Branch** | `main` |
| **Root Directory** | `ai_backend` |
| **Runtime / Language** | `Python 3` |
| **Build Command** | `pip install -r requirements.txt` |
| **Start Command** | `uvicorn app.main:app --host 0.0.0.0 --port $PORT` |
| **Instance Type** | **Free** |

> Note: leave **Auto-Deploy** on — every push to `main` will redeploy automatically.

Do **not** click Create yet — first add environment variables.

---

## Step 2 — Add Environment Variables

Scroll down to **Environment Variables** on the same page. Click **Add Environment Variable** for each row below:

| Key | Value | Why |
|---|---|---|
| `PYTHON_VERSION` | `3.11.8` | Pin the runtime; matches local dev |
| `OPENAI_API_KEY` | `sk-proj-...` (your own key from prerequisites) | **Your secret.** Never commit this. |
| `OPENAI_MODEL` | `gpt-5.4-mini` | Cheap, capable; switch to `gpt-5.4` later if you want better quality |
| `REQUIRE_AUTH` | `false` | Leave off for now; flip to `true` once you are ready for production |
| `ENABLE_MOCK_SERVICES` | `false` | Use the real OpenAI / Supabase backends |
| `SUPABASE_URL` | `https://dyolfgaabpcibwkphxgo.supabase.co` | Shared class Supabase (see "Use your own Supabase" section below if you want isolation) |
| `SUPABASE_ANON_KEY` | `sb_publishable_pGlOzhxq3XFUFg4KKQhJFg_2D6Gd9pg` | Safe to expose; only allows public reads |
| `SUPABASE_SERVICE_ROLE_KEY` | `sb_secret_...` (ask the project owner — this one is sensitive) | Lets the backend write to Supabase on a user's behalf |
| `LOG_LEVEL` | `INFO` | Default logging |
| `CORS_ORIGINS` | `*` | Loose for now; tighten later if you build a web client |

> Render hides secret values after you save them — that is normal and expected.

Click **Create Web Service** at the very bottom.

---

## Step 3 — Wait for the First Deploy

Render starts building. You will see a live log streaming at the top. Expect:

1. `==> Cloning from https://github.com/YOU/CropCareAI…` — about 5 seconds
2. `==> Building` — pip installs all dependencies, ~3–4 minutes
3. `==> Starting service with 'uvicorn …'` — about 10 seconds
4. `INFO:     Application startup complete.` — you are live

If it fails, scroll back through the log for the first red line. The most
common causes:

| Error | Fix |
|---|---|
| `ModuleNotFoundError: No module named 'app'` | Wrong Root Directory — must be `ai_backend`, not the repo root |
| `Address already in use` | You used `--port 8000` instead of `--port $PORT`; Render assigns the port |
| Backend starts but `/health` 500s | Missing env var; check the **Environment** tab |

---

## Step 4 — Verify the Backend Is Live

Render shows your URL at the top of the service page, like:

```
https://cropcare-api.onrender.com
```

Open these in a browser:

- `https://cropcare-api.onrender.com/health` → should return JSON with `"status":"ok"` and `"openaiConfigured":true`
- `https://cropcare-api.onrender.com/docs` → interactive Swagger UI; click **POST /v1/chat** → **Try it out** → send `{"user_message":"hello"}` → should get a real OpenAI response back

If the `/health` page works but `/v1/chat` returns an OpenAI error, your
`OPENAI_API_KEY` is wrong or has no credit. Add credit on the OpenAI dashboard
and try again.

---

## Step 5 — Build the APK Pointing at Your Render URL

Back on your laptop, in the project root:

```powershell
flutter build apk --release `
  --dart-define=AI_BACKEND_BASE_URL=https://cropcare-api.onrender.com
```

The output APK is at `build\app\outputs\flutter-apk\app-release.apk`. Send
it to anyone — they install it, open it on **any** internet connection, and
the AI features just work because they hit your Render URL.

You can verify by going **completely offline on your laptop** (turn off Wi-Fi)
and then using the APK on a phone with mobile data. Chat should still work,
because the phone is talking to Render directly, not your laptop.

---

## Free Tier Caveats

- **Sleep after 15 min idle.** The first request after a sleep takes ~30 seconds while Render wakes the service. Subsequent requests are instant. Tell users to be patient on the first chat.
- **750 free hours/month** across all your free services, which is enough to leave one service running 24/7.
- **No persistent disk.** Your sqlite, model cache, etc. resets on every redeploy. The CropCare backend doesn't write important state to disk (everything goes through Supabase), so this is fine.
- **Slow cold starts on Whisper.** The transcription endpoint (`/v1/transcribe`) loads the Whisper model on first call. This will take 10–20s the first time per cold container.

When you're ready to upgrade: **Starter** plan is $7/month, no sleep, faster
build/deploy. Recommended once you have real users.

---

## Use Your Own Supabase (optional, more advanced)

If you want **complete data isolation** — your own user accounts, your own
disease knowledge base, your own crop records — instead of sharing the class
Supabase project:

1. Sign up at [supabase.com](https://supabase.com) → **New project** → name it `cropcare-yourname` → pick a strong DB password → **Asia Southeast (Singapore)** region.
2. Wait ~2 minutes for provisioning.
3. **Settings → API** — copy the `URL`, `anon public` key, and `service_role` key.
4. **SQL Editor → New query** — paste the schema from the original project (ask the project owner for the `schema.sql` dump or run `supabase db dump --file schema.sql` if you have CLI access). Run it.
5. Update three Render env vars with your own values: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.
6. Update **two** values in the Flutter app at [`lib/core/constants/app_constants.dart`](../lib/core/constants/app_constants.dart) — `supabaseUrl` and `supabaseAnonKey` — and rebuild the APK.
7. Optionally seed the disease knowledge by importing the CSV from `assets/data/` (if available) into the `disease_knowledge_base` table.

This gives every classmate their own complete database, but it means you can't
share user accounts or disease KB updates between deployments.

---

## Common Mistakes Checklist

- [ ] **Did you fork the repo first?** Render needs to read from a repo *you* own (or are a collaborator on), not the original.
- [ ] **Is Root Directory set to `ai_backend`?** This trips up almost everyone. Without it, Render tries to build from the Flutter project root and fails immediately.
- [ ] **Did you use `$PORT` in the start command, not `8000`?** Render injects a random port — hard-coding 8000 means the service never becomes reachable.
- [ ] **Is your OpenAI account funded?** A new account has $0 credit by default; the API will return 429 / quota errors until you add billing.
- [ ] **Did you rebuild the APK after deploying?** The URL is baked in at compile time. The old APK still points at whatever URL it was built with.
- [ ] **HTTPS, not HTTP.** Render gives you `https://`; if you ever build with `http://your-url` Android release builds will silently block all traffic to it.

---

## When Something Breaks

1. **Render service shows red "Failed"** → click the service → **Logs** tab → scroll up to the first red line.
2. **App says "Online AI is unavailable"** → open `https://your-service.onrender.com/health` in a browser. If that fails, the backend is down. If it works, the APK is built with the wrong URL — rebuild.
3. **Chat works but answers feel canned** → the message starts with "Online AI is unavailable…" only when the backend is unreachable. If real responses feel low quality, switch `OPENAI_MODEL` to `gpt-5.4` (more expensive but smarter) and redeploy.
4. **Backend 500s on every request** → Logs tab. Usually a missing env var. The schema in [`ai_backend/.env.example`](../ai_backend/.env.example) is the source of truth for what's needed.

---

## Rotate Your Keys If You Ever Leak Them

If you accidentally commit a key to GitHub, push it to a public Discord, or
paste it in a screenshot:

- **OpenAI:** [platform.openai.com/api-keys](https://platform.openai.com/api-keys) → click the key → **Revoke**. Generate a new one. Update the Render env var. Redeploy.
- **Supabase service role:** Project → **Settings** → **API** → **Reset service_role secret**. Update Render. Redeploy.

GitHub will email you within minutes if it detects a committed OpenAI key —
take that email seriously.
