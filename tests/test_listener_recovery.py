"""Unit tests for listener runtime recovery helpers.

[INPUT]: listener_recovery helpers with temporary SDKConfig data directories
[OUTPUT]: Regression coverage for persisted restart counters and health resets
[POS]: Operational unit tests for listener auto-restart backoff state

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import sys
from pathlib import Path

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

import listener_recovery  # noqa: E402
from utils.config import SDKConfig  # noqa: E402


def _build_config(tmp_path: Path) -> SDKConfig:
    """Build a config object rooted under a temporary data dir."""
    return SDKConfig(
        user_service_url="https://example.com",
        molt_message_url="https://example.com",
        did_domain="example.com",
        credentials_dir=tmp_path / "credentials",
        data_dir=tmp_path / "data",
    )


def test_restart_failures_pause_auto_restart_after_three_attempts(
    tmp_path: Path,
) -> None:
    """Three persisted failures should pause automatic listener restart."""
    config = _build_config(tmp_path)

    state = None
    for index in range(3):
        state = listener_recovery.record_listener_restart_failure(
            "alice",
            f"failure-{index}",
            config=config,
        )

    assert state is not None
    assert state["consecutive_restart_failures"] == 3
    assert state["auto_restart_paused"] is True
    assert state["last_error"] == "failure-2"
    persisted = listener_recovery.get_listener_recovery_state(
        "alice",
        config=config,
    )
    assert persisted["auto_restart_paused"] is True


def test_note_listener_healthy_clears_persisted_restart_failures(
    tmp_path: Path,
) -> None:
    """A healthy listener observation should clear persisted backoff state."""
    config = _build_config(tmp_path)
    listener_recovery.record_listener_restart_failure(
        "alice",
        "temporary-failure",
        config=config,
    )

    state = listener_recovery.note_listener_healthy(
        "alice",
        config=config,
        result="restarted",
    )

    assert state["consecutive_restart_failures"] == 0
    assert state["auto_restart_paused"] is False
    assert state["last_restart_result"] == "restarted"
    assert state["last_error"] is None
