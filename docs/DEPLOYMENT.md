# Deployment

Nothing here has been deployed by the author of these files. **Steps marked (you) need your own accounts and credentials.**
Do not claim a deployment until you have done it and checked `/health`.

## Production checklist

- `APP_ENV=production`, `DEMO_MODE=false` (the app refuses to start otherwise), `FIREBASE_PROJECT_ID` set.
- `CORS_ORIGINS` limited to your real web origins (native apps need no CORS).
- Distinct random values for `N8N_SHARED_SECRET`, `BACKEND_CALLBACK_SECRET`, `INQUIRY_WEBHOOK_SECRET`.
- LLM key and prices set; Firestore rules and indexes deployed.
- HTTPS everywhere. Docs and OpenAPI are disabled automatically in production.
- Rate limiting is **not** built in: put the API behind a gateway or proxy that limits requests.

## Option A: Google Cloud Run (backend) (you)

```powershell
gcloud auth login
gcloud config set project <PROJECT_ID>
gcloud services enable run.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com

# Secrets (once)
echo -n "<value>" | gcloud secrets create GEMINI_API_KEY --data-file=-
# repeat for N8N_SHARED_SECRET, BACKEND_CALLBACK_SECRET, INQUIRY_WEBHOOK_SECRET

cd backend
gcloud run deploy leadpilot-api --source . --region <REGION> --allow-unauthenticated `
  --set-env-vars APP_ENV=production,DEMO_MODE=false,FIREBASE_PROJECT_ID=<PROJECT_ID>,LLM_PROVIDER=gemini,GEMINI_MODEL=gemini-2.0-flash,N8N_BASE_URL=https://<your-n8n-host>,CORS_ORIGINS=https://<your-web-origin> `
  --set-secrets GEMINI_API_KEY=GEMINI_API_KEY:latest,N8N_SHARED_SECRET=N8N_SHARED_SECRET:latest,BACKEND_CALLBACK_SECRET=BACKEND_CALLBACK_SECRET:latest,INQUIRY_WEBHOOK_SECRET=INQUIRY_WEBHOOK_SECRET:latest `
  --timeout 300
```

- Do **not** set `GOOGLE_APPLICATION_CREDENTIALS`: Cloud Run uses its service account (application default credentials).
  Grant that service account the **Cloud Datastore User** role and let it verify Firebase tokens (same project).
- `--allow-unauthenticated` is required because the app and n8n call it directly; authentication is done by the API itself.
- Health check path: `/health`. View logs with `gcloud run services logs read leadpilot-api`.
- Cloud Run cannot reach n8n on a private network, so n8n needs a public HTTPS address (Option B).

## Option B: VPS with Docker (n8n, or the whole stack) (you)

1. Provision a Linux VPS, install Docker, point a DNS name at it.
2. Copy the repo, create `.env` and `backend/.env` (never commit them), set `N8N_WEBHOOK_URL=https://<your-n8n-host>/`,
   `N8N_HOST=<your-n8n-host>`, and `N8N_BACKEND_URL` to the public backend URL if the backend is on Cloud Run.
3. Run `docker compose up -d --build`.
4. Put a TLS reverse proxy in front. Example Caddyfile (exposes n8n webhooks only, not the editor):

```
n8n.example.com {
    @webhooks path /webhook/*
    handle @webhooks {
        reverse_proxy localhost:5678
    }
    handle {
        respond "Not found" 404
    }
}
```

   Reach the n8n editor through an SSH tunnel or VPN instead of the public internet.
5. Import and activate the workflows as described in `n8n/README.md`.

## Flutter release builds (you)

```powershell
cd mobile
flutter build apk --release --dart-define=DEMO_MODE=false --dart-define=API_BASE_URL=https://<your-api-host>
flutter build web --release --dart-define=DEMO_MODE=false --dart-define=API_BASE_URL=https://<your-api-host>
```

Android release builds need the `INTERNET` permission in the main manifest. iOS needs your signing setup. Firebase config
comes from `flutterfire configure`.

## Operations

- Health: `GET /health` (liveness) and `GET /health/ready` (database). Every response carries `X-Request-ID`; logs are JSON
  with the same `requestId`.
- Diagnosis order: Error monitoring screen, then backend logs by request ID, then n8n *Executions*.
- Rotate secrets by updating the secret store and the n8n environment together, then restart both.
- Back up Firestore with scheduled exports (your own Google Cloud setup).