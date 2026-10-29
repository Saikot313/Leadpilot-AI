# LeadPilot n8n Workflows

Eight workflows that automate the lead pipeline. The backend triggers them and n8n calls the backend back.
**They have not been imported or run by the author of this repo's generator. Treat the first import as a test.**

## How the pieces talk

```
Flutter -> FastAPI --POST /webhook/<path> + X-LeadPilot-Secret--> n8n
                  <--POST /api/v1/internal/... + X-LeadPilot-Callback-Secret-- n8n
```

n8n answers **202 accepted** immediately. The backend records that as Success. If a later step fails, n8n calls
`.../executions/{id}/callback` with `failed` and the run turns Failed.

| # | File | Webhook path | Triggered by |
|---|------|--------------|--------------|
| 01 | `01_inquiry_ingestion.json` | `leadpilot-inquiry-ingestion` | Your website form (server-side), signed with the shared secret |
| 02 | `02_ai_lead_qualification.json` | `leadpilot-ai-qualification` | Workflow Center (manual) |
| 03 | `03_lead_routing_logging.json` | `leadpilot-lead-routing` | Backend after every submitted inquiry, and manually |
| 04 | `04_followup_draft_generation.json` | `leadpilot-followup-draft` | Workflow Center (manual) |
| 05 | `05_approval_outbound_actions.json` | `leadpilot-outbound-action` | Backend, only after a human approves a follow-up |
| 06 | `06_booking_processing.json` | `leadpilot-booking-processing` | Backend when a booking is confirmed |
| 07 | `07_error_notification_retry.json` | `leadpilot-error-notification` | Error Trigger and optional webhook |
| 08 | `08_daily_summary_report.json` | `leadpilot-daily-summary` | Schedule (08:00) and Workflow Center |

## Environment variables

Root `.env` (read by `docker-compose.yml`), see `.env.example`:

| Variable | Required | Meaning |
|----------|----------|---------|
| `N8N_ENCRYPTION_KEY` | yes | Encrypts stored credentials. Keep it stable. |
| `N8N_SHARED_SECRET` | yes | Backend to n8n. Must equal `N8N_SHARED_SECRET` in `backend/.env`. |
| `BACKEND_CALLBACK_SECRET` | yes | n8n to backend. Must equal the same variable in `backend/.env`. |
| `N8N_BACKEND_URL` | yes | `http://backend:8080` (backend in compose) or `http://host.docker.internal:8080` (backend on your host). |
| `LEADPILOT_WORKSPACE_ID` | for 07 and 08 schedule | Workspace for scheduled summaries and caught errors. Demo: `demo-workspace`. |
| `OUTBOUND_FROM_EMAIL` | for sending | Sender address. **Empty means nothing is ever sent.** |
| `SUMMARY_TO_EMAIL` | optional | Daily summary recipient. Empty means no email. |

Generate secrets: `python -c "import secrets; print(secrets.token_urlsafe(32))"`.
Use different values for the two secrets. Never commit `.env`.

## Setup

1. Set the variables above in the root `.env` and the two secrets in `backend/.env`.
2. `docker compose up --build`, then open http://localhost:5678 and create the n8n owner account.
3. **Import** each file: *Workflows -> Import from file*. Repeat for all eight.
4. **SMTP credential** (needed by 05, 06, 08): *Credentials -> New -> SMTP*, enter your provider's host, port, user and password.
   Open each *Send email*, *Send confirmation*, *Send reminder* and *Email summary* node and select it.
   Use an app password where your provider supports one.
5. **Error workflow:** in workflows 01 to 06 and 08, open *Settings -> Error workflow* and choose
   *LeadPilot 07 - Error Notification and Retry*.
6. **Team notifications (manual):** nodes named *CONFIGURE ME* (workflows 03 and 07) are placeholders. Replace them with a
   Slack, Teams or email node. Until then no team notification is sent.
7. **Activate** all eight workflows (toggle top right). The backend calls the production URL
   `/webhook/<path>`, which only works for active workflows. The `/webhook-test/` URL is not used.
8. Run the backend with `DEMO_MODE=true` or `false` and open **Admin -> Settings** (Batch 8) or
   **Model and cost** to confirm "n8n automation: configured".

## Test

1. In the app: **New inquiry -> Submit inquiry**. In **Workflows**, the routing run should be **Success**.
   In n8n, *Executions* shows workflow 03.
2. Approve a follow-up in **Approvals**. With SMTP and `OUTBOUND_FROM_EMAIL` set, workflow 05 emails the lead's address
   (use your own address as the lead email while testing). Without them the run turns **Failed** with the reason.
3. Confirm a booking that has a customer email. You get the confirmation immediately and a reminder 24 hours before
   (only if the meeting is more than 24 hours away and the booking is still confirmed).
4. Ingestion from outside (PowerShell):

```powershell
$h = @{ "X-LeadPilot-Secret" = "<N8N_SHARED_SECRET>"; "Content-Type" = "application/json" }
$b = '{"workspaceId":"demo-workspace","customerName":"Test","message":"Need a website, budget $5k, within 4 weeks","eventId":"test-001"}'
Invoke-RestMethod -Method Post -Uri http://localhost:5678/webhook/leadpilot-inquiry-ingestion -Headers $h -Body $b
```

Send it twice: the second call returns the same lead (no duplicate). A wrong secret returns 401.

## Safety properties

- Every webhook checks `X-LeadPilot-Secret` and rejects mismatches with 401. The comparison is a plain string match
  in n8n (not constant-time), so keep n8n off the public internet or behind a reverse proxy.
- IDs from request bodies are validated (`^[A-Za-z0-9_-]{1,128}$`) before they are put in a URL.
- Repeated `Idempotency-Key` values are ignored (last 500 kept per workflow).
- Email recipients and subjects are validated; CR/LF are stripped from subjects.
- Nothing customer-facing runs without a human approval recorded in the backend.

## Known limitations

- If SMTP fails after the backend already marked an approval **Executed**, the execution turns Failed but the approval
  keeps its status. Its message reads "Accepted by the n8n outbound workflow", meaning accepted, not delivered.
- SMTP acceptance is not proof of delivery.
- Only the `email` channel is implemented.
- Idempotency memory lives in n8n workflow static data, which only persists for activated (production) runs.

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| Runs show **Skipped** | `N8N_SHARED_SECRET` is empty in `backend/.env`. |
| Runs show **Failed**: HTTP 404 from n8n | Workflow not **activated**, or path differs. |
| Runs show **Failed**: HTTP 401/403 | The two `N8N_SHARED_SECRET` values differ. |
| n8n logs `access to env vars denied` | `N8N_BLOCK_ENV_ACCESS_IN_NODE` must be `false` (set in compose). |
| Callbacks fail with 401/503 | `BACKEND_CALLBACK_SECRET` differs or is empty in `backend/.env`. |
| Callbacks cannot connect | Wrong `N8N_BACKEND_URL` for how you run the backend. |
| Import error on a node | Your n8n is older or newer than these node versions. Send the exact message. |