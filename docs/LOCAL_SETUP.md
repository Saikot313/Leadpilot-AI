# Local Setup

Prerequisites: Python 3.11+, Flutter 3.22+ (Dart 3.4+), Git. Optional: Docker Desktop, Node (Firebase CLI), your own Firebase,
LLM and SMTP accounts. Commands are for Windows PowerShell.

## 1. Demo mode (no accounts)

```powershell
cd backend
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env        # DEMO_MODE=true by default
uvicorn app.main:app --reload --port 8080
```

Check http://localhost:8080/health and http://localhost:8080/docs.

```powershell
cd mobile
flutter create --org com.leadpilot --project-name leadpilot_ai --platforms android,ios,web .   # first time only
# replace pubspec.yaml / analysis_options.yaml with the repo versions, delete lib/main.dart and test/widget_test.dart
flutter pub get
flutter analyze
flutter run -d chrome --web-port 5000        # the port must be listed in CORS_ORIGINS
```

Android emulator: `flutter run` (the app reaches the host at `http://10.0.2.2:8080`). Override with
`--dart-define=API_BASE_URL=http://<host>:8080`.

## 2. Tests

```powershell
cd backend ; pytest -q
cd mobile  ; flutter test
```

## 3. Add a real LLM (optional)

In `backend/.env` set `GEMINI_API_KEY` (or `LLM_PROVIDER=openai` and `OPENAI_API_KEY`) and the two price variables
`LLM_INPUT_PRICE_PER_1M` and `LLM_OUTPUT_PRICE_PER_1M` (check your provider's pricing page). Restart the backend.
The Playground now shows measured tokens and latency and an **estimated** cost.

## 4. n8n automation

See [n8n/README.md](../n8n/README.md). Short version: set the two different secrets in `.env` and `backend/.env`, run
`docker compose up n8n` (or the whole stack), import and activate the eight workflows, add an SMTP credential.
Backend on your host with n8n in Docker: `N8N_BASE_URL=http://localhost:5678` (backend env) and
`N8N_BACKEND_URL=http://host.docker.internal:8080` (root `.env`).

## 5. Live mode (Firebase)

1. Follow [firebase/README.md](../firebase/README.md): create the project, enable Email/Password, deploy rules and indexes,
   save the service account as `secrets/firebase-sa.json`.
2. `backend/.env`: `DEMO_MODE=false`, `FIREBASE_PROJECT_ID=<id>`, `GOOGLE_APPLICATION_CREDENTIALS=<absolute path>`.
3. `cd mobile ; flutterfire configure` (replaces `lib/firebase_options.dart`).
4. Run the app with `flutter run --dart-define=DEMO_MODE=false` (or `--dart-define-from-file=.env`).
5. Sign up, create a workspace, and use the app. The first account becomes the workspace owner.

## 6. Docker for the whole stack

```powershell
copy .env.example .env ; copy backend\.env.example backend\.env
mkdir secrets            # put firebase-sa.json here first (Docker creates a directory if the file is missing)
docker compose up --build
```

## Troubleshooting

| Symptom | Cause and fix |
|---------|---------------|
| App shows "Can't reach the server" | Backend not running, or wrong `API_BASE_URL`; on web, the app port is missing from `CORS_ORIGINS` |
| Backend exits on startup with a settings error | `DEMO_MODE=false` needs `FIREBASE_PROJECT_ID`; production forbids demo mode; slot minutes must divide 60 |
| 503 `llm_not_configured` | `DEMO_MODE=false` and no LLM key set |
| Runs show Skipped | `N8N_SHARED_SECRET` is empty in `backend/.env` |
| Firestore `FAILED_PRECONDITION` index error | Deploy `firestore.indexes.json` |
| Release Android build cannot reach the network | Add `<uses-permission android:name="android.permission.INTERNET"/>` to `android/app/src/main/AndroidManifest.xml` |
| Android blocks `http://` traffic | Use HTTPS, or add `android:usesCleartextTraffic="true"` to the debug manifest while developing |