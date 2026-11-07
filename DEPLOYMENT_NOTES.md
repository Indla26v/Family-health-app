# Deployment notes — Family Health (cloud web + offline-first phone sync)

_Prepared 9 Oct 2026._

## Status

| Piece | State |
|---|---|
| Database | Neon project **`family-health`** (id `morning-tooth-61876432`, AWS Singapore `aws-ap-southeast-1`, closest region to India). This is the empty project you created on 8 Oct; I reused it rather than make a duplicate. Tables are created by the app's migrations on the first request. |
| Vercel project | **`family-health-web`** (id `prj_KELRAM3ZASVZvcOel66QAVmAUsn1`). Functions region `sin1` (Singapore). Vercel Authentication applies to preview deployments only, so the production URL is reachable by the phone app; the app does its own sign-in. |
| Env vars on Vercel | Set: `DATABASE_URL`, `AUTH_SECRET`, `ADMIN_EMAIL`, `ADMIN_PASSWORD`, `APP_TZ`. |
| **First deploy** | **Not done yet.** My sandbox can't log in to the Vercel CLI and can't reach Flutter, and computer use was off, so the code couldn't be uploaded from here. Run the commands under "Deploy" below. |
| Live URL | `https://family-health-web-hazel.vercel.app` (`family-health-web.vercel.app` belongs to someone else; never point the phone app there). |

## Deploy (run once from your PC)

```powershell
cd "C:\Projects\Health app\family-health-web"
npm install
npm test                                  # 29 tests, including the auth/authz tests
npx vercel link --project family-health-web --yes
npx vercel deploy --prod
```

After it finishes:

1. Open `https://<your-url>/api/health`. It should return `{"ok":true,...}`.
2. Open `https://<your-url>/api/v1/members`. It should return **401** `{"error":"Not signed in"}`.
3. Sign in at `https://<your-url>/login` (see "First sign-in"). The first request creates the tables in Neon.

## Environment variables (names only — values are in Vercel, never in source)

| Name | Purpose |
|---|---|
| `DATABASE_URL` | Neon pooled connection string (`…-pooler…`, `sslmode=require`). |
| `AUTH_SECRET` | Signs the 15-minute API access tokens (JWT, HS256). At least 32 random characters. `JWT_SECRET` also works. |
| `ADMIN_EMAIL` | Bootstrap owner, used only while the database has no accounts. Set to your email. |
| `ADMIN_PASSWORD` | Bootstrap owner's first password. |
| `APP_TZ` | `Asia/Kolkata`. Sets medicine times and "today". Vercel reserves `TZ`, so the app reads `APP_TZ`. |
| optional `FAMILY_NAME`, `SECURE_COOKIES`, `RUN_MIGRATIONS` | See `family-health-web/.env.example`. |

## First sign-in

- Vercel → project **family-health-web** → Settings → Environment Variables → **`ADMIN_PASSWORD`** → reveal the value.
- Sign in at `/login` with your email and that password.
- Then go to **Settings → Your sign-in** and change the password. Changing `ADMIN_PASSWORD` later has no effect, because it's only used while no accounts exist.
- Add your own profile under **Family → Add family member**.

## How auth works (web + API)

- **Library choice:** the app already had bcrypt + database sessions, so I kept those and added `jose` for JWTs. No new auth framework.
- **Passwords:** bcrypt, cost 12. Passwords and tokens are never logged.
- **Web:** random session token in an `httpOnly`, `SameSite=Lax` cookie. The cookie is `Secure` automatically on Vercel. Only its SHA-256 hash is stored in Postgres. Server actions get Next.js's built-in Origin check. Cookie-authenticated API writes must come from the same origin (CSRF guard in `src/lib/api.ts`).
- **Phone/API:** `POST /api/auth/login` returns a 15-minute access token (JWT) and a 30-day refresh token.
  - The refresh token is stored hashed and **rotates** on every `POST /api/auth/refresh`.
  - Reusing an old refresh token revokes the whole chain.
  - `POST /api/auth/logout` revokes it.
  - Changing your password signs out every web session and phone.
- **Other endpoints:** `GET /api/auth/me` returns the account. `POST /api/auth/accept-invite` turns an invite into an account.
- **Rate limit:** 5 failed sign-ins per email (and 20 per IP) within 15 minutes cause a 1-minute block. The counter is stored in Postgres, so it works across serverless instances.
- **Error messages:** generic, so they never reveal whether an email exists.
- **Public routes:** only `/api/health`, login, refresh, logout and accept-invite. Every other `/api/*` route goes through one guard (`guard()` in `src/lib/api.ts`). It answers **401** when you're not signed in and **403** when your role isn't allowed. Records of another family answer **404**.

## Roles and families (authorization)

- A **family** (household) has user accounts and health profiles. Reports, parsed values, medicines, readings, appointments and check-ups belong to a profile, and through it to the family.
- Every query is filtered by the caller's `familyId`, so changing an id in a URL can't reach another family's records.

| Role | Can do |
|---|---|
| **owner** | Everything, including adding/removing admins and "Delete everything". Exactly one per family: the first account. |
| **admin** | Manage people, invites and member/viewer roles. Delete data (profiles, reports, medicines, appointments). |
| **member** | Add/edit family members, upload/edit reports and values, log readings and doses. Can't delete whole records or manage people. |
| **viewer** | Read-only. |

The old "Admin / Full app / Simple mode" setting still exists, but it now only chooses the app's **mode** (screen layout), not permissions.

**Behaviour change:** every role can now see the whole family. Before, "Full app" users saw only their own profile.

### Adding people (no open sign-up)

- **Invite (recommended):**
  - Go to Settings → **People & access** → Invite someone. Enter their email and role, and optionally link an existing profile.
  - You get a one-time link `https://<your-url>/signup?token=…`, valid 7 days. Send it to the person. They choose a password.
  - The same is available as `POST /api/v1/invites` (owner/admin).
- **Change a role:** Settings → People & access, or `PATCH /api/v1/users/:id {"access":"member"}`.
- The old **Family → Sign-in** form still works for owners/admins. It creates a username login with the member role.

## REST API (all require `Authorization: Bearer <accessToken>` or the web cookie)

- `GET/POST /api/v1/members`, `GET/PATCH/DELETE /api/v1/members/:id`
- `GET/POST /api/v1/reports[?memberId=]`, `GET/PATCH/DELETE /api/v1/reports/:id` (the report together with its parsed values)
- `GET/PUT /api/v1/files/:reportId` (the original file; PUT takes the raw bytes with `Content-Type` pdf/jpeg/png)
- `GET/POST /api/v1/results?reportId=`, `PATCH/DELETE /api/v1/results/:id`
- `POST /api/v1/uploads` (multipart `memberId` + `files`: stores, reads and parses reports, same as the web uploader)
- `GET /api/v1/users`, `PATCH /api/v1/users/:id`, `GET/POST /api/v1/invites` (owner/admin)
- `GET /api/v1/sync?since=<cursor>`, `POST /api/v1/sync` (see below)
- Existing: `/api/upload`, `/api/files/:docId`, `/api/backup` (now family-scoped and guarded)

## Claude connector (MCP)

- **Endpoint:** a read-only MCP server at `/api/mcp/<secret>` (Streamable HTTP, stateless, so no extra services are needed).
- **Creating a link:** each user creates their own link under **Settings → Connect Claude**, then adds it in Claude → Settings → Connectors → Add custom connector.
- **What a link can see:** the same family records that user can see. It can't write anything.
- **Storage:** the `mcp_tokens` table (migration `0005_mcp_tokens.sql`, applied automatically). It holds only SHA-256 hashes.
- **Revocation:** "Replace link", "Turn off" and password changes (including a reset by email) all revoke the old link.
- **Logs:** the secret is part of the URL path, so Vercel's request logs (visible to the project team only) can contain it. Replace the link if that's a concern.
- **Tools:** list_family_members, get_health_summary, list_lab_tests, get_lab_results, list_reports, get_report, get_vitals, get_medicines, get_medicine_adherence, get_appointments, get_checkups.

## How phone sync works (offline-first)

The phone still keeps **everything locally**, in the same SharedPreferences JSON store as before. It works fully offline. Sync runs in the background (`lib/services/sync_service.dart`):

- **Tracking**
  - On every local save, each record is converted to the server's shape and hashed.
  - A changed record gets `updatedAt = now` (UTC) and a "dirty" flag.
  - Deleting a record the server already has creates a tombstone.
  - This bookkeeping is saved with the data, under `sync`.
- **Pull**
  - `GET /api/v1/sync?since=cursor` returns every row and deletion of your family with a newer server change number (`rev`).
  - A pulled row replaces the local one, unless the local copy is dirty and newer.
- **Push**
  - Dirty rows and tombstones go to `POST /api/v1/sync`.
  - The server applies **last-write-wins** on `updatedAt`. If its copy is newer, it returns it and the phone adopts it.
  - Deletes that need owner/admin are refused for members, and the record is restored.
- **Files:** original report files are uploaded once per report (`PUT /api/v1/files/:id`). Files over 4 MB stay on the phone only, because of Vercel's request size limit.
- **When it runs:** at app start, when the app comes back to the foreground, a few seconds after edits, and every 5 minutes. It can also be run manually under Settings → Cloud account & sync.
- **Offline:** if the server can't be reached, changes simply wait ("Offline · N waiting" in the app bar).
- **Server side:** Postgres triggers keep `rev`/`updated_at` current and write tombstones, so edits made on the web reach phones too.

## Phone sign-in and tokens

- First start shows **Sign in**, with a "Use offline only" option.
  - Signing in on a fresh phone downloads the family's records before setup.
  - Signing in on a phone that already has data uploads that data into the family.
  - Signing in to a *different* family first clears the other family's records from the phone. They stay on the server.
- **Token storage:** in `flutter_secure_storage` (Android Keystore / Windows Credential Manager), not in the data file.
- **Token handling:** the access token goes on every API call. After a 401 the app refreshes automatically, once.
- **When the session expires:** the app keeps working offline as the last signed-in user. Settings shows "Sign in again", and sync resumes after signing in.
- **IDs:** records created by older versions had short local ids. They're converted to UUIDs on the first sign-in, and new records always get UUIDs.

## Running the phone app against the API

```powershell
cd "C:\Projects\Health app"
flutter pub get                 # adds flutter_secure_storage + http
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=https://<your-url>
```

Without the `--dart-define`, the sign-in screen defaults to `https://family-health-web-hazel.vercel.app`. Tap **Server address…** on the sign-in screen to change it.

I added the `INTERNET` permission to `AndroidManifest.xml`, which release builds need.

## Git history

The remote tools can't write inside `.git` folders, so the history is delivered as bundles in `_restore\`.

- `_restore\flutter-app-snapshot.bundle` and `_restore\web-app-snapshot.bundle` are the restore points taken before any change.
- `_restore\flutter-app-work.bundle` and `_restore\web-app-work.bundle` contain the snapshot plus the work commits.

To attach the history without touching your files:

```powershell
cd "C:\Projects\Health app"
git init -b main
git fetch .\_restore\flutter-app-work.bundle main
git reset FETCH_HEAD            # moves HEAD/index only; your files stay as they are

cd family-health-web            # already a repo (branch master)
git fetch ..\_restore\web-app-work.bundle master
git reset FETCH_HEAD
```

Then `git status` shows anything that differs from the commits. Two files I couldn't read are expected to show as untracked:

- `family-health-web\src\app\(app)\health\[memberId]\test\[key]\page.tsx`
- `android\app\src\main\kotlin\…\MainActivity.kt`

They're nested too deep for the remote tools. Add them with `git add`.

## Remaining TODOs

- **Run the first Vercel deploy** (commands above) and check `/api/health` and the 401 check.
- **Run `flutter pub get`, `flutter analyze` and `flutter test` on your PC.** Flutter's servers are blocked from my sandbox, so the Dart changes are written but not compiled. They include new sync tests in `test/sync_test.dart`. Please send me any analyzer errors.
- Change the bootstrap owner's password after the first sign-in.
- **File size limit:** report files over ~4 MB can't be uploaded on Vercel (request body limit). Use direct-to-storage uploads (Neon object storage or Vercel Blob) if this matters.
- **Viewers on the phone:** a viewer's local edits stay on their phone, because the server refuses writes. The phone UI doesn't hide edit buttons for viewers yet.
- A bootstrap owner starts with no linked profile. There's no "this is me" link in the web UI yet; an invite can link a profile.
- **Duplicates:** if the same person was set up separately on the phone and on the web before syncing, they appear twice. Remove one under Family.
- OCR for scanned reports, push notifications for missed doses, and a native home-screen widget are still not built (as before).
