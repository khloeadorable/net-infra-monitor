import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "src"))

from alerts import check_threshold  # noqa: E402


def test_latency_under_threshold_is_ok():
    assert check_threshold(50, 100) is False


def test_latency_over_threshold_is_warning():
    assert check_threshold(150, 100) is True


def test_latency_equal_to_threshold_is_ok():
    assert check_threshold(100, 100) is False


def test_unreachable_target_is_always_warning():
    assert check_threshold(None, 100, reachable=False) is True


def test_unreachable_target_warning_even_with_low_latency():
    # reachable=False should win even if a stale latency value is present
    assert check_threshold(10, 100, reachable=False) is True


def test_none_latency_with_reachable_true_is_warning():
    # defensive case: shouldn't happen in practice, but must not crash
    assert check_threshold(None, 100, reachable=True) is True
