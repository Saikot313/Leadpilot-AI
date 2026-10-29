def test_health_is_ok_and_reports_demo_mode(client):
    r = client.get("/health")
    assert r.status_code == 200
    body = r.json()
    assert body["status"] == "ok"
    assert body["mode"] == "demo"
    assert body["service"] == "leadpilot-api"


def test_ready_checks_the_document_store(client):
    r = client.get("/health/ready")
    assert r.status_code == 200
    assert r.json()["status"] == "ready"


def test_responses_carry_request_id_and_security_headers(client):
    r = client.get("/health")
    assert r.headers["x-request-id"]
    assert r.headers["x-content-type-options"] == "nosniff"
    assert r.headers["cache-control"] == "no-store"


def test_unknown_route_uses_the_uniform_error_shape(client):
    r = client.get("/nope")
    assert r.status_code == 404
    assert r.json()["error"]["code"] == "http_404"