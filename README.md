# HR Request Mini App

A Flutter mobile app for employee HR requests, backed by a Node.js / Express / TypeScript REST API and PostgreSQL through Prisma. Employees submit requests and follow their status; HR reviews pending requests and records a decision.

## Features

- **Employee:** sign in, view a profile, create requests, browse submitted requests, open details, and see Pending / Approved / Rejected status and HR comments.
- **HR:** sign in, browse pending requests, open employee/request details, approve or reject, and optionally leave a comment.

## Stack and structure

- **Backend:** Node.js, Express, TypeScript, PostgreSQL, Prisma, Zod, JWT, bcrypt and Pino; Vitest/Supertest for tests.
- **Mobile:** Flutter, Riverpod, Dio, go_router and flutter_secure_storage.

```text
backend/
  prisma/                 schema, migrations and development seed
  src/
    auth/                 authentication and role middleware
    requests/             request HTTP, business and data access code
    users/                safe user queries
  tests/                  API, security and error handling tests
mobile/
  lib/
    core/                 HTTP, session, routing and shared UI
    features/             authentication, profile, requests and HR review
  test/                   unit, widget and state tests
  test_live/              opt-in real HTTP integration
  tool/                   Windows integration runner
ARCHITECTURE.md
AI_USAGE.md
```

## Prerequisites

- Node.js **22 or later** and npm.
- Docker Desktop with Docker Compose, using Linux containers.
- Flutter **3.47.0 or later**, with its bundled compatible Dart SDK, available on `PATH`.
- Windows PowerShell for the provided live integration runner.
- For Android execution: an Android SDK, compatible JDK, and emulator or device.
- For iOS execution: macOS and Xcode.

SDKs, dependencies and local configuration are not included in the submission. The setup examples below use PowerShell.

The locked `material_ui` and `cupertino_ui` dependencies require Flutter 3.47 and Dart 3.13.

## Backend setup

From the repository root:

```powershell
cd backend
Copy-Item .env.example .env
$jwtSecret = node -e "process.stdout.write(require('node:crypto').randomBytes(48).toString('hex'))"
(Get-Content -Raw .env).Replace('replace-with-a-random-secret-at-least-32-characters', $jwtSecret) | Set-Content -Encoding utf8 .env
npm ci
npm run db:up
npm run prisma:generate
npm run prisma:migrate
npm run prisma:seed
npm run dev
```

On macOS/Linux, use these commands in `backend` instead of the PowerShell environment-file commands, then run the same npm commands above:

```sh
cp .env.example .env
node -e "const fs=require('node:fs'); fs.writeFileSync('.env', fs.readFileSync('.env','utf8').replace('replace-with-a-random-secret-at-least-32-characters', require('node:crypto').randomBytes(48).toString('hex')))"
```

The API is available at `http://localhost:3000/api`. `.env.example` defines the development database on `127.0.0.1:55432`, the separate test database on `127.0.0.1:55433`, and the API port. Keep the connection URLs and Compose port mappings consistent if you change them. The JWT placeholder must be replaced; startup rejects it.

When running multiple checkouts, set a unique `COMPOSE_PROJECT_NAME` before the Docker commands so they use separate containers and volumes. Database ports 55432 and 55433 must still be available.

If API port 3000 is occupied, change `PORT` in `backend/.env` before starting the server. For example, from `backend`:

```powershell
(Get-Content -Raw .env).Replace('PORT=3000', 'PORT=3100') | Set-Content -Encoding utf8 .env
```

Use the selected API port in the URLs and `--dart-define` examples below. The live integration runner selects its own free ports.

To run the compiled backend instead of the development watcher, stop the watcher and run these commands in `backend`:

```powershell
npm run build
npm start
```

### Development users

**Development / assessment credentials only.** The seed creates these accounts with the shared password `DevPassword123!`:

| Role | Employee ID | Email |
|---|---|---|
| Employee 1 | EMP001 | alice@example.com |
| Employee 2 | EMP002 | bob@example.com |
| HR | HR001 | hr@example.com |

The seed is idempotent and preserves existing accounts. It is disabled when `NODE_ENV=production`.

## Mobile setup

In a second terminal, from the repository root:

```powershell
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api
```

`API_BASE_URL` is read centrally through `--dart-define`. Choose the address for the client:

| Client | API base URL |
|---|---|
| Host-based tests, including Windows | `http://127.0.0.1:3000/api` |
| Android emulator | `http://10.0.2.2:3000/api` |
| iOS simulator | `http://localhost:3000/api` |
| Physical device | Development machine LAN IP, for example `http://192.168.1.20:3000/api` |

For example, on an iOS simulator on macOS:

```powershell
flutter run --dart-define=API_BASE_URL=http://localhost:3000/api
```

A physical device must reach the backend over the same network; use a reachable HTTPS endpoint if its platform policy blocks local HTTP. Android permits local cleartext traffic in debug builds only. The repository includes Android/iOS targets; host-based tests need neither a desktop target nor an emulator.

## Testing

In `backend`, after setup:

```powershell
npm run db:test:up
npm run typecheck
npm test
npm run build
npm run format:check
npm audit
```

Backend tests reset the dedicated local database in `TEST_DATABASE_URL`; keep it separate from development data.

In `mobile`:

```powershell
flutter analyze
flutter test
dart format --set-exit-if-changed .
```

For real HTTP integration, use the Windows PowerShell helper `mobile/tool/run_live_integration.ps1`. From the repository root:

```powershell
cd mobile
.\tool\run_live_integration.ps1 -ValidateBackend
```

The runner starts an isolated PostgreSQL container on a dynamic local port, applies migrations and the seed, starts the compiled Express backend, and runs production Flutter networking/repositories/Riverpod code over real HTTP. It stops its backend and removes the temporary database and logs afterward. Token storage alone is simulated in this host test runtime.

The live suite is opt-in. Ordinary `flutter test` does not require a running backend or PostgreSQL.

To stop the development/test Compose services, run `docker compose --profile test down` in `backend`. This preserves the development volume. Add `--volumes` only when you intend to discard that Compose project's database data.

## API overview

| Method | Route | Access |
|---|---|---|
| POST | `/api/auth/login` | Public |
| GET | `/api/me` | Authenticated |
| POST | `/api/requests` | Employee |
| GET | `/api/requests` | Employee, own requests |
| GET | `/api/requests/:id` | Employee, own request |
| GET | `/api/hr/requests` | HR; optional `status` filter |
| GET | `/api/hr/requests/:id` | HR |
| PATCH | `/api/hr/requests/:id/review` | HR |

Login accepts `{email, password}` and returns `{token, tokenType, expiresIn, user}`. Protected requests use `Authorization: Bearer <token>`. Single resources use `{data}`; lists use `{data, pagination}` with `page` and `pageSize` query parameters. The HR client requests `status=PENDING`.

Response examples are in [backend/api-contract.examples.json](backend/api-contract.examples.json). Design decisions and scaling considerations are in [ARCHITECTURE.md](ARCHITECTURE.md).

## Security and limitations

Passwords use bcrypt; JWTs expire and are checked server-side. Current database roles determine access. Employee queries are ownership-scoped, missing/private employee resources share a safe 404, and strict validation rejects privileged-field injection. Ownership, initial status and timestamps come from the server; review actor/time come from authentication and server code. Only one conditional review transition can succeed; repeated/concurrent reviews return 409.

The client stores JWTs through flutter_secure_storage. The API includes login rate limiting, Helmet, configured CORS, and errors/logging that avoid sensitive payloads.

Android build/device execution was not verified because Android SDK/JDK were unavailable in the Windows environment. iOS native compilation requires macOS/Xcode and was not verified. Platform secure-storage behavior was not verified on a device/emulator. The live runner is Windows PowerShell-oriented; these environment limitations do not affect the host API integration checks.
