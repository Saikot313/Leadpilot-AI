import pytest

from app.services.cost_estimator import estimate_cost_usd, summarize_usage


def test_estimate_uses_measured_tokens_and_configured_prices():
    assert estimate_cost_usd(1_000_000, 1_000_000, 0.10, 0.40) == pytest.approx(0.5)
    assert estimate_cost_usd(1000, 500, 0.10, 0.40) == pytest.approx(0.0003)


@pytest.mark.parametrize(
    "args",
    [(None, 10, 0.1, 0.4), (10, None, 0.1, 0.4), (10, 10, None, 0.4), (10, 10, 0.1, None)],
)
def test_estimate_is_none_when_anything_is_unknown(args):
    assert estimate_cost_usd(*args) is None


def test_zero_tokens_is_zero_cost_not_unknown():
    assert estimate_cost_usd(0, 0, 0.1, 0.4) == 0


def record(**kw):
    base = {"success": True, "provider": "gemini", "model": "m"}
    base.update(kw)
    return base


def test_summary_separates_measured_values_from_estimates():
    rows = [
        record(tokensMeasured=True, inputTokens=1000, outputTokens=500, estimatedCostUsd=0.0003, latencyMs=800),
        record(tokensMeasured=True, inputTokens=2000, outputTokens=1000, estimatedCostUsd=0.0006, latencyMs=1200),
        record(success=False, tokensMeasured=False),
    ]
    s = summarize_usage(rows, period_days=30, monthly_budget_usd=0.009)
    assert s.total_requests == 3
    assert s.successful_requests == 2 and s.failed_requests == 1
    assert s.requests_without_token_data == 1
    assert s.measured_input_tokens == 3000 and s.measured_output_tokens == 1500
    assert s.estimated_cost_usd == pytest.approx(0.0009)
    assert s.avg_latency_ms == pytest.approx(1000.0)
    assert s.budget_used_pct == pytest.approx(10.0)
    assert "estimates" in s.cost_note and "1 request(s)" in s.cost_note
    assert len(s.by_model) == 1 and s.by_model[0].requests == 3


def test_empty_usage_has_no_invented_values():
    s = summarize_usage([], period_days=7)
    assert s.total_requests == 0
    assert s.estimated_cost_usd is None
    assert s.avg_latency_ms is None
    assert s.budget_used_pct is None


def test_no_budget_percentage_without_a_cost_estimate():
    s = summarize_usage([record(tokensMeasured=False)], period_days=30, monthly_budget_usd=10)
    assert s.estimated_cost_usd is None
    assert s.budget_used_pct is None