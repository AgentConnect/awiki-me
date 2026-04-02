"""Unit tests for the non-interactive email verification helper.

[INPUT]: scripts/utils/handle.py email verification helpers, monkeypatched async
         HTTP helper calls, and deterministic polling behavior
[OUTPUT]: Regression coverage for send-only and polling-based email flows
[POS]: Utility-layer tests for non-interactive email verification

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

from utils import handle as handle_utils  # noqa: E402


def test_ensure_email_verification_skips_send_when_already_verified(monkeypatch) -> None:
    """Already verified emails should not trigger another activation send."""
    events: list[str] = []

    async def fake_check(client, email):
        del client, email
        return True, "2026-03-19T14:00:00Z"

    async def fake_send() -> None:
        events.append("sent")

    monkeypatch.setattr(handle_utils, "check_email_verified", fake_check)

    result = asyncio.run(
        handle_utils.ensure_email_verification(
            client=object(),
            email="user@example.com",
            send_fn=fake_send,
        )
    )

    assert result.verified is True
    assert result.activation_sent is False
    assert result.verified_at == "2026-03-19T14:00:00Z"
    assert events == []


def test_ensure_email_verification_returns_pending_without_wait(monkeypatch) -> None:
    """Non-waiting mode should send the activation email and return pending."""
    events: list[str] = []

    async def fake_check(client, email):
        del client, email
        return False, None

    async def fake_send() -> None:
        events.append("sent")

    monkeypatch.setattr(handle_utils, "check_email_verified", fake_check)

    result = asyncio.run(
        handle_utils.ensure_email_verification(
            client=object(),
            email="user@example.com",
            send_fn=fake_send,
        )
    )

    assert result.verified is False
    assert result.activation_sent is True
    assert result.verified_at is None
    assert events == ["sent"]


def test_ensure_email_verification_polls_until_verified(monkeypatch) -> None:
    """Waiting mode should poll until the backend reports a verified email."""
    check_results = iter(
        [
            (False, None),
            (False, None),
            (True, "2026-03-19T14:05:00Z"),
        ]
    )
    sleep_calls: list[float] = []
    send_calls: list[str] = []

    async def fake_check(client, email):
        del client, email
        return next(check_results)

    async def fake_send() -> None:
        send_calls.append("sent")

    async def fake_sleep(seconds: float) -> None:
        sleep_calls.append(seconds)

    monkeypatch.setattr(handle_utils, "check_email_verified", fake_check)
    monkeypatch.setattr(handle_utils.asyncio, "sleep", fake_sleep)

    result = asyncio.run(
        handle_utils.ensure_email_verification(
            client=object(),
            email="user@example.com",
            send_fn=fake_send,
            wait=True,
            timeout=30,
            poll_interval=2.5,
        )
    )

    assert result.verified is True
    assert result.activation_sent is True
    assert result.verified_at == "2026-03-19T14:05:00Z"
    assert send_calls == ["sent"]
    assert sleep_calls == [2.5]


def test_ensure_email_verification_times_out(monkeypatch) -> None:
    """Waiting mode should return pending when verification does not complete in time."""
    send_calls: list[str] = []

    async def fake_check(client, email):
        del client, email
        return False, None

    async def fake_send() -> None:
        send_calls.append("sent")

    async def fake_sleep(seconds: float) -> None:
        del seconds

    monkeypatch.setattr(handle_utils, "check_email_verified", fake_check)
    monkeypatch.setattr(handle_utils.asyncio, "sleep", fake_sleep)

    result = asyncio.run(
        handle_utils.ensure_email_verification(
            client=object(),
            email="user@example.com",
            send_fn=fake_send,
            wait=True,
            timeout=0,
            poll_interval=2.0,
        )
    )

    assert result.verified is False
    assert result.activation_sent is True
    assert result.verified_at is None
    assert send_calls == ["sent"]
