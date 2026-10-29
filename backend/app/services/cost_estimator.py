"""Cost estimation and usage aggregation. Never invents token counts or prices."""
from __future__ import annotations

from typing import Any

from app.core.config import Settings
from app.schemas.monitoring import ModelUsage, UsageSummary

COST_NOTE = (
    "Costs are estimates computed from provider-reported token counts and the per-1M-token prices "
    "configured on the server. They are not billing data."
)


def estimate_cost_usd(
    input_tokens: int | None,
    output_tokens: int | None,
    input_price_per_1m: float | None,
    output_price_per_1m: float | None,
) -> float | None:
    """Return an estimate in USD, or None when any input is unknown."""
    if None in (input_tokens, output_tokens, input_price_per_1m, output_price_per_1m):
        return None
    cost = input_tokens / 1_000_000 * input_price_per_1m + output_tokens / 1_000_000 * output_price_per_1m
    return round(cost, 6)


def estimate_for_settings(settings: Settings, input_tokens: int | None, output_tokens: int | None) -> float | None:
    return estimate_cost_usd(
        input_tokens, output_tokens, settings.llm_input_price_per_1m, settings.llm_output_price_per_1m
    )


def summarize_usage(
    records: list[dict[str, Any]], *, period_days: int, monthly_budget_usd: float | None = None
) -> UsageSummary:
    total = len(records)
    successful = sum(1 for r in records if r.get("success", True))
    measured = [r for r in records if r.get("tokensMeasured")]
    costs = [r["estimatedCostUsd"] for r in records if r.get("estimatedCostUsd") is not None]
    latencies = [r["latencyMs"] for r in records if r.get("latencyMs")]

    groups: dict[tuple[str, str], ModelUsage] = {}
    model_costs: dict[tuple[str, str], list[float]] = {}
    for r in records:
        key = (str(r.get("provider", "unknown")), str(r.get("model", "unknown")))
        usage = groups.setdefault(key, ModelUsage(provider=key[0], model=key[1]))
        usage.requests += 1
        if r.get("tokensMeasured"):
            usage.measured_input_tokens += int(r.get("inputTokens") or 0)
            usage.measured_output_tokens += int(r.get("outputTokens") or 0)
        if r.get("estimatedCostUsd") is not None:
            model_costs.setdefault(key, []).append(r["estimatedCostUsd"])
    for key, usage in groups.items():
        if key in model_costs:
            usage.estimated_cost_usd = round(sum(model_costs[key]), 6)

    cost = round(sum(costs), 6) if costs else None
    note = COST_NOTE
    missing = total - len(measured)
    if missing:
        note += f" {missing} request(s) had no provider token data and are excluded from token and cost totals."
    budget_pct = None
    if cost is not None and monthly_budget_usd:
        budget_pct = round(cost / monthly_budget_usd * 100, 1)

    return UsageSummary(
        period_days=period_days,
        total_requests=total,
        successful_requests=successful,
        failed_requests=total - successful,
        requests_without_token_data=missing,
        measured_input_tokens=sum(int(r.get("inputTokens") or 0) for r in measured),
        measured_output_tokens=sum(int(r.get("outputTokens") or 0) for r in measured),
        estimated_cost_usd=cost,
        cost_note=note,
        avg_latency_ms=round(sum(latencies) / len(latencies), 1) if latencies else None,
        by_model=sorted(groups.values(), key=lambda m: m.requests, reverse=True),
        monthly_budget_usd=monthly_budget_usd,
        budget_used_pct=budget_pct,
    )