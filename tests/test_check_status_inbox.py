"""Tests for check_status inbox surfacing and automatic E2EE delivery.

[INPUT]: check_status inbox helpers with monkeypatched RPC/auth/E2EE dependencies
[OUTPUT]: Regression coverage for plaintext delivery, handshake summaries,
          listener degraded-mode fallback, and auto-E2EE metrics in
          check_status.py
[POS]: Unit tests for user-visible inbox reporting in the unified status CLI

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import asyncio
import json
import sys
from pathlib import Path
from typing import Any

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

import check_status  # noqa: E402


class _DummyAsyncClient:
    """Minimal async context manager used by mocked RPC calls."""

    async def __aenter__(self) -> "_DummyAsyncClient":
        return self

    async def __aexit__(self, exc_type, exc, tb) -> None:
        del exc_type, exc, tb


class _FakeE2eeClient:
    """Small E2EE client stub for inbox processing tests."""

    def __init__(self) -> None:
        self.process_calls: list[tuple[str, dict[str, Any]]] = []
        self.decrypt_calls: list[dict[str, Any]] = []

    async def process_e2ee_message(
        self,
        msg_type: str,
        content: dict[str, Any],
    ) -> list[tuple[str, dict[str, Any]]]:
        self.process_calls.append((msg_type, content))
        return [("e2ee_ack", {"session_id": content.get("session_id")})]

    def has_session_id(self, session_id: str | None) -> bool:
        return session_id == "sess-1"

    def decrypt_message(self, content: dict[str, Any]) -> tuple[str, str]:
        self.decrypt_calls.append(content)
        return "text", "Secret hello"

    def export_state(self) -> dict[str, Any]:
        return {"sessions": [{"session_id": "sess-1"}]}


def test_summarize_inbox_hides_protocol_messages_from_user_output(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Summary mode should keep protocol messages hidden from user output."""

    async def _fake_authenticated_rpc_call(
        client,
        endpoint: str,
        method: str,
        params: dict[str, Any],
        *,
        auth: Any,
        credential_name: str,
    ) -> dict[str, Any]:
        del client, endpoint, params, auth, credential_name
        assert method == "get_inbox"
        return {
            "messages": [
                {
                    "id": "init-1",
                    "type": "e2ee_init",
                    "sender_did": "did:bob",
                    "content": json.dumps({"session_id": "sess-1"}),
                    "created_at": "2026-03-11T09:00:00Z",
                },
                {
                    "id": "plain-1",
                    "type": "text",
                    "sender_did": "did:carol",
                    "content": "Hello",
                    "created_at": "2026-03-11T09:05:00Z",
                },
            ]
        }

    monkeypatch.setattr(
        check_status, "create_authenticator", lambda credential_name, config: (
            object(),
            {"did": "did:alice"},
        )
    )
    monkeypatch.setattr(
        check_status, "create_molt_message_client", lambda config: _DummyAsyncClient()
    )
    monkeypatch.setattr(
        check_status, "authenticated_rpc_call", _fake_authenticated_rpc_call
    )

    report = asyncio.run(check_status.summarize_inbox("alice"))

    assert report["status"] == "ok"
    assert report["total"] == 1
    assert report["messages"] == [
        {
            "id": "plain-1",
            "type": "text",
            "sender_did": "did:carol",
            "content": "Hello",
            "created_at": "2026-03-11T09:05:00Z",
        }
    ]


def test_check_identity_bootstraps_missing_jwt_via_did_auth(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Identity status should stay OK when a missing JWT is re-issued automatically."""
    credential_data = {
        "did": "did:alice",
        "name": "Alice",
        "jwt_token": None,
    }

    async def _fake_authenticated_rpc_call(
        client,
        endpoint: str,
        method: str,
        params: dict[str, Any] | None = None,
        request_id: int | str = 1,
        *,
        auth: Any,
        credential_name: str,
    ) -> dict[str, Any]:
        del client, endpoint, method, params, request_id, auth, credential_name
        credential_data["jwt_token"] = "jwt-new"
        return {"did": "did:alice", "name": "Alice"}

    monkeypatch.setattr(check_status, "load_identity", lambda credential_name: dict(credential_data))
    monkeypatch.setattr(
        check_status, "create_authenticator", lambda credential_name, config: (
            object(),
            dict(credential_data),
        )
    )
    monkeypatch.setattr(
        check_status, "create_user_service_client", lambda config: _DummyAsyncClient()
    )
    monkeypatch.setattr(
        check_status, "authenticated_rpc_call", _fake_authenticated_rpc_call
    )

    result = asyncio.run(check_status.check_identity("alice"))

    assert result["status"] == "ok"
    assert result["jwt_valid"] is True
    assert result["jwt_refreshed"] is True
    assert credential_data["jwt_token"] == "jwt-new"


def test_auto_e2ee_builds_plaintext_inbox_report(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Auto-E2EE mode should surface decrypted plaintext and mark handled items read."""
    fake_client = _FakeE2eeClient()
    sent_calls: list[tuple[str, dict[str, Any]]] = []
    marked_read: list[str] = []

    async def _fake_authenticated_rpc_call(
        client,
        endpoint: str,
        method: str,
        params: dict[str, Any],
        *,
        auth: Any,
        credential_name: str,
    ) -> dict[str, Any]:
        del client, endpoint, auth, credential_name
        if method == "get_inbox":
            return {
                "messages": [
                    {
                        "id": "init-1",
                        "type": "e2ee_init",
                        "sender_did": "did:bob",
                        "content": json.dumps(
                            {"session_id": "sess-1", "sender_did": "did:bob"}
                        ),
                        "created_at": "2026-03-11T09:00:00Z",
                    },
                    {
                        "id": "cipher-1",
                        "type": "e2ee_msg",
                        "sender_did": "did:bob",
                        "content": json.dumps({"session_id": "sess-1"}),
                        "created_at": "2026-03-11T09:02:00Z",
                    },
                    {
                        "id": "plain-1",
                        "type": "text",
                        "sender_did": "did:carol",
                        "content": "Hello",
                        "created_at": "2026-03-11T09:01:00Z",
                    },
                ]
            }
        if method == "send":
            sent_calls.append((params["type"], json.loads(params["content"])))
            return {"id": "resp-1"}
        if method == "mark_read":
            marked_read.extend(params["message_ids"])
            return {"ok": True}
        raise AssertionError(f"Unexpected RPC method: {method}")

    monkeypatch.setattr(
        check_status, "create_authenticator", lambda credential_name, config: (
            object(),
            {"did": "did:alice"},
        )
    )
    monkeypatch.setattr(
        check_status, "create_molt_message_client", lambda config: _DummyAsyncClient()
    )
    monkeypatch.setattr(
        check_status, "authenticated_rpc_call", _fake_authenticated_rpc_call
    )
    monkeypatch.setattr(check_status, "is_websocket_mode", lambda config: False)
    monkeypatch.setattr(
        check_status,
        "_load_or_create_e2ee_client",
        lambda local_did, credential_name: fake_client,
    )
    monkeypatch.setattr(
        check_status, "_save_e2ee_client", lambda client, credential_name: None
    )

    inbox_report = asyncio.run(check_status._build_inbox_report_with_auto_e2ee("alice"))

    assert inbox_report["status"] == "ok"
    assert inbox_report["total"] == 2
    assert inbox_report["by_type"] == {"text": 2}
    assert inbox_report["text_messages"] == 2
    assert inbox_report["messages"][0]["content"] == "Secret hello"
    assert inbox_report["messages"][0]["is_e2ee"] is True
    assert inbox_report["messages"][0]["e2ee_notice"] == (
        "This is an encrypted message."
    )
    assert inbox_report["messages"][1]["content"] == "Hello"

    assert marked_read == ["init-1", "cipher-1"]


def test_auto_e2ee_uses_local_cache_when_websocket_mode_is_active(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """WebSocket receive mode should surface local cache instead of remote inbox."""
    remote_calls: list[str] = []

    monkeypatch.setattr(
        check_status, "create_authenticator", lambda credential_name, config: (
            object(),
            {"did": "did:alice"},
        )
    )
    monkeypatch.setattr(check_status, "is_websocket_mode", lambda config: True)
    monkeypatch.setattr(
        check_status,
        "ensure_listener_runtime",
        lambda credential_name, config=None: {"was_running": True},
    )
    monkeypatch.setattr(
        check_status,
        "create_molt_message_client",
        lambda config: _DummyAsyncClient(),
    )

    async def _fake_authenticated_rpc_call(
        client,
        endpoint: str,
        method: str,
        params: dict[str, Any],
        *,
        auth: Any,
        credential_name: str,
    ) -> dict[str, Any]:
        del client, endpoint, params, auth, credential_name
        remote_calls.append(method)
        assert method == "get_inbox"
        return {
            "messages": [
                {
                    "id": "remote-1",
                    "type": "text",
                    "sender_did": "did:carol",
                    "content": "remote hello",
                    "created_at": "2026-03-11T10:30:00Z",
                }
            ]
        }

    monkeypatch.setattr(
        check_status,
        "authenticated_rpc_call",
        _fake_authenticated_rpc_call,
    )
    monkeypatch.setattr(
        check_status,
        "_build_local_inbox_report",
        lambda owner_did: {
            "status": "ok",
            "source": "local_ws_cache",
            "total": 1,
            "by_type": {"text": 1},
            "text_messages": 1,
            "text_by_sender": {"did:bob": {"count": 1, "latest": "2026-03-11T10:00:00Z"}},
            "messages": [
                {
                    "id": "local-1",
                    "type": "text",
                    "sender_did": "did:bob",
                    "content": "local hello",
                    "created_at": "2026-03-11T10:00:00Z",
                }
            ],
        },
    )

    report = asyncio.run(check_status._build_inbox_report_with_auto_e2ee("alice"))

    assert report["source"] == "local_ws_cache"
    assert report["http_sync"]["status"] == "ok"
    assert remote_calls == ["get_inbox"]
    assert report["total"] == 2
    assert {message["content"] for message in report["messages"]} == {
        "local hello",
        "remote hello",
    }


def test_auto_e2ee_keeps_local_cache_when_websocket_http_sync_fails(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Healthy websocket mode should keep local unread messages even if HTTP sync fails."""

    monkeypatch.setattr(
        check_status, "create_authenticator", lambda credential_name, config: (
            object(),
            {"did": "did:alice"},
        )
    )
    monkeypatch.setattr(check_status, "is_websocket_mode", lambda config: True)
    monkeypatch.setattr(
        check_status,
        "ensure_listener_runtime",
        lambda credential_name, config=None: {"was_running": True},
    )
    monkeypatch.setattr(
        check_status,
        "create_molt_message_client",
        lambda config: _DummyAsyncClient(),
    )

    async def _raise_sync_error(
        client,
        endpoint: str,
        method: str,
        params: dict[str, Any],
        *,
        auth: Any,
        credential_name: str,
    ) -> dict[str, Any]:
        del client, endpoint, method, params, auth, credential_name
        raise RuntimeError("boom")

    monkeypatch.setattr(
        check_status,
        "authenticated_rpc_call",
        _raise_sync_error,
    )
    monkeypatch.setattr(
        check_status,
        "_build_local_inbox_report",
        lambda owner_did: {
            "status": "ok",
            "source": "local_ws_cache",
            "total": 1,
            "by_type": {"text": 1},
            "text_messages": 1,
            "text_by_sender": {"did:bob": {"count": 1, "latest": "2026-03-11T10:00:00Z"}},
            "messages": [
                {
                    "id": "local-1",
                    "type": "text",
                    "sender_did": "did:bob",
                    "content": "local hello",
                    "created_at": "2026-03-11T10:00:00Z",
                }
            ],
        },
    )

    report = asyncio.run(check_status._build_inbox_report_with_auto_e2ee("alice"))

    assert report["source"] == "local_ws_cache"
    assert report["http_sync"]["status"] == "error"
    assert report["messages"][0]["content"] == "local hello"


def test_auto_e2ee_uses_http_fallback_when_websocket_mode_is_degraded(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Degraded WebSocket mode should keep heartbeat service alive over HTTP."""

    monkeypatch.setattr(
        check_status, "create_authenticator", lambda credential_name, config: (
            object(),
            {"did": "did:alice"},
        )
    )
    monkeypatch.setattr(check_status, "is_websocket_mode", lambda config: True)
    monkeypatch.setattr(
        check_status,
        "ensure_listener_runtime",
        lambda credential_name, config=None: {
            "was_running": False,
            "running": False,
            "auto_restart_paused": False,
            "consecutive_restart_failures": 1,
        },
    )
    monkeypatch.setattr(
        check_status,
        "create_molt_message_client",
        lambda config: _DummyAsyncClient(),
    )

    async def _fake_authenticated_rpc_call(
        client,
        endpoint: str,
        method: str,
        params: dict[str, Any],
        *,
        auth: Any,
        credential_name: str,
    ) -> dict[str, Any]:
        del client, endpoint, method, params, auth, credential_name
        return {
            "messages": [
                {
                    "id": "msg-1",
                    "type": "text",
                    "sender_did": "did:bob",
                    "content": "hello",
                    "created_at": "2026-03-11T10:00:00Z",
                }
            ]
        }

    monkeypatch.setattr(
        check_status,
        "authenticated_rpc_call",
        _fake_authenticated_rpc_call,
    )
    monkeypatch.setattr(
        check_status,
        "_load_or_create_e2ee_client",
        lambda local_did, credential_name: object(),
    )
    monkeypatch.setattr(
        check_status,
        "_save_e2ee_client",
        lambda client, credential_name: None,
    )

    report = asyncio.run(check_status._build_inbox_report_with_auto_e2ee("alice"))

    assert report["status"] == "ok"
    assert report["source"] == "remote_http_fallback"
    assert report["messages"][0]["content"] == "hello"


def test_build_local_inbox_report_excludes_rows_marked_read(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Local websocket inbox summaries should only include unread incoming rows."""
    monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))

    conn = check_status.local_store.get_connection()
    try:
        check_status.local_store.ensure_schema(conn)
        thread_id = check_status.local_store.make_thread_id(
            "did:alice",
            peer_did="did:bob",
        )
        check_status.local_store.store_message(
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
        check_status.local_store.store_message(
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

    report = check_status._build_local_inbox_report("did:alice")

    assert report["total"] == 1
    assert [message["id"] for message in report["messages"]] == ["unread-1"]


def test_check_status_uses_auto_e2ee_inbox_report(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Unified status should attach auto-decrypted inbox content."""
    monkeypatch.setattr(
        check_status,
        "ensure_local_upgrade_ready",
        lambda credential_name: {
            "status": "ready",
            "credential_ready": True,
            "database_ready": True,
            "performed": [],
            "credential_layout": {"credential_ready": True, "status": "ready"},
            "local_database": {"status": "ready"},
        },
    )

    async def _fake_check_identity(credential_name: str) -> dict[str, Any]:
        del credential_name
        return {
            "status": "ok",
            "did": "did:alice",
            "name": "Alice",
            "jwt_valid": True,
        }

    async def _fake_auto_inbox(
        credential_name: str,
        *,
        listener_status: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        del listener_status
        assert credential_name == "alice"
        return {
            "status": "ok",
            "total": 1,
            "by_type": {"text": 1},
            "text_messages": 1,
            "text_by_sender": {"did:bob": {"count": 1, "latest": "2026-03-11T09:00:00Z"}},
            "messages": [{"id": "cipher-1", "content": "Secret hello", "is_e2ee": True}],
        }

    monkeypatch.setattr(check_status, "check_identity", _fake_check_identity)
    monkeypatch.setattr(
        check_status,
        "summarize_group_watch",
        lambda owner_did: {"status": "ok", "active_groups": 0, "groups": []},
    )
    monkeypatch.setattr(
        check_status,
        "_build_inbox_report_with_auto_e2ee",
        _fake_auto_inbox,
    )
    monkeypatch.setattr(
        check_status,
        "is_websocket_mode",
        lambda config: True,
    )
    monkeypatch.setattr(
        check_status,
        "ensure_listener_runtime",
        lambda credential_name, config=None: {
            "installed": True,
            "running": False,
            "service_running": False,
            "daemon_available": False,
            "degraded": True,
            "auto_restart_paused": True,
            "consecutive_restart_failures": 3,
            "last_restart_attempt_at": "2026-03-11T09:00:00Z",
            "last_restart_result": "failed",
        },
    )
    monkeypatch.setattr(
        check_status,
        "load_e2ee_client",
        lambda local_did, credential_name: _FakeE2eeClient(),
    )

    report = asyncio.run(check_status.check_status("alice"))

    assert report["inbox"]["messages"][0]["content"] == "Secret hello"
    assert report["inbox"]["messages"][0]["is_e2ee"] is True
    assert report["realtime_listener"]["mode"] == "websocket"
    assert report["realtime_listener"]["degraded"] is True
    assert report["realtime_listener"]["auto_restart_paused"] is True
    assert report["realtime_listener"]["consecutive_restart_failures"] == 3
    assert "e2ee_auto" not in report
