"""Gemini provider (REST via httpx)."""
from __future__ import annotations

import time

from app.services.llm.base import LLMCallError, LLMProvider, LLMResponse, post_json

_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"


class GeminiProvider(LLMProvider):
    name = "gemini"

    def __init__(self, api_key: str, model: str, timeout: float):
        self._api_key = api_key
        self.model = model
        self._timeout = timeout

    def generate_json(self, system, user, *, max_output_tokens=1500, temperature=0.2) -> LLMResponse:
        body = {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": [{"role": "user", "parts": [{"text": user}]}],
            "generationConfig": {
                "temperature": temperature,
                "maxOutputTokens": max_output_tokens,
                "responseMimeType": "application/json",
            },
        }
        started = time.perf_counter()
        data = post_json(
            f"{_BASE_URL}/{self.model}:generateContent",
            {"x-goog-api-key": self._api_key, "Content-Type": "application/json"},
            body,
            self._timeout,
        )
        latency_ms = int((time.perf_counter() - started) * 1000)

        candidates = data.get("candidates") or []
        if not candidates:
            raise LLMCallError("Gemini returned no candidates (possibly blocked).", code="blocked", retryable=False)
        parts = (candidates[0].get("content") or {}).get("parts") or []
        text = "".join(p.get("text", "") for p in parts if isinstance(p, dict) and not p.get("thought"))
        if not text.strip():
            raise LLMCallError("Gemini returned an empty response.", code="empty_response", retryable=True)

        usage = data.get("usageMetadata") or {}
        input_tokens = usage.get("promptTokenCount")
        candidate_tokens = usage.get("candidatesTokenCount")
        output_tokens = None
        if candidate_tokens is not None:
            output_tokens = int(candidate_tokens) + int(usage.get("thoughtsTokenCount") or 0)
        return LLMResponse(
            text=text,
            provider=self.name,
            model=self.model,
            input_tokens=int(input_tokens) if input_tokens is not None else None,
            output_tokens=output_tokens,
            latency_ms=latency_ms,
        )