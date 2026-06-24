import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from checker import check_http, check_tcp  # noqa: E402


def test_check_http_success():
    target = {"name": "test-node", "type": "http", "target": "http://example.com"}
    mock_resp = MagicMock(status_code=200)
    with patch("checker.requests.get", return_value=mock_resp):
        result = check_http(target)
    assert result.reachable is True
    assert result.latency_ms is not None
    assert result.error is None


def test_check_http_failure():
    import requests

    target = {"name": "test-node", "type": "http", "target": "http://example.com"}
    with patch("checker.requests.get", side_effect=requests.ConnectionError("refused")):
        result = check_http(target)
    assert result.reachable is False
    assert result.latency_ms is None
    assert "refused" in result.error


def test_check_http_server_error_marks_unreachable():
    target = {"name": "test-node", "type": "http", "target": "http://example.com"}
    mock_resp = MagicMock(status_code=503)
    with patch("checker.requests.get", return_value=mock_resp):
        result = check_http(target)
    assert result.reachable is False


def test_check_tcp_success():
    target = {"name": "db", "type": "tcp", "target": "example.com:5432"}
    with patch("checker.socket.create_connection") as mock_conn:
        mock_conn.return_value.__enter__.return_value = MagicMock()
        result = check_tcp(target)
    assert result.reachable is True


def test_check_tcp_failure():
    target = {"name": "db", "type": "tcp", "target": "example.com:5432"}
    with patch("checker.socket.create_connection", side_effect=OSError("timed out")):
        result = check_tcp(target)
    assert result.reachable is False
    assert "timed out" in result.error
