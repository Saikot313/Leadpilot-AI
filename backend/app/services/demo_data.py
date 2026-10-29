"""Demo-mode helpers: rule-based qualifier fallback and seed data. Everything here is labeled demo."""
from __future__ import annotations

import re
from datetime import timedelta

from app.core.config import DEMO_USER_ID, DEMO_WORKSPACE_ID
from app.schemas.common import LeadStatus, NextAction, Urgency, score_to_priority, utcnow
from app.schemas.qualification import (
    AgentConfig,
    BudgetInfo,
    LLMQualificationOutput,
    QualificationResult,
    ScoreFactor,
)
from app.services.firestore_client import DocumentStore

DEMO_NOTICE = "Demo rule-based estimate (keyword rules; no AI model was used)."

_KEYWORDS = (
    "website", "web app", "mobile app", "app", "automation", "seo", "marketing", "chatbot", "crm",
    "design", "development", "ecommerce", "e-commerce", "branding", "integration", "dashboard",
)
_KEYWORD_RE = re.compile(r"\b(?:" + "|".join(re.escape(k) for k in _KEYWORDS) + r")\b", re.IGNORECASE)
_BUDGET_RE = re.compile(
    r"(\$|usd|bdt|৳|€|£)\s?(\d[\d,]*(?:\.\d+)?)\s?(k)?"
    r"|(\d[\d,]*(?:\.\d+)?)\s?(k)?\s?(usd|dollars|bdt|taka|euros?)",
    re.IGNORECASE,
)
_HIGH_URGENCY_RE = re.compile(r"\b(asap|urgent|urgently|immediately|right away|this week)\b", re.IGNORECASE)
_MEDIUM_URGENCY_RE = re.compile(r"\b(soon|next week|next month|this month|few weeks)\b", re.IGNORECASE)
_DEADLINE_RE = re.compile(
    r"\b(within\s+\d+\s+(?:days?|weeks?|months?)"
    r"|by\s+(?:the\s+end\s+of\s+)?(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*(?:\s+\d{1,2})?"
    r"|next\s+(?:week|month|quarter))",
    re.IGNORECASE,
)


def _currency(symbol: str) -> str:
    s = symbol.lower()
    if s in ("$", "usd", "dollars"):
        return "USD"
    if s in ("bdt", "৳", "taka"):
        return "BDT"
    if s.startswith("euro") or s == "€":
        return "EUR"
    if s == "£":
        return "GBP"
    return symbol.upper()


def _parse_budget(message: str) -> BudgetInfo | None:
    m = _BUDGET_RE.search(message)
    if not m:
        return None
    raw = m.group(2) or m.group(4)
    multiplier = 1000 if (m.group(3) or m.group(5)) else 1
    try:
        amount = float(raw.replace(",", "")) * multiplier
    except ValueError:
        return None
    return BudgetInfo(
        text=m.group(0).strip(), amount_min=amount, amount_max=amount,
        currency=_currency(m.group(1) or m.group(6)),
    )


def demo_qualification(message: str, customer_name: str | None) -> LLMQualificationOutput:
    keywords = sorted({k.lower() for k in _KEYWORD_RE.findall(message)})
    budget = _parse_budget(message)
    deadline_match = _DEADLINE_RE.search(message)
    deadline = deadline_match.group(1) if deadline_match else None
    if _HIGH_URGENCY_RE.search(message):
        urgency = Urgency.HIGH
    elif _MEDIUM_URGENCY_RE.search(message):
        urgency = Urgency.MEDIUM
    else:
        urgency = Urgency.UNSPECIFIED

    factors: list[ScoreFactor] = []
    score = 25
    if budget:
        score += 20
        factors.append(ScoreFactor(factor="Budget stated", impact="positive", note=budget.text or ""))
    else:
        factors.append(ScoreFactor(factor="No budget stated", impact="negative", note="Budget is unknown."))
    if urgency == Urgency.HIGH:
        score += 15
        factors.append(ScoreFactor(factor="High urgency", impact="positive", note="Urgency keywords found."))
    elif urgency == Urgency.MEDIUM:
        score += 8
        factors.append(ScoreFactor(factor="Moderate urgency", impact="positive", note="Soft timeline mentioned."))
    if keywords:
        score += min(len(keywords), 3) * 5
        factors.append(ScoreFactor(factor="Clear service keywords", impact="positive", note=", ".join(keywords[:4])))
    else:
        factors.append(ScoreFactor(factor="Vague requirements", impact="negative", note="No service keywords found."))
    if deadline:
        score += 8
        factors.append(ScoreFactor(factor="Deadline mentioned", impact="positive", note=deadline))
    if len(message) > 200:
        score += 7
        factors.append(ScoreFactor(factor="Detailed inquiry", impact="positive", note="Longer, more specific message."))
    if customer_name:
        score += 5
    score = min(score, 95)

    missing = []
    if not budget:
        missing.append("Budget range")
    if not deadline and urgency == Urgency.UNSPECIFIED:
        missing.append("Timeline or deadline")
    if len(keywords) < 2:
        missing.append("More detail on the scope of work")

    if score >= 70:
        action = NextAction.BOOK_MEETING
    elif score >= 40:
        action = NextAction.REQUEST_INFORMATION
    else:
        action = NextAction.NURTURE

    first = (customer_name or "there").split()[0]
    ask = " and ".join(m.lower() for m in missing[:2]) if missing else "a few more details"
    draft = (
        f"Hi {first},\n\nThank you for getting in touch. We would be glad to help. "
        f"To prepare a useful proposal, could you share {ask}? "
        "If it is easier, we can also arrange a short call.\n\nBest regards"
    )
    return LLMQualificationOutput(
        customer_name=customer_name,
        summary=(message[:300] + ("..." if len(message) > 300 else "")),
        requirements=[k.title() for k in keywords][:12],
        budget=budget,
        urgency=urgency,
        deadline=deadline,
        score=score,
        explanation=f"{DEMO_NOTICE} Score is based on stated budget, urgency, keywords, deadline and detail.",
        score_factors=factors[:8],
        missing_information=missing,
        follow_up_questions=[f"Could you share {m.lower()}?" for m in missing][:6],
        recommended_next_action=action,
        needs_human_handoff=False,
        suggested_followup_message=draft,
    )


# ---------------------------------------------------------------------------
# Seed data
# ---------------------------------------------------------------------------
_SAMPLE_LEADS = [
    ("lead_demo_1", "Amina Rahman", "amina@brightcafe.example", "Bright Cafe", "website",
     "We need a website with online ordering and a CRM integration. Budget is around $6k and we want to launch within 6 weeks.",
     LeadStatus.QUALIFIED, 1),
    ("lead_demo_2", "Daniel Okoro", "daniel@northwind.example", "Northwind Logistics", "referral",
     "Urgent: we need a dashboard and automation for dispatch reports, ASAP. Budget $12k.",
     LeadStatus.MEETING_BOOKED, 2),
    ("lead_demo_3", "Sofia Martinez", "sofia@studio-m.example", "Studio M", "social",
     "Looking for branding and a small marketing website sometime next month.",
     LeadStatus.CONTACTED, 3),
    ("lead_demo_4", "Hiro Tanaka", "hiro@example.com", None, "email",
     "Hi, do you do apps?",
     LeadStatus.LOST, 5),
    ("lead_demo_5", "Priya Nair", "priya@greenleaf.example", "GreenLeaf", "website",
     "We want a chatbot for our store and an SEO refresh. Not sure about budget yet.",
     LeadStatus.NEW, 0),
]


def seed_demo_store(store: DocumentStore) -> None:
    now = utcnow()
    wid = DEMO_WORKSPACE_ID
    base = f"workspaces/{wid}"

    store.set(f"users/{DEMO_USER_ID}", {
        "uid": DEMO_USER_ID, "email": "demo@leadpilot.local", "displayName": "Demo User",
        "photoUrl": None, "activeWorkspaceId": wid, "createdAt": now, "updatedAt": now,
    })
    store.set(base, {
        "name": "Demo Workspace", "industry": "Digital agency", "timezone": "Asia/Dhaka",
        "ownerId": DEMO_USER_ID, "isDemo": True, "createdAt": now, "updatedAt": now,
    })
    store.set(f"{base}/members/{DEMO_USER_ID}", {
        "uid": DEMO_USER_ID, "workspaceId": wid, "email": "demo@leadpilot.local",
        "displayName": "Demo User", "role": "owner", "status": "active", "joinedAt": now,
    })
    store.set(f"{base}/settings/agent_config", {
        **AgentConfig(
            business_name="Demo Digital Agency",
            business_description="Web, mobile and automation services for small businesses.",
            services=["Websites", "Mobile apps", "AI automation", "SEO and marketing"],
            ideal_customer="Small and medium businesses with a clear project and budget.",
            minimum_budget_usd=1500,
        ).model_dump(by_alias=True),
        "updatedAt": now, "updatedBy": DEMO_USER_ID,
    })

    for lead_id, name, email, company, source, message, status, days_ago in _SAMPLE_LEADS:
        created = now - timedelta(days=days_ago, hours=2)
        qualification = None
        score = priority = None
        if status != LeadStatus.NEW:
            out = demo_qualification(message, name)
            qualification = QualificationResult(
                **out.model_dump(), priority=score_to_priority(out.score),
                provider="demo-rules", model="keyword-rules", mode="demo", generated_at=created,
            )
            score, priority = qualification.score, qualification.priority
        store.set(f"{base}/leads/{lead_id}", {
            "workspaceId": wid, "customerName": name, "customerEmail": email, "customerPhone": None,
            "company": company, "source": source, "message": message, "tags": ["demo"], "notes": None,
            "status": status, "score": score, "priority": priority, "qualification": qualification,
            "assignedTo": None, "createdBy": DEMO_USER_ID, "eventId": None,
            "createdAt": created, "updatedAt": created, "lastContactedAt": None,
        })
        store.set(f"{base}/leads/{lead_id}/statusHistory/{lead_id}_h0", {
            "fromStatus": None, "toStatus": "new", "changedBy": DEMO_USER_ID,
            "note": "Demo lead created", "createdAt": created,
        })

    lead1 = store.get(f"{base}/leads/lead_demo_1")
    draft = (lead1["qualification"]["suggestedFollowupMessage"]) if lead1 and lead1.get("qualification") else ""
    store.set(f"{base}/approvals/approval_demo_1", {
        "workspaceId": wid, "actionType": "send_followup", "status": "pending",
        "title": "Send follow-up to Amina Rahman",
        "description": "AI-drafted follow-up. Review before anything is sent.",
        "leadId": "lead_demo_1",
        "payload": {"channel": "email", "to": "amina@brightcafe.example",
                    "subject": "Thanks for your inquiry", "body": draft},
        "safetyFlags": [], "requestedBy": "ai", "createdAt": now,
    })