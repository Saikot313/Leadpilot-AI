# Architecture

## Components

| Component | Responsibility | Trusts |
|-----------|----------------|--------|
| Flutter app | UI, local state (Riverpod), calls the backend; reads and writes only conversations and follow-ups in Firestore | Nothing: every rule is re-enforced server-side |
| FastAPI backend | Auth, authorization, validation, LLM calls, schema validation, approvals, bookings, audit, n8n triggers | Firebase ID tokens, its own environment |
| LLM provider | Produces a structured assessment | **Nothing it returns is trusted** |
| n8n | Routing, outbound email, reminders, summaries, error capture | Backend via shared secrets |
| Firestore | Persistence; rules isolate workspaces | Admin SDK (backend) bypasses rules by design |

## Primary flow

```
Inquiry -> validate (Pydantic, size limits) -> save lead (idempotent by eventId)
        -> LLM prompt (customer text fenced as untrusted data)
        -> parse JSON -> validate schema -> derive priority -> scan draft -> injection flags
        -> persist qualification + usage record + audit entry
        -> NEW & score>=40 => QUALIFIED (deterministic rule)
        -> queue approval (follow-up draft or "mark lost")
        -> trigger n8n routing (idempotent) -> record execution
        -> Flutter refreshes -> human approves/rejects -> backend claims atomically -> n8n outbound workflow
```

## Trust boundaries and controls

- **Client to backend:** Bearer ID token verified on every request; workspace membership and role resolved from Firestore;
  Pydantic models reject unknown fields; IDs must match `^[A-Za-z0-9_-]{1,128}$`; 32 KB body limit.
- **LLM output:** parsed, schema-validated, retried on malformed output; the model's own priority label is ignored;
  drafts scanned for links, prices and commitments; a detected injection forces a human handoff.
- **Public webhook:** HMAC-SHA256 over `timestamp.body`, five-minute window, minimal response (no AI output).
- **Backend and n8n:** `X-LeadPilot-Secret` (backend to n8n) and `X-LeadPilot-Callback-Secret` (n8n to backend), different values.
- **Sensitive actions:** only after a recorded human decision. The decision is a compare-and-update on `status == pending`,
  so concurrent approvers cannot trigger two sends.

## Reliability

- Retries with backoff for LLM calls (429, 5xx, timeouts, malformed output) and n8n calls; failures never lose a lead.
- Every workflow run is an `execution` document: Success (accepted), Failed, Skipped (n8n not configured), with latency and attempts.
- n8n answers 202 first and reports later failures through the callback endpoint.
- Idempotency: deterministic IDs derived from `eventId` and idempotency keys; duplicate n8n deliveries are dropped.
- Bookings: one `bookingSlots/<utc-slot>` document per reserved slot, created in a single atomic batch, so double booking is impossible.

## Observability and cost

- Structured JSON logs with a request ID (no customer text, emails or secrets).
- `usage` records: provider, model, **measured** tokens and latency when reported, **estimated** cost from configured prices.
  Missing token data is shown as n/a and excluded from totals; nothing is guessed.
- `activity` is the audit trail (user, AI, n8n, system actors); `errors` feeds Error Monitoring.

## Trade-offs

- A backend-centric design (instead of the client talking to Firestore) keeps secrets, validation and audit in one place,
  at the price of an extra hop and more backend code.
- Demo mode swaps Firestore for an in-memory store behind the same interface, so the whole app runs without accounts.
- n8n handles integrations and delivery; business rules stay in the backend so they are testable.