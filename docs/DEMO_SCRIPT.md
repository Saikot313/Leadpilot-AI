# Demo Script (5 to 7 minutes)

Before you start: backend and app running (see LOCAL_SETUP). State clearly which mode you are in. In demo mode the banner
says so, and AI results are labeled "Demo rules, no AI model" unless you added an LLM key.

## 1. The problem (30 s)
"Agencies lose leads because inquiries are slow to read, score and answer. LeadPilot qualifies them automatically and keeps
a person in control."

## 2. Dashboard (30 s)
Open the dashboard: animated KPIs, pipeline bar, recent leads, pending approvals, today's summary. Point out that the average
score is labeled a heuristic estimate.

## 3. Submit an inquiry (90 s)
**New inquiry -> Submit inquiry.** Paste: *"We need a mobile app with online ordering and a CRM integration. Budget around
$12k, launch within 8 weeks."* Add a name and your own email. Walk through the result panel:
validated and saved, qualified (score, priority, next action), a draft queued for approval, routing workflow status
(Skipped without n8n, Success with it). Say what Skipped means: nothing ran, and the app does not pretend otherwise.

## 4. Lead details (60 s)
Open the lead: the Hero score ring, the explanation and score factors, extracted budget and deadline, missing information,
suggested questions, the draft, and the "Source" block that separates measured values from estimates.

## 5. Safety (60 s)
**AI Playground -> Prompt injection -> Run.** Show the safety callout, the forced human handoff and the score that was not 100.
Explain: customer text is treated as untrusted data, output is schema-validated, priority is computed by the server.

## 6. Human approval (60 s)
**Approvals.** Edit the draft, approve (confirmation dialog), then show the result message. Without n8n: "Approved, but nothing was
sent." With n8n and SMTP: the email arrives and the execution shows Success. Reject a second item to show it is recorded.

## 7. Automation and bookings (45 s)
**Workflows:** catalog, execution history, retry for a failed run. **Bookings:** book a slot, try to double-book it from a
second tab (rejected), confirm, cancel to release.

## 8. Monitoring (45 s)
**Model and cost:** requests, measured tokens (n/a without a provider), estimated cost, budget bar. **Audit logs:** AI actions
filter; no customer text is stored. **Error monitoring:** failures with retry status.

## 9. Close (30 s)
"Backend-authoritative security, Firestore rules, idempotent workflows, human approval for anything customer-facing, and honest
cost tracking." Then name the limitations you know (see README) before anyone asks.

## If something fails live
Stay calm, show the error state (it is a designed screen), and open the Error monitoring screen or backend logs by request ID.