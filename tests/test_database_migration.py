"""Tests for database_migration ready-state self-healing.

[INPUT]: database_migration, local_store, temporary AWIKI_DATA_DIR
[OUTPUT]: pytest assertions for ready-state schema repair behavior
[POS]: Unit tests for database migration helpers

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

import database_migration  # noqa: E402
import local_store  # noqa: E402

_REPAIRED_INDEXES = {
    "idx_messages_owner_thread",
    "idx_messages_owner_direction",
    "idx_e2ee_outbox_owner_status",
}


def _index_names(conn: sqlite3.Connection) -> set[str]:
    """Return non-internal SQLite index names."""
    rows = conn.execute(
        """
        SELECT name FROM sqlite_master
        WHERE type = 'index' AND name NOT LIKE 'sqlite_%'
        """
    ).fetchall()
    return {row[0] for row in rows}


@pytest.fixture()
def prepared_ready_database(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """Create a ready database with selected indexes removed."""
    monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))

    conn = local_store.get_connection()
    local_store.ensure_schema(conn)
    for index_name in sorted(_REPAIRED_INDEXES):
        conn.execute(f"DROP INDEX {index_name}")
    conn.commit()
    conn.close()

    return tmp_path / "database" / "awiki.db"


def test_ensure_local_database_ready_repairs_ready_database(
    prepared_ready_database: Path,
) -> None:
    """Ready-state checks should repair missing indexes before returning."""
    result = database_migration.ensure_local_database_ready()

    assert result["status"] == "ready"
    assert result["db_path"] == str(prepared_ready_database)
    assert result["before_version"] == local_store._SCHEMA_VERSION
    assert result["after_version"] == local_store._SCHEMA_VERSION

    conn = local_store.get_connection()
    try:
        assert _REPAIRED_INDEXES <= _index_names(conn)
    finally:
        conn.close()


def test_migrate_local_database_repairs_ready_database_without_backup(
    prepared_ready_database: Path,
) -> None:
    """The standalone migration helper should self-heal ready databases."""
    result = database_migration.migrate_local_database()

    assert result["status"] == "ready"
    assert result["db_path"] == str(prepared_ready_database)
    assert result["before_version"] == local_store._SCHEMA_VERSION
    assert result["after_version"] == local_store._SCHEMA_VERSION
    assert result["backup_path"] is None

    conn = local_store.get_connection()
    try:
        assert _REPAIRED_INDEXES <= _index_names(conn)
    finally:
        conn.close()


def test_migrate_local_database_treats_outdated_v6_database_as_legacy(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Outdated schemas should trigger backup + migration instead of ready-state repair."""
    monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
    db_dir = tmp_path / "database"
    db_dir.mkdir(parents=True, exist_ok=True)
    db_path = db_dir / "awiki.db"

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.executescript("""
        CREATE TABLE contacts (
            owner_did TEXT NOT NULL DEFAULT '',
            did TEXT NOT NULL,
            name TEXT,
            handle TEXT,
            nick_name TEXT,
            bio TEXT,
            profile_md TEXT,
            tags TEXT,
            relationship TEXT,
            first_seen_at TEXT,
            last_seen_at TEXT,
            metadata TEXT,
            PRIMARY KEY (owner_did, did)
        );
        CREATE TABLE messages (
            msg_id TEXT NOT NULL,
            owner_did TEXT NOT NULL DEFAULT '',
            thread_id TEXT NOT NULL,
            direction INTEGER NOT NULL DEFAULT 0,
            sender_did TEXT,
            receiver_did TEXT,
            group_id TEXT,
            group_did TEXT,
            content_type TEXT DEFAULT 'text',
            content TEXT,
            title TEXT,
            server_seq INTEGER,
            sent_at TEXT,
            stored_at TEXT NOT NULL,
            is_e2ee INTEGER DEFAULT 0,
            is_read INTEGER DEFAULT 0,
            sender_name TEXT,
            metadata TEXT,
            credential_name TEXT NOT NULL DEFAULT '',
            PRIMARY KEY (msg_id, owner_did)
        );
        CREATE TABLE e2ee_outbox (
            outbox_id TEXT PRIMARY KEY,
            owner_did TEXT NOT NULL DEFAULT '',
            peer_did TEXT NOT NULL,
            session_id TEXT,
            original_type TEXT NOT NULL DEFAULT 'text',
            plaintext TEXT NOT NULL,
            local_status TEXT NOT NULL DEFAULT 'queued',
            attempt_count INTEGER NOT NULL DEFAULT 0,
            sent_msg_id TEXT,
            sent_server_seq INTEGER,
            last_error_code TEXT,
            retry_hint TEXT,
            failed_msg_id TEXT,
            failed_server_seq INTEGER,
            metadata TEXT,
            last_attempt_at TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            credential_name TEXT NOT NULL DEFAULT ''
        );
        PRAGMA user_version = 6;
    """)
    conn.commit()
    conn.close()

    detection = database_migration.detect_local_database_layout()
    result = database_migration.migrate_local_database()

    assert detection["status"] == "legacy"
    assert detection["before_version"] == 6
    assert result["status"] == "migrated"
    assert result["before_version"] == 6
    assert result["after_version"] == local_store._SCHEMA_VERSION
    assert result["backup_path"] is not None
    assert Path(result["backup_path"]).exists()


def test_ensure_local_database_ready_for_upgrade_stops_and_restarts_listener(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Explicit upgrade flow should stop a running listener and restore it after migration."""

    class _FakeServiceManager:
        def __init__(self) -> None:
            self.running = True
            self.calls: list[str] = []

        def status(self) -> dict[str, object]:
            self.calls.append("status")
            return {
                "installed": True,
                "running": self.running,
            }

        def stop(self) -> None:
            self.calls.append("stop")
            self.running = False

        def start(self) -> None:
            self.calls.append("start")
            self.running = True

    fake_manager = _FakeServiceManager()
    monkeypatch.setattr(
        database_migration,
        "detect_local_database_layout",
        lambda config=None: {
            "status": "ready",
            "db_path": "/tmp/awiki.db",
            "before_version": local_store._SCHEMA_VERSION,
        },
    )
    monkeypatch.setattr(
        database_migration,
        "ensure_local_database_ready",
        lambda config=None: {
            "status": "ready",
            "db_path": "/tmp/awiki.db",
            "before_version": local_store._SCHEMA_VERSION,
            "after_version": local_store._SCHEMA_VERSION,
            "backup_path": None,
        },
    )
    monkeypatch.setattr(
        database_migration,
        "get_service_manager",
        lambda: fake_manager,
    )

    result = database_migration.ensure_local_database_ready_for_upgrade()

    assert result["status"] == "ready"
    assert result["listener_service"]["was_running"] is True
    assert result["listener_service"]["stopped"] is True
    assert result["listener_service"]["restarted"] is True
    assert fake_manager.calls == ["status", "stop", "status", "start", "status"]
