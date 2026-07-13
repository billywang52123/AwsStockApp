"""Gateway Lambda tools 的單元測試:mock urllib,不打真網路。

Lambda 以 tools/ 為打包根(平面模組),測試同樣把 tools/ 加進 sys.path,
與 Lambda runtime 內的 import 方式一致。
"""
import io
import json
import sys
import urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

import pytest


@pytest.fixture(autouse=True)
def base_url(monkeypatch):
    monkeypatch.setenv("BACKEND_BASE_URL", "https://backend.example")


def _fake_response(payload: dict):
    body = io.BytesIO(json.dumps(payload).encode())
    body.status = 200
    body.__enter__ = lambda s: s
    body.__exit__ = lambda s, *a: False
    return body


def test_holdings_calls_backend_with_user_header(monkeypatch):
    captured = {}

    def fake_urlopen(req, timeout):
        captured["url"] = req.full_url
        captured["x_user_id"] = req.get_header("X-user-id")
        captured["timeout"] = timeout
        return _fake_response({"success": True, "data": {"risk_score": 55}})

    monkeypatch.setattr("backend_client.urllib.request.urlopen", fake_urlopen)
    from get_portfolio_holdings import handler

    result = handler({"user_id": "demo-user"}, None)

    assert result == {"risk_score": 55}
    assert captured["url"] == "https://backend.example/api/portfolio/analysis"
    assert captured["x_user_id"] == "demo-user"
    assert captured["timeout"] == 5


def test_market_compare_path(monkeypatch):
    def fake_urlopen(req, timeout):
        assert req.full_url == "https://backend.example/api/market/compare"
        return _fake_response({"success": True, "data": {"market_change": -0.4}})

    monkeypatch.setattr("backend_client.urllib.request.urlopen", fake_urlopen)
    from get_market_compare import handler

    assert handler({"user_id": "demo-user"}, None) == {"market_change": -0.4}


def test_missing_user_id_returns_error():
    from get_portfolio_holdings import handler
    result = handler({}, None)
    assert "error" in result


def test_backend_failure_returns_structured_error(monkeypatch):
    def fake_urlopen(req, timeout):
        raise urllib.error.URLError("timeout")

    monkeypatch.setattr("backend_client.urllib.request.urlopen", fake_urlopen)
    from get_portfolio_holdings import handler

    result = handler({"user_id": "demo-user"}, None)
    assert "error" in result and "暫時" in result["error"]
