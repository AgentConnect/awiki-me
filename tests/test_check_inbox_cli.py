"""Unit tests for check_inbox CLI routing, scope filtering, and auto-mark-read.

[INPUT]: check_inbox CLI helpers, monkeypatched async entrypoints, and CLI argv
[OUTPUT]: Regression coverage for inbox scope filtering, local-cache vs HTTP
          fallback reads, auto-mark-read, and group-history dispatch
[POS]: Message CLI unit tests for unified direct/group inbox behavior

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import json
import sys
import asyncio
from pathlib import Path

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

import check_inbox as check_inbox_cli  # noqa: E402
import local_store  # noqa: E402


class _DummyAsyncClient:
    """Minimal async context manager used by mocked inbox RPC tests."""

    async def __aenter__(self) -> "_DummyAsyncClient":
        return self

    async def __aexit__(self, exc_type, exc, tb) -> None:
        del exc_type, exc, tb


class TestCheckInboxCli:
    """Test inbox CLI parsing and group-aware routing."""

    def test_check_inbox_uses_local_cache_in_websocket_mode(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        remote_calls: list[str] = []

        monkeypatch.setattr(
            check_inbox_cli,
            "create_authenticator",
            lambda credential_name, config: (object(), {"did": "did:alice"}),
        )
        monkeypatch.setattr(check_inbox_cli, "is_websocket_mode", lambda config: True)
        monkeypatch.setattr(
            check_inbox_cli,
            "ensure_listener_runtime",
            lambda credential_name, config=None: {"was_running": True},
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "_load_local_messages",
            lambda **kwargs: [
                {
                    "id": "local-1",
                    "type": "text",
                    "sender_did": "did:bob",
                    "content": "local hello",
                }
            ],
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "create_molt_message_client",
            lambda config: _DummyAsyncClient(),
        )

        async def _fake_authenticated_rpc_call(
            client,
            endpoint: str,
            method: str,
            params: dict[str, object],
            *,
            auth: object,
            credential_name: str,
        ) -> dict[str, object]:
            del client, endpoint, auth, credential_name
            remote_calls.append(method)
            assert method == "get_inbox"
            return {
                "messages": [
                    {
                        "id": "remote-1",
                        "type": "text",
                        "sender_did": "did:carol",
                        "content": "remote hello",
                    }
                ],
                "total": 1,
            }

        monkeypatch.setattr(
            check_inbox_cli,
            "authenticated_rpc_call",
            _fake_authenticated_rpc_call,
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "_store_inbox_messages",
            lambda credential_name, my_did, inbox: None,
        )

        asyncio.run(check_inbox_cli.check_inbox("alice", 5, "all", False))

        payload = json.loads(capsys.readouterr().out)
        assert payload["source"] == "local_ws_cache"
        assert payload["http_sync"]["status"] == "ok"
        assert remote_calls == ["get_inbox"]
        assert {message["content"] for message in payload["messages"]} == {
            "local hello",
            "remote hello",
        }

    def test_check_inbox_keeps_local_cache_when_websocket_http_sync_fails(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        monkeypatch.setattr(
            check_inbox_cli,
            "create_authenticator",
            lambda credential_name, config: (object(), {"did": "did:alice"}),
        )
        monkeypatch.setattr(check_inbox_cli, "is_websocket_mode", lambda config: True)
        monkeypatch.setattr(
            check_inbox_cli,
            "ensure_listener_runtime",
            lambda credential_name, config=None: {"was_running": True},
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "_load_local_messages",
            lambda **kwargs: [
                {
                    "id": "local-1",
                    "type": "text",
                    "sender_did": "did:bob",
                    "content": "local hello",
                }
            ],
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "create_molt_message_client",
            lambda config: _DummyAsyncClient(),
        )

        async def _raise_http_error(
            client,
            endpoint: str,
            method: str,
            params: dict[str, object],
            *,
            auth: object,
            credential_name: str,
        ) -> dict[str, object]:
            del client, endpoint, method, params, auth, credential_name
            raise RuntimeError("boom")

        monkeypatch.setattr(
            check_inbox_cli,
            "authenticated_rpc_call",
            _raise_http_error,
        )

        asyncio.run(check_inbox_cli.check_inbox("alice", 5, "all", False))

        payload = json.loads(capsys.readouterr().out)
        assert payload["source"] == "local_ws_cache"
        assert payload["messages"][0]["content"] == "local hello"
        assert payload["http_sync"]["status"] == "error"

    def test_check_inbox_falls_back_to_http_when_websocket_mode_is_degraded(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        monkeypatch.setattr(
            check_inbox_cli,
            "create_authenticator",
            lambda credential_name, config: (object(), {"did": "did:alice"}),
        )
        monkeypatch.setattr(check_inbox_cli, "is_websocket_mode", lambda config: True)
        monkeypatch.setattr(
            check_inbox_cli,
            "ensure_listener_runtime",
            lambda credential_name, config=None: {
                "was_running": False,
                "running": False,
                "auto_restart_paused": False,
                "consecutive_restart_failures": 1,
            },
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "create_molt_message_client",
            lambda config: _DummyAsyncClient(),
        )

        async def _fake_authenticated_rpc_call(
            client,
            endpoint: str,
            method: str,
            params: dict[str, object],
            *,
            auth: object,
            credential_name: str,
        ) -> dict[str, object]:
            del client, endpoint, method, params, auth, credential_name
            return {
                "messages": [
                    {
                        "id": "msg-1",
                        "type": "text",
                        "sender_did": "did:bob",
                        "content": "hello",
                    }
                ],
                "total": 1,
            }

        monkeypatch.setattr(
            check_inbox_cli,
            "authenticated_rpc_call",
            _fake_authenticated_rpc_call,
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "_store_inbox_messages",
            lambda credential_name, my_did, inbox: None,
        )

        async def _fake_auto_process_e2ee_messages(
            messages: list[dict[str, object]],
            *,
            local_did: str,
            auth: object,
            credential_name: str,
        ) -> tuple[list[dict[str, object]], list[str], object]:
            del local_did, auth, credential_name
            return messages, [], object()

        monkeypatch.setattr(
            check_inbox_cli,
            "_auto_process_e2ee_messages",
            _fake_auto_process_e2ee_messages,
        )

        asyncio.run(check_inbox_cli.check_inbox("alice", 5, "all", False))

        payload = json.loads(capsys.readouterr().out)
        assert payload["source"] == "remote_http_fallback"
        assert payload["messages"][0]["content"] == "hello"

    def test_filter_messages_by_scope_variants(self) -> None:
        messages = [
            {"id": "dm_1", "group_id": None, "content": "private"},
            {"id": "grp_1", "group_id": "group-1", "content": "group"},
        ]

        assert check_inbox_cli._filter_messages_by_scope(messages, "all") == messages
        assert check_inbox_cli._filter_messages_by_scope(messages, "direct") == [
            messages[0]
        ]
        assert check_inbox_cli._filter_messages_by_scope(messages, "group") == [
            messages[1]
        ]

    def test_parse_group_history_target(self) -> None:
        assert (
            check_inbox_cli._parse_group_history_target(
                "group:321cf92a-b54a-4e66-b791-f883c9bb4b26"
            )
            == "321cf92a-b54a-4e66-b791-f883c9bb4b26"
        )
        assert check_inbox_cli._parse_group_history_target("did:wba:example:user:alice") is None

    def test_main_dispatches_group_history_from_group_id(
        self,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        captured: dict[str, object] = {}

        async def _fake_get_group_history(
            group_id: str,
            credential_name: str,
            limit: int,
            since_seq: int | None,
        ) -> None:
            captured.update(
                {
                    "group_id": group_id,
                    "credential_name": credential_name,
                    "limit": limit,
                    "since_seq": since_seq,
                }
            )

        monkeypatch.setattr(
            check_inbox_cli, "configure_logging", lambda **kwargs: None
        )
        monkeypatch.setattr(
            check_inbox_cli, "get_group_history", _fake_get_group_history
        )
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "check_inbox.py",
                "--group-id",
                "grp_1",
                "--credential",
                "bob",
                "--limit",
                "30",
                "--since-seq",
                "7",
            ],
        )

        check_inbox_cli.main()

        assert captured == {
            "group_id": "grp_1",
            "credential_name": "bob",
            "limit": 30,
            "since_seq": 7,
        }

    def test_main_dispatches_group_history_from_history_prefix(
        self,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        captured: dict[str, object] = {}

        async def _fake_get_group_history(
            group_id: str,
            credential_name: str,
            limit: int,
            since_seq: int | None,
        ) -> None:
            captured.update(
                {
                    "group_id": group_id,
                    "credential_name": credential_name,
                    "limit": limit,
                    "since_seq": since_seq,
                }
            )

        monkeypatch.setattr(
            check_inbox_cli, "configure_logging", lambda **kwargs: None
        )
        monkeypatch.setattr(
            check_inbox_cli, "get_group_history", _fake_get_group_history
        )
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "check_inbox.py",
                "--history",
                "group:grp_1",
                "--credential",
                "bob",
            ],
        )

        check_inbox_cli.main()

        assert captured == {
            "group_id": "grp_1",
            "credential_name": "bob",
            "limit": 20,
            "since_seq": None,
        }

    def test_main_dispatches_inbox_with_scope(
        self,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        captured: dict[str, object] = {}

        async def _fake_check_inbox(
            credential_name: str,
            limit: int,
            scope: str,
        ) -> None:
            captured.update(
                {
                    "credential_name": credential_name,
                    "limit": limit,
                    "scope": scope,
                    "mark_read": False,
                }
            )

        monkeypatch.setattr(
            check_inbox_cli, "configure_logging", lambda **kwargs: None
        )
        monkeypatch.setattr(check_inbox_cli, "check_inbox", _fake_check_inbox)
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "check_inbox.py",
                "--credential",
                "bob",
                "--scope",
                "group",
                "--limit",
                "40",
            ],
        )

        check_inbox_cli.main()

        assert captured == {
            "credential_name": "bob",
            "limit": 40,
            "scope": "group",
            "mark_read": False,
        }

    def test_main_dispatches_inbox_auto_mark_read(
        self,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        captured: dict[str, object] = {}

        async def _fake_check_inbox(
            credential_name: str,
            limit: int,
            scope: str,
            mark_read: bool = False,
        ) -> None:
            captured.update(
                {
                    "credential_name": credential_name,
                    "limit": limit,
                    "scope": scope,
                    "mark_read": mark_read,
                }
            )

        monkeypatch.setattr(
            check_inbox_cli, "configure_logging", lambda **kwargs: None
        )
        monkeypatch.setattr(check_inbox_cli, "check_inbox", _fake_check_inbox)
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "check_inbox.py",
                "--credential",
                "bob",
                "--mark-read",
                "--limit",
                "15",
            ],
        )

        check_inbox_cli.main()

        assert captured == {
            "credential_name": "bob",
            "limit": 15,
            "scope": "all",
            "mark_read": True,
        }

    def test_main_dispatches_explicit_mark_read_ids(
        self,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        captured: dict[str, object] = {}

        async def _fake_mark_read(
            message_ids: list[str],
            credential_name: str,
        ) -> None:
            captured.update(
                {
                    "message_ids": message_ids,
                    "credential_name": credential_name,
                }
            )

        monkeypatch.setattr(
            check_inbox_cli, "configure_logging", lambda **kwargs: None
        )
        monkeypatch.setattr(check_inbox_cli, "mark_read", _fake_mark_read)
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "check_inbox.py",
                "--credential",
                "bob",
                "--mark-read",
                "msg_1",
                "msg_2",
            ],
        )

        check_inbox_cli.main()

        assert captured == {
            "message_ids": ["msg_1", "msg_2"],
            "credential_name": "bob",
        }

    def test_main_rejects_since_seq_without_group_history(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys,
    ) -> None:
        monkeypatch.setattr(
            check_inbox_cli, "configure_logging", lambda **kwargs: None
        )
        monkeypatch.setattr(
            sys,
            "argv",
            [
                "check_inbox.py",
                "--credential",
                "bob",
                "--since-seq",
                "7",
            ],
        )

        with pytest.raises(SystemExit):
            check_inbox_cli.main()

        assert "--since-seq only supports group history reads" in capsys.readouterr().err

    def test_resolve_group_since_seq_prefers_explicit_argument(
        self,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))

        since_seq, cursor_source = check_inbox_cli._resolve_group_since_seq(
            owner_did="did:alice",
            group_id="grp_1",
            explicit_since_seq=9,
        )

        assert since_seq == 9
        assert cursor_source == "argument"

    def test_resolve_group_since_seq_reads_group_snapshot_first(
        self,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
        conn = local_store.get_connection()
        try:
            local_store.ensure_schema(conn)
            local_store.upsert_group(
                conn,
                owner_did="did:alice",
                group_id="grp_1",
                last_synced_seq=12,
                credential_name="alice",
            )
        finally:
            conn.close()

        since_seq, cursor_source = check_inbox_cli._resolve_group_since_seq(
            owner_did="did:alice",
            group_id="grp_1",
            explicit_since_seq=None,
        )

        assert since_seq == 12
        assert cursor_source == "group_snapshot"

    def test_resolve_group_since_seq_falls_back_to_message_cache(
        self,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
        conn = local_store.get_connection()
        try:
            local_store.ensure_schema(conn)
            local_store.store_message(
                conn,
                msg_id="msg_1",
                owner_did="did:alice",
                thread_id=local_store.make_thread_id("did:alice", group_id="grp_1"),
                direction=0,
                sender_did="did:bob",
                group_id="grp_1",
                content_type="group_user",
                content="hello",
                server_seq=21,
                sent_at="2026-03-10T01:00:00+00:00",
                credential_name="alice",
            )
        finally:
            conn.close()

        since_seq, cursor_source = check_inbox_cli._resolve_group_since_seq(
            owner_did="did:alice",
            group_id="grp_1",
            explicit_since_seq=None,
        )

        assert since_seq == 21
        assert cursor_source == "message_cache"

    def test_get_group_history_uses_resolved_local_cursor(
        self,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        captured: dict[str, object] = {}

        monkeypatch.setattr(
            check_inbox_cli,
            "create_authenticator",
            lambda credential_name, config: (
                object(),
                {"did": "did:alice", "handle": "alice.awiki.ai"},
            ),
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "_resolve_group_since_seq",
            lambda owner_did, group_id, explicit_since_seq: (22, "group_snapshot"),
        )

        async def _fake_group_rpc_call(**kwargs):
            captured.update(kwargs)
            return {"messages": [], "next_since_seq": 22}

        monkeypatch.setattr(
            check_inbox_cli, "_group_rpc_call", _fake_group_rpc_call
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "_persist_group_messages",
            lambda **kwargs: None,
        )

        import asyncio

        asyncio.run(
            check_inbox_cli.get_group_history(
                "grp_1",
                credential_name="alice",
                limit=30,
                since_seq=None,
            )
        )

        assert captured["params"] == {"group_id": "grp_1", "limit": 30, "since_seq": 22}

    def test_check_inbox_auto_marks_visible_messages_as_read(
        self,
        monkeypatch: pytest.MonkeyPatch,
        capsys: pytest.CaptureFixture[str],
    ) -> None:
        marked_message_ids: list[str] = []

        async def _fake_authenticated_rpc_call(
            client,
            endpoint: str,
            method: str,
            params: dict[str, object],
            *,
            auth: object,
            credential_name: str,
        ) -> dict[str, object]:
            del client, endpoint, auth, credential_name
            if method == "get_inbox":
                return {
                    "messages": [
                        {
                            "id": "plain-1",
                            "type": "text",
                            "sender_did": "did:bob",
                            "content": "hello",
                        },
                        {
                            "id": "cipher-1",
                            "type": "e2ee_msg",
                            "sender_did": "did:bob",
                            "content": '{"session_id":"sess-1"}',
                        },
                    ],
                    "total": 2,
                }
            if method == "mark_read":
                marked_message_ids.extend(params["message_ids"])  # type: ignore[index]
                return {"updated_count": len(params["message_ids"])}  # type: ignore[index]
            raise AssertionError(f"Unexpected method: {method}")

        async def _fake_auto_process_e2ee_messages(
            messages: list[dict[str, object]],
            *,
            local_did: str,
            auth: object,
            credential_name: str,
        ) -> tuple[list[dict[str, object]], list[str], object]:
            del local_did, auth, credential_name
            return messages, ["cipher-1"], object()

        monkeypatch.setattr(
            check_inbox_cli,
            "create_authenticator",
            lambda credential_name, config: (object(), {"did": "did:alice"}),
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "create_molt_message_client",
            lambda config: _DummyAsyncClient(),
        )
        monkeypatch.setattr(check_inbox_cli, "is_websocket_mode", lambda config: False)
        monkeypatch.setattr(
            check_inbox_cli,
            "authenticated_rpc_call",
            _fake_authenticated_rpc_call,
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "_store_inbox_messages",
            lambda credential_name, my_did, inbox: None,
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "_auto_process_e2ee_messages",
            _fake_auto_process_e2ee_messages,
        )
        monkeypatch.setattr(
            check_inbox_cli,
            "_mark_local_messages_read",
            lambda credential_name, owner_did, message_ids: None,
        )

        import asyncio

        asyncio.run(
            check_inbox_cli.check_inbox(
                credential_name="alice",
                limit=20,
                scope="all",
                mark_read=True,
            )
        )

        payload = json.loads(capsys.readouterr().out)
        assert payload["total"] == 2
        assert marked_message_ids == ["cipher-1", "plain-1"]

    def test_load_local_messages_excludes_rows_marked_read_from_inbox(
        self,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
        conn = local_store.get_connection()
        try:
            local_store.ensure_schema(conn)
            thread_id = local_store.make_thread_id("did:alice", peer_did="did:bob")
            local_store.store_message(
                conn,
                msg_id="unread-1",
                owner_did="did:alice",
                thread_id=thread_id,
                direction=0,
                sender_did="did:bob",
                receiver_did="did:alice",
                content_type="text",
                content="hello",
                credential_name="alice",
            )
            local_store.store_message(
                conn,
                msg_id="read-1",
                owner_did="did:alice",
                thread_id=thread_id,
                direction=0,
                sender_did="did:bob",
                receiver_did="did:alice",
                content_type="text",
                content="old hello",
                is_read=True,
                credential_name="alice",
            )
        finally:
            conn.close()

        messages = check_inbox_cli._load_local_messages(
            owner_did="did:alice",
            limit=10,
            incoming_only=True,
        )

        assert [message["id"] for message in messages] == ["unread-1"]

    def test_load_local_history_keeps_sent_encrypted_messages(
        self,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
        conn = local_store.get_connection()
        try:
            local_store.ensure_schema(conn)
            local_store.store_message(
                conn,
                msg_id="cipher-out-1",
                owner_did="did:alice",
                thread_id=local_store.make_thread_id("did:alice", peer_did="did:bob"),
                direction=1,
                sender_did="did:alice",
                receiver_did="did:bob",
                content_type="text",
                content="secret hello",
                is_e2ee=True,
                credential_name="alice",
            )
        finally:
            conn.close()

        messages = check_inbox_cli._load_local_messages(
            owner_did="did:alice",
            limit=10,
            peer_did="did:bob",
            incoming_only=False,
        )

        assert len(messages) == 1
        assert messages[0]["id"] == "cipher-out-1"
        assert messages[0]["content"] == "secret hello"
        assert messages[0]["_e2ee"] is True
