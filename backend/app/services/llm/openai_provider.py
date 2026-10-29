"""OpenAI provider (REST via httpx)."""
from __future__ import annotations

import time

from app.services.llm.base import LLMCallError, LLMProvider, LLMResponse, post_json

_URL = "https://api.openai.com/v1/chat/completions"


class OpenAIProvider(LLMProvider):
    name = "openai"

    def __init__(self, api_key: str, model: str, timeout: float):
        self._api_key = api_key
        self.model = model
        self._timeout = timeout

    def generate_json(self, system, user, *, max_output_tokens=1500, temperature=0.2) -> LLMResponse:
        body = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": temperature,
            "max_completion_tokens": max_output_tokens,
            "response_format": {"type": "json_object"},
        }
        started = time.perf_counter()
        data = post_json(
            _URL,
            {"Authorization": f"Bearer {self._api_key}", "Content-Type": "application/json"},
            body,
            self._timeout,
        )
        latency_ms = int((time.perf_counter() - started) * 1000)

        choices = data.get("choices") or []
        message = (choices[0].get("message") or {}) if choices else {}
        if message.get("refusal"):
            raise LLMCallError("The model refused the request.", code="blocked", retryable=False)
        text = message.get("content") or ""
        if not text.strip():
            raise LLMCallError("OpenAI returned an empty response.", code="empty_response", retryable=True)

        usage = data.get("usage") or {}
        input_tokens = usage.get("prompt_tokens")
        output_tokens = usage.get("completion_tokens")
        return LLMResponse(
            text=text,
            provider=self.name,
            model=self.model,
            input_tokens=int(input_tokens) if input_tokens is not None else None,
            output_tokens=int(output_tokens) if output_tokens is not None else None,
            latency_ms=latency_ms,
        )