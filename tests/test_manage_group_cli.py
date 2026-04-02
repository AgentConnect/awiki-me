"""Unit tests for unified group CLI behavior.

[INPUT]: manage_group CLI entrypoints, monkeypatched async RPC/doc clients, and CLI argv
[OUTPUT]: Regression coverage for join argument handling, JSON-RPC rendering, and fetch-doc fallback
[POS]: Unified group CLI unit tests

[PROTOCOL]:
1. Update this header when logic changes
2. Check the folder's CLAUDE.md after updating
"""

from __future__ import annotations

import sys
from pathlib import Path

import httpx
import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

import manage_group as manage_group_cli  # noqa: E402
from utils.rpc import JsonRpcError  # noqa: E402


class TestManageGroupCli:
    """Test unified-group CLI parsing and error handling."""

    def test_join_rejects_group_id_with_guidance(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys,
    ) -> None:
        monkeypatch.setattr(manage_group_cli, "configure_logging", lambda **kwargs: None)
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "manage_group.py",
                "--join",
                "--group-id",
                "grp_1",
                "--join-code",
                "314159",
            ],
        )

        with pytest.raises(SystemExit):
            manage_group_cli.main()

        assert "can only be joined with the global 6-digit join-code" in capsys.readouterr().err

    def test_create_dispatches_with_limits_and_prompt(
        self,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        captured: dict[str, object] = {}

        async def _fake_create_group(**kwargs):
            captured.update(kwargs)

        monkeypatch.setattr(manage_group_cli, "configure_logging", lambda **kwargs: None)
        monkeypatch.setattr(manage_group_cli, "create_group", _fake_create_group)
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "manage_group.py",
                "--create",
                "--group-name",
                "OpenClaw Meetup",
                "--slug",
                "openclaw-meetup",
                "--description",
                "desc",
                "--goal",
                "goal",
                "--rules",
                "rules",
                "--message-prompt",
                "prompt",
                "--member-max-messages",
                "3",
                "--member-max-total-chars",
                "1500",
            ],
        )

        manage_group_cli.main()

        assert captured == {
            "name": "OpenClaw Meetup",
            "slug": "openclaw-meetup",
            "description": "desc",
            "goal": "goal",
            "rules": "rules",
            "message_prompt": "prompt",
            "member_max_messages": 3,
            "member_max_total_chars": 1500,
            "join_enabled": True,
            "credential_name": "default",
        }

    def test_update_dispatches_new_limit_fields(
        self,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        captured: dict[str, object] = {}

        async def _fake_update_group(**kwargs):
            captured.update(kwargs)

        monkeypatch.setattr(manage_group_cli, "configure_logging", lambda **kwargs: None)
        monkeypatch.setattr(manage_group_cli, "update_group", _fake_update_group)
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "manage_group.py",
                "--update",
                "--group-id",
                "grp_1",
                "--member-max-messages",
                "5",
                "--member-max-total-chars",
                "2000",
            ],
        )

        manage_group_cli.main()

        assert captured["group_id"] == "grp_1"
        assert captured["member_max_messages"] == 5
        assert captured["member_max_total_chars"] == 2000

    def test_join_dispatches_with_join_code_only(
        self,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        captured: dict[str, object] = {}

        async def _fake_join_group(**kwargs):
            captured.update(kwargs)

        monkeypatch.setattr(manage_group_cli, "configure_logging", lambda **kwargs: None)
        monkeypatch.setattr(manage_group_cli, "join_group", _fake_join_group)
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "manage_group.py",
                "--join",
                "--join-code",
                "314159",
                "--credential",
                "bob",
            ],
        )

        manage_group_cli.main()

        assert captured == {"join_code": "314159", "credential_name": "bob"}

    def test_join_accepts_legacy_passcode_alias(
        self,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        captured: dict[str, object] = {}

        async def _fake_join_group(**kwargs):
            captured.update(kwargs)

        monkeypatch.setattr(manage_group_cli, "configure_logging", lambda **kwargs: None)
        monkeypatch.setattr(manage_group_cli, "join_group", _fake_join_group)
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "manage_group.py",
                "--join",
                "--passcode",
                "314159",
                "--credential",
                "bob",
            ],
        )

        manage_group_cli.main()

        assert captured == {"join_code": "314159", "credential_name": "bob"}

    def test_jsonrpc_error_is_rendered_as_json(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys,
    ) -> None:
        async def _fake_get_group(**kwargs):
            raise JsonRpcError(-32004, "group join is disabled")

        monkeypatch.setattr(manage_group_cli, "configure_logging", lambda **kwargs: None)
        monkeypatch.setattr(manage_group_cli, "get_group", _fake_get_group)
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "manage_group.py",
                "--get",
                "--group-id",
                "grp_1",
            ],
        )

        with pytest.raises(SystemExit) as exc_info:
            manage_group_cli.main()

        assert exc_info.value.code == 1
        assert '"error_type": "jsonrpc"' in capsys.readouterr().out

    def test_fetch_doc_retries_with_x_handle_after_connect_error(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys,
    ) -> None:
        class _FakeResponse:
            def __init__(self, *, status_code: int, text: str = "") -> None:
                self.status_code = status_code
                self.text = text

            def raise_for_status(self) -> None:
                request = httpx.Request("GET", "https://awiki.ai")
                response = httpx.Response(self.status_code, request=request, text=self.text)
                if self.status_code >= 400:
                    raise httpx.HTTPStatusError("boom", request=request, response=response)

        class _FakeClient:
            def __init__(self) -> None:
                self.calls: list[dict[str, object]] = []

            async def __aenter__(self):
                return self

            async def __aexit__(self, exc_type, exc, tb):
                return None

            async def get(self, url: str, headers: dict[str, str] | None = None, timeout: float = 10.0):
                self.calls.append({"url": url, "headers": headers or {}, "timeout": timeout})
                if len(self.calls) == 1:
                    raise httpx.ConnectError("dns failed")
                return _FakeResponse(status_code=200, text="# Group Doc")

        fake_client = _FakeClient()
        monkeypatch.setattr(manage_group_cli.httpx, "AsyncClient", lambda **kwargs: fake_client)
        monkeypatch.setattr(manage_group_cli, "configure_logging", lambda **kwargs: None)
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "manage_group.py",
                "--fetch-doc",
                "--doc-url",
                "https://alice.awiki.ai/group/openclaw-meetup.md",
                "--credential",
                "default",
            ],
        )
        monkeypatch.setattr(
            manage_group_cli,
            "_get_identity_data_or_exit",
            lambda credential_name, config: {"did": "did:alice", "handle": "alice"},
        )

        manage_group_cli.main()

        assert len(fake_client.calls) == 2
        assert fake_client.calls[1]["headers"]["X-Handle"] == "alice"
        assert "# Group Doc" in capsys.readouterr().out
