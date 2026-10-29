# API Contracts

Base path `/api/v1`. JSON uses camelCase. Interactive docs at `/docs` (disabled when `APP_ENV=production`).
Health: `GET /health` (liveness), `GET /health/ready` (database reachable). Both are outside `/api/v1`.

## Conventions

- **Auth:** `Authorization: Bearer <Firebase ID token>`. In demo mode the token is ignored and the user is `demo-user`.
- **Roles:** owner, admin, agent (writers), viewer (read-only). "Managers" are owner and admin.
- **Errors:** always `{"error": {"code", "message", "requestId", "details?"}}`. Codes you will meet: `validation_error`, `unauthorized`,
  `forbidden`, `not_found`, `conflict` variants (`invalid_transition`, `same_status`, `already_decided`, `slot_unavailable`,
  `invalid_booking_state`, `concurrent_update`), `llm_not_configured` (503), `llm_timeout`, `llm_rate_limited`, `llm_invalid_output`,
  `payload_too_large` (413).
- **Lists:** `{"items": [...], "count": n}`.
- **Idempotency:** `eventId` on inquiries and leads; optional `Idempotency-Key` header on manual workflow triggers.

## Endpoints

| Area | Endpoint | Who |
|------|----------|-----|
| Workspaces | `GET /me/workspaces` · `POST /workspaces` · `GET/PATCH /workspaces/{wid}` | any / any / member / manager |
| Members | `GET/POST /workspaces/{wid}/members` · `PATCH/DELETE .../members/{uid}` | member / manager |
| Leads | `GET/POST .../leads` · `GET/PATCH .../leads/{id}` · `POST .../leads/{id}/status` · `GET .../leads/{id}/history` | member / writer |
| AI | `POST .../playground` · `POST .../leads/{id}/qualify` · `POST .../leads/{id}/followup-draft` · `GET/PUT .../agent-config` | writer (PUT: manager) |
| Inquiries | `POST .../inquiries` (app) · `POST /public/inquiries/{wid}` (signed) · `POST /internal/workspaces/{wid}/inquiries` (n8n) | writer / HMAC / secret |
| Workflows | `GET .../workflows` · `GET .../executions[/{id}]` · `POST .../workflows/trigger` · `POST .../executions/{id}/retry` | member / writer |
| Approvals | `GET .../approvals[/{id}]` · `POST .../approvals/{id}/decision` | member / writer |
| Bookings | `GET .../bookings/availability?date=` · `GET/POST .../bookings` · `POST .../{id}/confirm` · `POST .../{id}/cancel` | member / writer |
| Monitoring | `GET .../monitoring/{overview,usage,usage/records,errors,activity,integrations}` | manager |
| Summary | `GET .../daily-summary` | member |

Query filters on `GET .../leads`: `status`, `priority`, `source`, `tag`, `search`, `assignedTo`, `limit` (max 500).

## Qualification result (what the LLM must return, validated by the backend)

```json
{
  "customer_name": null, "summary": "...", "requirements": ["..."],
  "budget": {"text": null, "amount_min": null, "amount_max": null, "currency": null},
  "urgency": "low|medium|high|unspecified", "deadline": null,
  "score": 0, "explanation": "...", "score_factors": [{"factor": "", "impact": "positive|negative|neutral", "note": ""}],
  "missing_information": [], "follow_up_questions": [],
  "recommended_next_action": "send_followup|request_information|book_meeting|human_handoff|nurture|disqualify",
  "needs_human_handoff": false, "handoff_reason": null, "suggested_followup_message": ""
}
```

The stored result adds `priority` (derived: 70+ high, 40-69 medium, below 40 low), `safetyFlags`, `isHeuristicScore`,
`scoreDisclaimer`, `provider`, `model`, `mode`, `generatedAt`. Usage is returned separately; token fields are `null` unless measured.

## Public inquiry webhook (sign on a server, never in the browser)

`POST /api/v1/public/inquiries/{workspaceId}` with headers `X-LeadPilot-Timestamp` (unix seconds, within 5 minutes) and
`X-LeadPilot-Signature` = `hex(HMAC_SHA256(INQUIRY_WEBHOOK_SECRET, "<timestamp>.<raw body>"))`.

```python
import hashlib, hmac, json, time, httpx
secret = "<INQUIRY_WEBHOOK_SECRET>"
body = json.dumps({"message": "Need a website", "customerName": "Visitor", "eventId": "form-123"}).encode()
ts = str(int(time.time()))
sig = hmac.new(secret.encode(), ts.encode() + b"." + body, hashlib.sha256).hexdigest()
httpx.post("https://api.example.com/api/v1/public/inquiries/<workspaceId>", content=body, headers={
    "Content-Type": "application/json", "X-LeadPilot-Timestamp": ts, "X-LeadPilot-Signature": sig})
```

Body fields: `message` (required), `customerName`, `customerEmail`, `customerPhone`, `company`, `source`, `eventId`.
Response: `{leadId, duplicate, status, mode}` only (no AI analysis is exposed publicly).

## Backend to n8n

`POST {N8N_BASE_URL}/webhook/<path>` with headers `X-LeadPilot-Secret` and `Idempotency-Key`, body:

```json
{"executionId": "exec_...", "workspaceId": "...", "workflow": "lead_routing", "idempotencyKey": "...", "mode": "live", "data": {}}
```

Paths: `leadpilot-inquiry-ingestion`, `-ai-qualification`, `-lead-routing`, `-followup-draft`, `-outbound-action`,
`-booking-processing`, `-error-notification`, `-daily-summary`. n8n replies `202`; HTTP 5xx, 429, 408 and timeouts are retried.

## n8n to backend (header `X-LeadPilot-Callback-Secret`)

| Endpoint | Purpose |
|----------|---------|
| `POST /internal/workspaces/{wid}/executions/{id}/callback` | final outcome `{status: success|failed, message}` |
| `POST /internal/workspaces/{wid}/errors` | record a failure `{workflow, message, node?, executionId?, leadId?, retryStatus?}` |
| `POST /internal/workspaces/{wid}/inquiries` | ingest an inquiry |
| `POST /internal/workspaces/{wid}/leads/{id}/qualify` · `/followup-draft` | run AI steps |
| `GET /internal/workspaces/{wid}/bookings/{id}` | read-only, used before sending a reminder |
| `GET /internal/workspaces/{wid}/daily-summary` | daily metrics |