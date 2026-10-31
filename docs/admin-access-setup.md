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
PASSWORD_RESET_REDIRECT_URL=cropcareai://auth/reset-password
ADMIN_INVITE_REDIRECT_URL=https://cropcareai-nxn4.onrender.com/admin
ADMIN_AUTH_REDIRECT_URL=https://cropcareai-nxn4.onrender.com/admin
```

In Render, add them under **cropcare-ai-backend > Environment**. Keep
`SUPABASE_SERVICE_ROLE_KEY` and `OPENAI_API_KEY` marked as secret values. After
changing an environment value, select **Save, rebuild, and deploy**. The public
portal configuration reports only whether privileged access is ready; it never
returns the service-role key to the browser.

Run `docs/supabase-admin-security.sql` once in the Supabase SQL editor.
Run `docs/supabase-admin-content-management.sql` once to add the disease
severity and canonical treatment fields used by the card-based library.
Run `docs/supabase-announcements.sql` once to enable administrator-only
posts and discussions, optional all-user announcements, unique admin likes,
and atomic alert fan-out to every profile. The announcement tables have no
`anon` or `authenticated` table grants; only the protected backend can read or
mutate them. Mobile users receive only the generated per-user notification,
whose sender label is `CropCare AI Team`. Notifications arrive through the
app's existing sync path when it opens, reconnects, or refreshes; this project
does not currently configure a closed-app remote push provider such as FCM.

In Supabase **Authentication > URL Configuration**, set the Site URL to
`https://cropcareai-nxn4.onrender.com/admin` and add these exact redirect URLs:
`cropcareai://auth/callback`, `cropcareai://auth/reset-password`, and
`https://cropcareai-nxn4.onrender.com/admin`.
The built-in Supabase sender is suitable for limited testing but is rate-limited;
custom SMTP remains preferable for production delivery.

## Require authenticator-app MFA for administrators

The admin portal requires a Supabase `aal2` session before serving any
administrator API route. On the first administrator sign-in, the portal
enrolls an authenticator-app TOTP factor and displays its QR code and manual
setup key. Later sign-ins require a fresh code from that factor. Ordinary user
sign-in in the CropCare app is unchanged.

Before using the admin portal:

1. In Supabase **Authentication > Multi-Factor Authentication**, allow
   authenticator-app (TOTP) factors.
2. Each administrator installs any standards-compliant authenticator app,
   such as Google Authenticator or Microsoft Authenticator.
3. Deploy the backend and portal changes. Each admin scans the setup QR code
   and verifies one code during their first login; subsequent logins require
   a fresh code.
4. For an existing account, the QR code appears after password sign-in only
   if that account has no verified TOTP factor. If a factor is already enrolled
   but its authenticator is unavailable, the Supabase project owner must remove
   that user's old factor from the Supabase Dashboard before the account can
   enroll a replacement.

Newly registered accounts do not receive a QR during registration. The owner
must first confirm the email and a superadmin must approve the account's admin
role. Then the account can sign in to the portal and enroll its authenticator.

TOTP does not require a paid SMS provider or email delivery service. The
authenticator app generates codes offline. If an administrator loses access
to their authenticator, a project owner must recover the factor through
Supabase; do not disable the backend's `aal2` check to regain access.

The admin portal obtains the enrolled-factor list from the signed-in user's
`/auth/v1/user` response. Supabase does not provide factor listing through
`GET /auth/v1/factors`; that route returns `405 Method Not Allowed`. Factor
enrollment, challenge, verification, and removal use their respective
factor-specific endpoints.

## Who can access

- `admin`: can manage users, disease guidance, treatments, crops, and diagnoses.
  It can view the administrator list but cannot approve administrator requests,
  revoke administrator access, or change a superadmin.
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
2. A superadmin signs in, opens **User management**, and selects **Admins**.
3. Verify the applicant's identity and email, then select **Approve admin**.
4. The applicant signs out and signs in again. Their account can now access the
   protected administrator API.
5. Use **Revoke admin** to remove access. Suspension also blocks sign-in.

All approval, revocation, suspension, and record mutation events are written to
the server-only audit table. Changes to app records are visible to users after
pull-to-refresh, reopening the relevant screen, signing in, or reconnecting.

The **Users** tab contains ordinary app accounts and never offers administrator
approval. The **Admins** tab contains approved administrators and pending
requests created from the admin portal. Administrators can edit allowlisted
profile fields and send Supabase password-recovery email, but cannot set or see
passwords. Email-address changes are initiated by the account owner from a
signed-in CropCare app session and take effect only after Supabase confirmation.

The **Add user** action calls Supabase Auth's invitation endpoint. The invitee
confirms the email through the received link and creates a password on the
hosted CropCare page. The backend stores the supplied name, farm address, and
optional phone in the shared `profiles` row; no password is generated or
visible to an administrator. The role selector defaults to **Non-admin**. Only
a signed-in superadmin can select **Admin** and assign the trusted
`app_metadata.admin_role` value during invitation.