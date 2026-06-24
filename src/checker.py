"""
Performs real health checks against monitored targets.

Each target is checked with a real network call (HTTP GET or TCP connect)
and timed. No synthetic data — if a target is unreachable, that's reflected
as a genuine failure, not simulated.
"""
import logging
import socket
import time
from dataclasses import dataclass

import requests

from targets import NodeTarget

logger = logging.getLogger(__name__)


@dataclass
class CheckResult:
    name: str
    target: str
    latency_ms: float | None
    reachable: bool
    error: str | None = None


def _log_result(result: "CheckResult") -> None:
    logger.info(
        "health check completed",
        extra={
            "node": result.name,
            "target": result.target,
            "reachable": result.reachable,
            "latency_ms": result.latency_ms,
            "error": result.error,
        },
    )


def check_http(target: NodeTarget, timeout: float = 5.0) -> CheckResult:
    start = time.perf_counter()
    try:
        resp = requests.get(target["target"], timeout=timeout)
        latency_ms = (time.perf_counter() - start) * 1000
        result = CheckResult(
            name=target["name"],
            target=target["target"],
            latency_ms=round(latency_ms, 1),
            reachable=resp.status_code < 500,
        )
    except requests.RequestException as e:
        result = CheckResult(
            name=target["name"],
            target=target["target"],
            latency_ms=None,
            reachable=False,
            error=str(e),
        )
    _log_result(result)
    return result


def check_tcp(target: NodeTarget, timeout: float = 5.0) -> CheckResult:
    host, _, port_str = target["target"].partition(":")
    port = int(port_str) if port_str else 443
    start = time.perf_counter()
    try:
        with socket.create_connection((host, port), timeout=timeout):
            latency_ms = (time.perf_counter() - start) * 1000
            result = CheckResult(
                name=target["name"],
                target=target["target"],
                latency_ms=round(latency_ms, 1),
                reachable=True,
            )
    except OSError as e:
        result = CheckResult(
            name=target["name"],
            target=target["target"],
            latency_ms=None,
            reachable=False,
            error=str(e),
        )
    _log_result(result)
    return result


def check_target(target: NodeTarget) -> CheckResult:
    if target["type"] == "http":
        return check_http(target)
    elif target["type"] == "tcp":
        return check_tcp(target)
    else:
        raise ValueError(f"Unknown target type: {target['type']}")


def check_all(targets: list[NodeTarget]) -> list[CheckResult]:
    return [check_target(t) for t in targets]
