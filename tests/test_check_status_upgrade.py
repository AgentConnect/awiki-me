"""Tests for check_status local upgrade orchestration.

[INPUT]: check_status helpers with monkeypatched migration functions
[OUTPUT]: Regression coverage for local upgrade reporting and failure gating
[POS]: Unit tests for local skill upgrade flow exposed by check_status.py

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

import check_status  # noqa: E402


def test_ensure_local_upgrade_ready_reports_performed_migrations(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Upgrade helper should summarize credential/database migration work."""
    monkeypatch.setattr(
        check_status,
        "ensure_credential_storage_ready",
        lambda credential_name: {
            "status": "migrated",
            "layout": "new",
            "credential_ready": True,
            "migration": {
                "status": "migrated",
                "migrated": [{"credential_name": credential_name}],
            },
        },
    )
    monkeypatch.setattr(
        check_status,
        "ensure_local_database_ready",
        lambda: {
            "status": "migrated",
            "db_path": "/tmp/awiki.db",
            "before_version": 8,
            "after_version": 9,
            "backup_path": "/tmp/awiki-backup.db",
        },
    )

    result = check_status.ensure_local_upgrade_ready("alice")

    assert result["status"] == "ready"
    assert result["credential_ready"] is True
    assert result["database_ready"] is True
    assert result["performed"] == ["credential_layout", "local_database"]


def test_ensure_local_upgrade_ready_can_coordinate_listener_for_explicit_upgrade(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Explicit upgrade mode should use the listener-aware database wrapper."""
    monkeypatch.setattr(
        check_status,
        "ensure_credential_storage_ready",
        lambda credential_name: {
            "status": "ready",
            "layout": "new",
            "credential_ready": True,
            "migration": {"status": "not_needed"},
        },
    )
    monkeypatch.setattr(
        check_status,
        "ensure_local_database_ready",
        lambda: pytest.fail("ensure_local_database_ready should not be used"),
    )
    monkeypatch.setattr(
        check_status,
        "ensure_local_database_ready_for_upgrade",
        lambda: {
            "status": "ready",
            "db_path": "/tmp/awiki.db",
            "before_version": 11,
            "after_version": 11,
            "backup_path": None,
            "listener_service": {
                "was_running": True,
                "stopped": True,
                "restarted": True,
            },
        },
    )

    result = check_status.ensure_local_upgrade_ready(
        "alice",
        coordinate_listener_during_database_upgrade=True,
    )

    assert result["status"] == "ready"
    assert result["local_database"]["listener_service"]["restarted"] is True


def test_check_status_stops_when_upgrade_cannot_prepare_credentials(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Unified status should return early when local upgrade leaves credentials unusable."""
    monkeypatch.setattr(
        check_status,
        "ensure_local_upgrade_ready",
        lambda credential_name: {
            "status": "error",
            "credential_ready": False,
            "database_ready": True,
            "performed": [],
            "credential_layout": {
                "status": "partial",
                "layout": "legacy_remaining",
                "credential_ready": False,
                "migration": {"status": "error"},
            },
            "local_database": {"status": "ready"},
        },
    )

    report = asyncio.run(check_status.check_status("alice"))

    assert report["local_upgrade"]["status"] == "error"
    assert report["identity"]["status"] == "storage_migration_required"
    assert report["inbox"]["status"] == "skipped"
    assert report["group_watch"]["status"] == "skipped"
