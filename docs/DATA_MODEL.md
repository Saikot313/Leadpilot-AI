# Data Model (Cloud Firestore)

All business data lives under `workspaces/{workspaceId}`. Timestamps are Firestore timestamps. IDs are strings.
"Backend" means the Admin SDK (bypasses rules); "client" means the Flutter app under the security rules.

| Path | Written by | Key fields |
|------|-----------|-----------|
| `users/{uid}` | client (own doc) / backend | uid, email, displayName, activeWorkspaceId, createdAt, updatedAt |
| `workspaces/{wid}` | backend | name, industry, timezone, ownerId, isDemo, createdAt, updatedAt |
| `workspaces/{wid}/members/{uid}` | backend | uid, workspaceId, email, displayName, role (owner/admin/agent/viewer), status (active/removed), joinedAt |
| `.../leads/{id}` | client (basic fields), backend (status, AI fields) | customerName, customerEmail, customerPhone, company, source, message, tags, notes, status, score, priority, qualification{...}, assignedTo, createdBy, eventId, createdAt, updatedAt, lastContactedAt |
| `.../leads/{id}/statusHistory/{id}` | backend | fromStatus, toStatus, changedBy, note, createdAt |
| `.../conversations/conv_{leadId}` | client | workspaceId, leadId, channel, createdAt, lastMessageAt |
| `.../conversations/.../messages/{id}` | client (create only) | senderType, senderId, senderName, text, isInternal, createdAt |
| `.../followups/{id}` | client | title, notes, dueAt, status (open/done/cancelled), leadId, leadName, createdBy, completedAt |
| `.../approvals/{id}` | backend | actionType, status (pending/approved/rejected/executed/failed), title, leadId, payload, safetyFlags, decidedBy, decidedAt, decisionNote, executionId, resultMessage |
| `.../bookings/{id}` | backend | leadId, customerName, customerEmail, startAt, endAt, durationMinutes, status, slotKeys, confirmedBy, cancelledReason |
| `.../bookingSlots/{utcSlotKey}` | backend | bookingId, startAt. **Existence = slot taken** (atomic double-booking guard) |
| `.../executions/{id}` | backend | workflow, status, leadId, relatedId, attempts, retryCount, idempotencyKey, startedAt, finishedAt, latencyMs, errorMessage, responseSummary |
| `.../usage/{id}` | backend | kind, provider, model, success, errorCode, inputTokens, outputTokens, tokensMeasured, latencyMs, estimatedCostUsd, createdAt |
| `.../activity/{id}` | backend | actorType (user/ai/system/n8n), actorId, action, entityType, entityId, summary, metadata (no customer text), createdAt |
| `.../errors/{id}` | backend | source, code, message, workflow, executionId, leadId, retryStatus, createdAt |
| `.../settings/agent_config` | backend | businessName, services, tone, minimumBudgetUsd, handoffRules, customInstructions, monthlyBudgetUsd |

## Rules summary (`firebase/firestore.rules`)

- Members read their workspace's data; non-members read nothing.
- Clients may create and edit basic lead fields, conversations, notes and follow-ups (owner, admin, agent), never `status`,
  `qualification`, `score`, `priority`, `workspaceId`, `createdBy` or `eventId`.
- Approvals, bookings, executions, usage, activity, errors, settings and membership are not writable by clients.
- Usage and activity are readable by owners and admins only (the backend serves monitoring data anyway).
- `integrations/{id}` is reserved for non-secret settings; the current code does not use it. No credentials are stored in Firestore.

## Indexes

`firebase/firestore.indexes.json` defines composite indexes for the filtered queries and the collection-group exemption on
`members.uid` used by `GET /me/workspaces`. Deploy with `firebase deploy --only firestore`.