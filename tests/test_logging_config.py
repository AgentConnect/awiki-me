"""Unit tests for the shared logging configuration module."""

from __future__ import annotations

import logging
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Add scripts/ to sys.path so we can import utils.logging_config
_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

from utils.logging_config import (  # noqa: E402
    DailyRetentionFileHandler,
    cleanup_log_files,
    get_log_dir,
)


class _MutableClock:
    """Simple mutable clock for handler tests."""

    def __init__(self, current: datetime) -> None:
        self.current = current

    def now(self) -> datetime:
        return self.current


def _write_log_file(log_dir: Path, day: datetime, content: str) -> Path:
    """Create a managed log file with deterministic content."""
    path = log_dir / f"awiki-agent-{day.date().isoformat()}.log"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


def test_get_log_dir_uses_data_dir(tmp_path, monkeypatch) -> None:
    """Log files should live under <DATA_DIR>/logs."""
    monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))

    log_dir = get_log_dir()

    assert log_dir == tmp_path / "logs"
    assert log_dir.exists()


def test_cleanup_log_files_removes_expired_days(tmp_path) -> None:
    """Files older than the retention window should be removed."""
    log_dir = tmp_path / "logs"
    now = datetime(2026, 3, 17, 8, 0, tzinfo=timezone.utc)

    for offset in range(17):
        day = now - timedelta(days=16 - offset)
        _write_log_file(log_dir, day, f"log-{offset}")

    deleted = cleanup_log_files(log_dir, now=now, max_retention_days=15)

    remaining = sorted(path.name for path in log_dir.glob("*.log"))
    assert [path.name for path in deleted] == [
        "awiki-agent-2026-03-01.log",
        "awiki-agent-2026-03-02.log",
    ]
    assert remaining[0] == "awiki-agent-2026-03-03.log"
    assert remaining[-1] == "awiki-agent-2026-03-17.log"
    assert len(remaining) == 15


def test_cleanup_log_files_enforces_total_size_limit(tmp_path) -> None:
    """Size cleanup should delete the oldest files first."""
    log_dir = tmp_path / "logs"
    now = datetime(2026, 3, 3, 8, 0, tzinfo=timezone.utc)

    _write_log_file(log_dir, datetime(2026, 3, 1, tzinfo=timezone.utc), "aaaaa")
    _write_log_file(log_dir, datetime(2026, 3, 2, tzinfo=timezone.utc), "bbbbb")
    _write_log_file(log_dir, datetime(2026, 3, 3, tzinfo=timezone.utc), "ccccc")

    deleted = cleanup_log_files(
        log_dir,
        now=now,
        max_retention_days=15,
        max_total_size_bytes=10,
    )

    remaining = sorted(path.name for path in log_dir.glob("*.log"))
    assert [path.name for path in deleted] == ["awiki-agent-2026-03-01.log"]
    assert remaining == [
        "awiki-agent-2026-03-02.log",
        "awiki-agent-2026-03-03.log",
    ]


def test_daily_retention_file_handler_writes_one_file_per_day(tmp_path) -> None:
    """The handler should rotate to a new file when the day changes."""
    log_dir = tmp_path / "logs"
    clock = _MutableClock(datetime(2026, 3, 8, 9, 0, tzinfo=timezone.utc))
    handler = DailyRetentionFileHandler(
        log_dir=log_dir,
        clock=clock.now,
        cleanup_interval_seconds=1,
    )
    handler.setFormatter(logging.Formatter("%(message)s"))

    logger = logging.Logger("test_daily_handler")
    logger.setLevel(logging.INFO)
    logger.addHandler(handler)

    try:
        logger.info("first-day")
        clock.current = datetime(2026, 3, 9, 9, 0, tzinfo=timezone.utc)
        logger.info("second-day")
    finally:
        logger.removeHandler(handler)
        handler.close()

    first_file = log_dir / "awiki-agent-2026-03-08.log"
    second_file = log_dir / "awiki-agent-2026-03-09.log"

    assert first_file.exists()
    assert second_file.exists()
    assert "first-day" in first_file.read_text(encoding="utf-8")
    assert "second-day" in second_file.read_text(encoding="utf-8")


def test_configure_logging_mirrors_print_to_daily_log(tmp_path) -> None:
    """configure_logging should mirror stdout prints into the daily log file."""
    env = os.environ.copy()
    env["AWIKI_DATA_DIR"] = str(tmp_path)
    env["PYTHONPATH"] = str(_scripts_dir)

    script = """
from utils.logging_config import configure_logging
configure_logging(console_level=None, mirror_stdio=True)
print("print-to-log")
"""
    result = subprocess.run(
        [sys.executable, "-c", script],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        check=True,
    )

    log_dir = tmp_path / "logs"
    log_files = sorted(log_dir.glob("awiki-agent-*.log"))

    assert "print-to-log" in result.stdout
    assert len(log_files) == 1
    assert "print-to-log" in log_files[0].read_text(encoding="utf-8")
