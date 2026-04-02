"""Unit tests for concise query_db CLI error output.

[INPUT]: query_db CLI entry point, monkeypatched local_store helpers, and argv
[OUTPUT]: Regression coverage for concise SQL validation and SQLite errors
[POS]: CLI unit tests for read-only local database querying

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
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

import query_db  # noqa: E402


class _DummyConnection:
    """Minimal SQLite connection stub for CLI tests."""

    def close(self) -> None:
        """Close the stub connection."""


def test_main_renders_sqlite_error_without_traceback(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """query_db should print only the SQLite error reason."""
    monkeypatch.setattr(query_db, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(query_db.local_store, "get_connection", lambda: _DummyConnection())
    monkeypatch.setattr(query_db.local_store, "ensure_schema", lambda conn: None)

    def _fake_execute_sql(conn, sql):
        del conn, sql
        raise sqlite3.OperationalError("no such column: group_name")

    monkeypatch.setattr(query_db.local_store, "execute_sql", _fake_execute_sql)
    monkeypatch.setattr(
        sys,
        "argv",
        ["query_db.py", "SELECT group_name FROM messages"],
    )

    with pytest.raises(SystemExit) as exc_info:
        query_db.main()

    assert exc_info.value.code == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err.strip() == "Error: no such column: group_name"
    assert "Traceback" not in captured.err


def test_main_renders_validation_error_without_traceback(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """query_db should keep validation failures concise too."""
    monkeypatch.setattr(query_db, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(query_db.local_store, "get_connection", lambda: _DummyConnection())
    monkeypatch.setattr(query_db.local_store, "ensure_schema", lambda conn: None)
    monkeypatch.setattr(
        query_db.local_store,
        "execute_sql",
        lambda conn, sql: (_ for _ in ()).throw(ValueError("Forbidden SQL operation: DROP")),
    )
    monkeypatch.setattr(
        sys,
        "argv",
        ["query_db.py", "DROP TABLE messages"],
    )

    with pytest.raises(SystemExit) as exc_info:
        query_db.main()

    assert exc_info.value.code == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err.strip() == "Error: Forbidden SQL operation: DROP"
    assert "Traceback" not in captured.err


def test_main_normalizes_shell_style_line_continuations(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """query_db should tolerate shell-style backslash-newline SQL wrapping."""
    captured_sql: dict[str, str] = {}

    monkeypatch.setattr(query_db, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(query_db.local_store, "get_connection", lambda: _DummyConnection())
    monkeypatch.setattr(query_db.local_store, "ensure_schema", lambda conn: None)

    def _fake_execute_sql(conn, sql):
        del conn
        captured_sql["sql"] = sql
        return [{"ok": True}]

    monkeypatch.setattr(query_db.local_store, "execute_sql", _fake_execute_sql)
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "query_db.py",
            "SELECT msg_id, \\\ncontent FROM messages WHERE msg_id = 'm1'",
        ],
    )

    query_db.main()

    assert captured_sql["sql"] == "SELECT msg_id, content FROM messages WHERE msg_id = 'm1'"
    assert capsys.readouterr().out.strip() == '[\n  {\n    "ok": true\n  }\n]'
