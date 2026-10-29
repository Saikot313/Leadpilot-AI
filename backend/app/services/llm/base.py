"""LLM provider interface and shared HTTP handling."""
from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any

import httpx

from app.core.logging import get_logger

logger = get_logger("leadpilot.llm")


class LLMCallError(Exception):
    """Provider call failed. `code` is one of: timeout, network, rate_limited, upstream_5xx, auth_failed,
    bad_request, bad_response, blocked, empty_response."""

    def __init__(self, message: str, *, code: str, retryable: bool):
        super().__init__(message)
        self.code = code
        self.retryable = retryable


@dataclass
class LLMResponse:
    text: str
    provider: str
    model: str
    input_tokens: int | None = None  # None = provider did not report it
    output_tokens: int | None = None
    latency_ms: int | None = None


class LLMProvider(ABC):
    name: str = "base"
    model: str = ""

    @abstractmethod
    def generate_json(
        self, system: str, user: str, *, max_output_tokens: int = 1500, temperature: float = 0.2
    ) -> LLMResponse:
        """Return the model's raw text (expected to be JSON). Raises LLMCallError."""


def post_json(url: str, headers: dict[str, str], body: dict[str, Any], timeout: float) -> dict[str, Any]:
    """POST JSON and map failures to LLMCallError. Never logs request bodies or credentials."""
    try:
        resp = httpx.post(url, headers=headers, json=body, timeout=timeout)
    except httpx.TimeoutException as exc:
        raise LLMCallError("LLM request timed out.", code="timeout", retryable=True) from exc
    except httpx.HTTPError as exc:
        raise LLMCallError("LLM network error.", code="network", retryable=True) from exc

    status = resp.status_code
    if status >= 400:
        logger.warning("llm_http_error", extra={"status": status})
        if status == 429:
            raise LLMCallError("LLM rate limit reached.", code="rate_limited", retryable=True)
        if status >= 500:
            raise LLMCallError("LLM provider error.", code="upstream_5xx", retryable=True)
        if status in (401, 403):
            raise LLMCallError("LLM credentials were rejected.", code="auth_failed", retryable=False)
        raise LLMCallError("LLM request was rejected.", code="bad_request", retryable=False)
    try:
        data = resp.json()
    except ValueError as exc:
        raise LLMCallError("LLM returned a non-JSON response.", code="bad_response", retryable=True) from exc
    if not isinstance(data, dict):
        raise LLMCallError("LLM returned an unexpected response.", code="bad_response", retryable=True)
    return data