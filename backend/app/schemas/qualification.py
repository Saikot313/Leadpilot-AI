"""Qualification schemas. LLM output is untrusted and validated against these."""
from datetime import datetime
from typing import Annotated, Literal

from pydantic import Field, StringConstraints, field_validator, model_validator

from app.schemas.common import (
    ID_PATTERN,
    CamelModel,
    LeadSource,
    Mode,
    NextAction,
    Priority,
    RequestModel,
    Urgency,
    utcnow,
)

ShortText = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=300)]
SCORE_DISCLAIMER = (
    "Heuristic AI estimate for triage only. It is not a validated prediction of conversion."
)


class BudgetInfo(CamelModel):
    text: str | None = Field(default=None, max_length=200)
    amount_min: float | None = Field(default=None, ge=0)
    amount_max: float | None = Field(default=None, ge=0)
    currency: str | None = Field(default=None, max_length=8)


class ScoreFactor(CamelModel):
    factor: str = Field(min_length=1, max_length=80)
    impact: Literal["positive", "negative", "neutral"] = "neutral"
    note: str = Field(default="", max_length=200)


class LLMQualificationOutput(CamelModel):
    """Exactly what the model must return (snake_case or camelCase accepted)."""

    customer_name: str | None = Field(default=None, max_length=120)
    summary: str = Field(min_length=1, max_length=600)
    requirements: list[ShortText] = Field(default_factory=list, max_length=12)
    budget: BudgetInfo | None = None
    urgency: Urgency = Urgency.UNSPECIFIED
    deadline: str | None = Field(default=None, max_length=120)
    score: int = Field(ge=0, le=100)
    explanation: str = Field(min_length=1, max_length=1200)
    score_factors: list[ScoreFactor] = Field(default_factory=list, max_length=8)
    missing_information: list[ShortText] = Field(default_factory=list, max_length=10)
    follow_up_questions: list[ShortText] = Field(default_factory=list, max_length=6)
    recommended_next_action: NextAction
    needs_human_handoff: bool = False
    handoff_reason: str | None = Field(default=None, max_length=300)
    suggested_followup_message: str = Field(default="", max_length=2000)

    @field_validator("score", mode="before")
    @classmethod
    def _coerce_score(cls, v):
        if isinstance(v, bool):
            raise ValueError("score must be a number")
        if isinstance(v, (int, float)):
            return round(v)
        if isinstance(v, str):
            try:
                return round(float(v.strip()))
            except ValueError as exc:
                raise ValueError("score must be a number") from exc
        return v

    @field_validator(
        "requirements", "score_factors", "missing_information", "follow_up_questions", mode="before"
    )
    @classmethod
    def _none_to_list(cls, v):
        return [] if v is None else v

    @field_validator("urgency", mode="before")
    @classmethod
    def _none_urgency(cls, v):
        return Urgency.UNSPECIFIED if v is None else v

    @model_validator(mode="after")
    def _consistent_handoff(self):
        if self.recommended_next_action == NextAction.HUMAN_HANDOFF:
            self.needs_human_handoff = True
        return self


class QualificationResult(LLMQualificationOutput):
    """Validated output plus backend-derived fields. Stored on the lead document."""

    priority: Priority
    is_heuristic_score: bool = True
    score_disclaimer: str = SCORE_DISCLAIMER
    safety_flags: list[str] = Field(default_factory=list)
    generated_at: datetime = Field(default_factory=utcnow)
    provider: str
    model: str
    mode: Mode = "live"


class UsageInfo(CamelModel):
    """Token counts are None unless the provider reported them. Cost is always an estimate."""

    provider: str
    model: str
    input_tokens: int | None = None
    output_tokens: int | None = None
    total_tokens: int | None = None
    tokens_measured: bool = False
    latency_ms: int | None = None
    estimated_cost_usd: float | None = None
    cost_is_estimate: bool = True
    attempts: int = 1


class QualifyRequest(RequestModel):
    message: str = Field(min_length=1, max_length=5000)
    customer_name: str | None = Field(default=None, max_length=120)
    source: LeadSource | None = None
    lead_id: str | None = Field(default=None, pattern=ID_PATTERN)


class QualifyResponse(CamelModel):
    result: QualificationResult
    usage: UsageInfo
    mode: Mode
    lead_id: str | None = None
    persisted: bool = False
    approval_id: str | None = None


class FollowupDraftOutput(CamelModel):
    """LLM output for a follow-up draft."""

    subject: str = Field(min_length=1, max_length=150)
    body: str = Field(min_length=1, max_length=2000)


class AgentConfig(CamelModel):
    business_name: str = Field(default="", max_length=120)
    business_description: str = Field(default="", max_length=800)
    services: list[ShortText] = Field(default_factory=list, max_length=15)
    ideal_customer: str = Field(default="", max_length=400)
    tone: Literal["professional", "friendly", "concise"] = "professional"
    minimum_budget_usd: float | None = Field(default=None, ge=0)
    handoff_rules: list[ShortText] = Field(default_factory=list, max_length=10)
    custom_instructions: str = Field(default="", max_length=1000)
    monthly_budget_usd: float | None = Field(default=None, ge=0)


class AgentConfigOut(AgentConfig):
    updated_at: datetime | None = None
    updated_by: str | None = None