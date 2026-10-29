"""Qualification pipeline. LLM output is untrusted: parsed, schema-validated and post-processed here."""
from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass

from pydantic import BaseModel, ValidationError

from app.core.config import Settings
from app.core.errors import (
    AppError,
    RateLimitedError,
    ServiceUnavailableError,
    UpstreamError,
)
from app.core.logging import get_logger
from app.schemas.common import ActorType, NextAction, UsageKind, score_to_priority, utcnow
from app.schemas.lead import LeadOut
from app.schemas.qualification import (
    AgentConfig,
    AgentConfigOut,
    FollowupDraftOutput,
    LLMQualificationOutput,
    QualificationResult,
    UsageInfo,
)
from app.services.audit_service import log_activity
from app.services.cost_estimator import estimate_for_settings
from app.services.demo_data import demo_qualification
from app.services.firestore_client import DocumentStore, new_id
from app.services.llm.base import LLMCallError, LLMProvider
from app.services.llm.gemini_provider import GeminiProvider
from app.services.llm.openai_provider import OpenAIProvider
from app.services.llm.prompts import (
    build_followup_system_prompt,
    build_followup_user_prompt,
    build_qualification_system_prompt,
    build_qualification_user_prompt,
    detect_injection,
)

logger = get_logger("leadpilot.qualification")

_LINK_RE = re.compile(r"https?://|www\.", re.IGNORECASE)
_PRICE_RE = re.compile(r"[$€£৳]\s?\d|\b\d[\d,.]*\s?(usd|dollars|bdt|taka|euros?)\b", re.IGNORECASE)
_COMMIT_RE = re.compile(r"\b(guarantee|guaranteed|promise|free of charge|100%)\b", re.IGNORECASE)


# ---------- Agent configuration ----------
def _config_path(workspace_id: str) -> str:
    return f"workspaces/{workspace_id}/settings/agent_config"


def get_agent_config(store: DocumentStore, workspace_id: str) -> AgentConfigOut:
    doc = store.get(_config_path(workspace_id))
    return AgentConfigOut.model_validate(doc) if doc else AgentConfigOut()


def save_agent_config(
    store: DocumentStore, workspace_id: str, config: AgentConfig, actor_id: str
) -> AgentConfigOut:
    store.set(
        _config_path(workspace_id),
        {**config.model_dump(by_alias=True), "updatedAt": utcnow(), "updatedBy": actor_id},
    )
    log_activity(
        store, workspace_id, actor_type=ActorType.USER, actor_id=actor_id,
        action="agent_config.updated", entity_type="agent_config", summary="Agent configuration updated",
    )
    return get_agent_config(store, workspace_id)


# ---------- LLM plumbing ----------
def get_provider(settings: Settings) -> LLMProvider:
    if settings.llm_provider == "gemini":
        return GeminiProvider(settings.llm_api_key, settings.llm_model, settings.llm_timeout_seconds)
    return OpenAIProvider(settings.llm_api_key, settings.llm_model, settings.llm_timeout_seconds)


@dataclass
class _Attempts:
    attempts: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    tokens_measured: bool = False
    latency_ms: int = 0


class _LLMFailure(Exception):
    def __init__(self, error: AppError, acc: _Attempts):
        super().__init__(error.message)
        self.error = error
        self.acc = acc


def extract_json(text: str) -> dict:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = re.sub(r"^```(?:json)?\s*|\s*```$", "", cleaned, flags=re.IGNORECASE)
    start, end = cleaned.find("{"), cleaned.rfind("}")
    if start == -1 or end <= start:
        raise ValueError("No JSON object in model output")
    data = json.loads(cleaned[start : end + 1])
    if not isinstance(data, dict):
        raise ValueError("Model output is not a JSON object")
    return data


def _map_llm_error(exc: LLMCallError) -> AppError:
    if exc.code == "rate_limited":
        return RateLimitedError("The AI provider is rate limiting requests. Try again shortly.", code="llm_rate_limited")
    if exc.code == "timeout":
        return UpstreamError("The AI provider timed out.", code="llm_timeout")
    if exc.code == "auth_failed":
        return UpstreamError("The AI provider rejected the server credentials.", code="llm_auth_failed")
    return UpstreamError("The AI provider request failed.", code="llm_error")


def _run_llm(
    provider: LLMProvider, settings: Settings, system: str, user: str, schema: type[BaseModel], acc: _Attempts
) -> BaseModel:
    last_error: AppError | None = None
    total = settings.llm_max_retries + 1
    for attempt in range(total):
        acc.attempts += 1
        try:
            resp = provider.generate_json(system, user)
        except LLMCallError as exc:
            last_error = _map_llm_error(exc)
            if not exc.retryable:
                break
            if attempt < total - 1:
                time.sleep(min(0.5 * 2**attempt, 4))
            continue

        acc.latency_ms += resp.latency_ms or 0
        if resp.input_tokens is not None or resp.output_tokens is not None:
            acc.tokens_measured = True
            acc.input_tokens += resp.input_tokens or 0
            acc.output_tokens += resp.output_tokens or 0
        try:
            return schema.model_validate(extract_json(resp.text))
        except (ValueError, ValidationError):
            logger.warning("llm_invalid_output", extra={"attempt": attempt + 1})
            last_error = UpstreamError(
                "The AI returned a response that did not match the required format.", code="llm_invalid_output"
            )
            if attempt < total - 1:
                time.sleep(min(0.5 * 2**attempt, 4))
    raise _LLMFailure(last_error or UpstreamError("The AI request failed."), acc)


def _record_usage(
    store: DocumentStore,
    settings: Settings,
    *,
    workspace_id: str,
    kind: UsageKind,
    provider: str,
    model: str,
    success: bool,
    error_code: str | None,
    lead_id: str | None,
    requested_by: str | None,
    acc: _Attempts,
) -> UsageInfo:
    in_t = acc.input_tokens if acc.tokens_measured else None
    out_t = acc.output_tokens if acc.tokens_measured else None
    total = (in_t + out_t) if acc.tokens_measured else None
    info = UsageInfo(
        provider=provider,
        model=model,
        input_tokens=in_t,
        output_tokens=out_t,
        total_tokens=total,
        tokens_measured=acc.tokens_measured,
        latency_ms=acc.latency_ms or None,
        estimated_cost_usd=estimate_for_settings(settings, in_t, out_t),
        cost_is_estimate=True,
        attempts=max(acc.attempts, 1),
    )
    try:
        store.set(
            f"workspaces/{workspace_id}/usage/{new_id()}",
            {
                "workspaceId": workspace_id, "kind": kind, "provider": provider, "model": model,
                "success": success, "errorCode": error_code, "leadId": lead_id, "requestedBy": requested_by,
                "inputTokens": in_t, "outputTokens": out_t, "totalTokens": total,
                "tokensMeasured": acc.tokens_measured, "latencyMs": info.latency_ms,
                "estimatedCostUsd": info.estimated_cost_usd, "costIsEstimate": True,
                "attempts": info.attempts, "createdAt": utcnow(),
            },
        )
    except Exception:  # noqa: BLE001
        logger.exception("usage_record_failed")
    return info


def _scan_draft(text: str) -> list[str]:
    flags = []
    if _LINK_RE.search(text):
        flags.append("contains_link")
    if _PRICE_RE.search(text):
        flags.append("mentions_price")
    if _COMMIT_RE.search(text):
        flags.append("commitment_language")
    return flags


def _finalize(output: LLMQualificationOutput, extra_flags: list[str], provider: str, model: str, settings: Settings) -> QualificationResult:
    flags = list(extra_flags) + _scan_draft(output.suggested_followup_message)
    result = QualificationResult(
        **output.model_dump(),
        priority=score_to_priority(output.score),  # backend-derived; the model's own label is never trusted
        safety_flags=flags,
        provider=provider,
        model=model,
        mode=settings.mode,
    )
    if "possible_prompt_injection" in flags:
        result.needs_human_handoff = True
        result.recommended_next_action = NextAction.HUMAN_HANDOFF
        result.handoff_reason = "The message contains text that looks like an attempt to instruct the AI."
    return result


# ---------- Public API ----------
def qualify_message(
    store: DocumentStore,
    settings: Settings,
    *,
    workspace_id: str,
    message: str,
    customer_name: str | None = None,
    source=None,
    requested_by: str | None = None,
    lead_id: str | None = None,
    kind: UsageKind = UsageKind.QUALIFICATION,
) -> tuple[QualificationResult, UsageInfo]:
    config = get_agent_config(store, workspace_id)
    flags = ["possible_prompt_injection"] if detect_injection(message) else []
    acc = _Attempts()
    provider_name, model_name = settings.llm_provider, settings.llm_model

    if settings.llm_configured:
        provider = get_provider(settings)
        try:
            output = _run_llm(
                provider,
                settings,
                build_qualification_system_prompt(config),
                build_qualification_user_prompt(message, customer_name, getattr(source, "value", source)),
                LLMQualificationOutput,
                acc,
            )
        except _LLMFailure as failure:
            _record_usage(
                store, settings, workspace_id=workspace_id, kind=kind, provider=provider_name,
                model=model_name, success=False, error_code=failure.error.code, lead_id=lead_id,
                requested_by=requested_by, acc=failure.acc,
            )
            raise failure.error from None
    elif settings.demo_mode:
        provider_name, model_name = "demo-rules", "keyword-rules"
        acc.attempts = 1
        output = demo_qualification(message, customer_name)
    else:
        raise ServiceUnavailableError("No LLM API key is configured on the server.", code="llm_not_configured")

    result = _finalize(output, flags, provider_name, model_name, settings)
    usage = _record_usage(
        store, settings, workspace_id=workspace_id, kind=kind, provider=provider_name, model=model_name,
        success=True, error_code=None, lead_id=lead_id, requested_by=requested_by, acc=acc,
    )
    return result, usage


def draft_followup(
    store: DocumentStore,
    settings: Settings,
    *,
    workspace_id: str,
    lead: LeadOut,
    requested_by: str | None,
    instruction: str | None = None,
) -> tuple[FollowupDraftOutput, UsageInfo]:
    q = lead.qualification
    acc = _Attempts()
    provider_name, model_name = settings.llm_provider, settings.llm_model

    if settings.llm_configured:
        config = get_agent_config(store, workspace_id)
        provider = get_provider(settings)
        try:
            draft = _run_llm(
                provider,
                settings,
                build_followup_system_prompt(config),
                build_followup_user_prompt(
                    lead.customer_name,
                    q.summary if q else lead.message[:300],
                    q.missing_information if q else [],
                    q.recommended_next_action.value if q else "request_information",
                    instruction,
                ),
                FollowupDraftOutput,
                acc,
            )
        except _LLMFailure as failure:
            _record_usage(
                store, settings, workspace_id=workspace_id, kind=UsageKind.FOLLOWUP_DRAFT,
                provider=provider_name, model=model_name, success=False, error_code=failure.error.code,
                lead_id=lead.id, requested_by=requested_by, acc=failure.acc,
            )
            raise failure.error from None
    elif settings.demo_mode:
        provider_name, model_name = "demo-rules", "keyword-rules"
        acc.attempts = 1
        body = (q.suggested_followup_message if q and q.suggested_followup_message else
                f"Hi {lead.customer_name.split()[0] if lead.customer_name else 'there'},\n\n"
                "Thank you for your inquiry. Could you share a few more details so we can help?\n\nBest regards")
        draft = FollowupDraftOutput(subject="Thanks for your inquiry", body=body)
    else:
        raise ServiceUnavailableError("No LLM API key is configured on the server.", code="llm_not_configured")

    usage = _record_usage(
        store, settings, workspace_id=workspace_id, kind=UsageKind.FOLLOWUP_DRAFT, provider=provider_name,
        model=model_name, success=True, error_code=None, lead_id=lead.id, requested_by=requested_by, acc=acc,
    )
    return draft, usage


def scan_draft_flags(text: str) -> list[str]:
    """Public helper so approvals created from edited or regenerated drafts get the same safety flags."""
    return _scan_draft(text)