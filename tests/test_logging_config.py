import json
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from logging_config import JsonFormatter  # noqa: E402


def _make_record(msg: str, **extra) -> logging.LogRecord:
    record = logging.LogRecord(
        name="test", level=logging.INFO, pathname=__file__, lineno=1,
        msg=msg, args=(), exc_info=None,
    )
    for k, v in extra.items():
        setattr(record, k, v)
    return record


def test_formats_as_valid_json():
    formatter = JsonFormatter()
    record = _make_record("hello")
    parsed = json.loads(formatter.format(record))
    assert parsed["message"] == "hello"
    assert parsed["level"] == "INFO"


def test_includes_extra_fields():
    formatter = JsonFormatter()
    record = _make_record("check done", node="db-01", latency_ms=12.3, reachable=True)
    parsed = json.loads(formatter.format(record))
    assert parsed["node"] == "db-01"
    assert parsed["latency_ms"] == 12.3
    assert parsed["reachable"] is True


def test_excludes_internal_logrecord_fields():
    formatter = JsonFormatter()
    record = _make_record("hi")
    parsed = json.loads(formatter.format(record))
    # internal LogRecord bookkeeping fields shouldn't leak into the payload
    assert "pathname" not in parsed
    assert "lineno" not in parsed
    assert "args" not in parsed
