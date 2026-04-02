"""Unit tests for manage_content CLI error rendering.

[INPUT]: manage_content CLI entrypoint with monkeypatched async handlers and argv
[OUTPUT]: Regression coverage for structured JsonRpcError and generic error output
[POS]: CLI unit tests for content page management failures

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

import manage_content  # noqa: E402


def test_main_renders_jsonrpc_error_as_structured_json(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """CLI should return structured JSON when a JSON-RPC error occurs."""

    async def _fake_create_page(**kwargs) -> None:
        del kwargs
        raise manage_content.JsonRpcError(
            -32001,
            "Slug already exists",
            {"slug": "dup"},
        )

    monkeypatch.setattr(manage_content, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(manage_content, "create_page", _fake_create_page)
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_content.py",
            "--create",
            "--slug",
            "dup",
            "--title",
            "Title",
        ],
    )

    with pytest.raises(SystemExit) as exc_info:
        manage_content.main()

    assert exc_info.value.code == 1
    captured = json.loads(capsys.readouterr().out)
    assert captured == {
        "status": "error",
        "error_type": "jsonrpc",
        "code": -32001,
        "message": "Slug already exists",
        "data": {"slug": "dup"},
    }


def test_main_renders_generic_error_as_structured_json(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """CLI should return structured JSON for unexpected failures too."""

    async def _fake_list_pages(credential_name: str) -> None:
        del credential_name
        raise RuntimeError("boom")

    monkeypatch.setattr(manage_content, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(manage_content, "list_pages", _fake_list_pages)
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_content.py",
            "--list",
        ],
    )

    with pytest.raises(SystemExit) as exc_info:
        manage_content.main()

    assert exc_info.value.code == 1
    captured = json.loads(capsys.readouterr().out)
    assert captured == {
        "status": "error",
        "error_type": "RuntimeError",
        "message": "boom",
    }
