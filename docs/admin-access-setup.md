# CropCare AI administrator access

## Portal URLs

- Production: `https://cropcareai-nxn4.onrender.com/admin`
- Local development: `http://127.0.0.1:8765/admin`

The production portal is served by the existing Render backend. Render must
have automatic deploys enabled for the repository's `main` branch, or the
latest commit must be deployed manually from the Render dashboard.

## Server connection

The admin backend writes to the same Supabase tables used by the Flutter app:
`crops`, `diagnoses`, `treatments`, and `disease_knowledge_base`. The public
project URL and publishable key are shared with the app for authentication.
Privileged data operations require `SUPABASE_SERVICE_ROLE_KEY` in the backend
environment. Never put that key in Flutter, JavaScript, Git, screenshots, or
the browser console.

Set these backend environment variables locally and on Render:

```text
REQUIRE_AUTH=true
SUPABASE_URL=https://dyolfgaabpcibwkphxgo.supabase.co
SUPABASE_ANON_KEY=<the app's publishable key>
SUPABASE_SERVICE_ROLE_KEY=<set privately from Supabase Project Settings>
```

In Render, add them under **cropcare-ai-backend > Environment**. Keep
`SUPABASE_SERVICE_ROLE_KEY` and `OPENAI_API_KEY` marked as secret values. After
changing an environment value, select **Save, rebuild, and deploy**. The public
portal configuration reports only whether privileged access is ready; it never
returns the service-role key to the browser.

Run `docs/supabase-admin-security.sql` once in the Supabase SQL editor.

## Who can access

- `admin`: can manage users, disease guidance, treatments, crops, and diagnoses.
  It cannot approve administrators or change a superadmin.
- `superadmin`: has administrator access and can approve or revoke the `admin`
  role for registered accounts.
- A superadmin role cannot be created from the portal. Only the Supabase project
  owner should bootstrap or replace it using trusted project-owner access.

Keep superadmin access limited to one primary owner and, if required, one
recovery owner. Use separate named accounts, strong unique passwords, email
confirmation, and Supabase MFA when available.

## Bootstrap the first superadmin

1. Use **Create an account** on `/admin` and confirm the account email.
2. Sign in to the Supabase dashboard as the project owner.
3. Open the SQL editor, replace the placeholder email, and run:

```sql
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
  || jsonb_build_object('admin_role', 'superadmin')
where lower(email) = lower('OWNER_EMAIL@example.com');
```

4. Sign out of `/admin` and sign in again so a fresh session is issued.

## Approve an administrator

1. The applicant creates an account and confirms their email.
2. A superadmin signs in and opens **User management**.
3. Verify the applicant's identity and email, then select **Approve admin**.
4. The applicant signs out and signs in again. Their account can now access the
   protected administrator API.
5. Use **Revoke admin** to remove access. Suspension also blocks sign-in.

All approval, revocation, suspension, and record mutation events are written to
the server-only audit table. Changes to app records are visible to users after
pull-to-refresh, reopening the relevant screen, signing in, or reconnecting.