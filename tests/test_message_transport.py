"""Unit tests for message transport helpers and WebSocket demultiplexing.

[INPUT]: message_transport module, message_daemon, WsClient, fake websocket connection
[OUTPUT]: Regression coverage for receive-mode persistence, localhost daemon
          proxying, automatic HTTP fallback on WebSocket transport failures,
          and single-reader response/notification demultiplexing
[POS]: Transport selection and WebSocket client safety tests

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import asyncio
import json
import sys
from contextlib import suppress
from pathlib import Path
from types import SimpleNamespace

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

import message_daemon  # noqa: E402
import message_transport  # noqa: E402
from utils.config import SDKConfig  # noqa: E402
from utils.ws import WsClient  # noqa: E402


class FakeConnection:
    """Minimal websocket-like connection for WsClient unit tests."""

    def __init__(self) -> None:
        self.sent_payloads: list[str] = []
        self.recv_queue: asyncio.Queue[str] = asyncio.Queue()
        self.closed = False

    async def send(self, payload: str) -> None:
        self.sent_payloads.append(payload)

    async def recv(self) -> str:
        return await self.recv_queue.get()

    def ping(self):
        loop = asyncio.get_running_loop()
        waiter = loop.create_future()
        waiter.set_result(None)
        return waiter

    async def close(self) -> None:
        self.closed = True


class _DummyAsyncClient:
    """Minimal async context manager used by mocked HTTP fallback tests."""

    async def __aenter__(self) -> "_DummyAsyncClient":
        return self

    async def __aexit__(self, exc_type, exc, tb) -> None:
        del exc_type, exc, tb


def _build_config(tmp_path: Path) -> SDKConfig:
    """Build a config object rooted under a temporary data dir."""
    return SDKConfig(
        user_service_url="https://example.com",
        molt_message_url="https://example.com",
        did_domain="example.com",
        credentials_dir=tmp_path / "credentials",
        data_dir=tmp_path / "data",
    )


def test_write_and_load_receive_mode(tmp_path: Path) -> None:
    """Transport mode should round-trip through settings.json."""
    config = _build_config(tmp_path)

    settings_path = message_transport.write_receive_mode(
        message_transport.RECEIVE_MODE_WEBSOCKET,
        config=config,
    )

    assert settings_path.exists()
    assert (
        message_transport.load_receive_mode(config)
        == message_transport.RECEIVE_MODE_WEBSOCKET
    )


def test_ws_client_demultiplexes_response_and_notification() -> None:
    """A notification interleaved with a response should not be lost."""

    async def _run() -> None:
        config = SDKConfig(
            user_service_url="https://example.com",
            molt_message_url="https://example.com",
            did_domain="example.com",
        )
        identity = SimpleNamespace(jwt_token="token")
        ws = WsClient(config, identity)
        fake_conn = FakeConnection()
        ws._conn = fake_conn
        ws._reader_task = asyncio.create_task(ws._reader_loop())

        rpc_task = asyncio.create_task(ws.send_rpc("send", {"content": "hello"}))
        await asyncio.sleep(0)

        await fake_conn.recv_queue.put(
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "method": "new_message",
                    "params": {"id": "msg-1", "content": "incoming"},
                }
            )
        )
        await fake_conn.recv_queue.put(
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "id": 1,
                    "result": {"id": "out-1", "server_seq": 7},
                }
            )
        )

        result = await rpc_task
        notification = await ws.receive_notification(timeout=0.1)

        assert result == {"id": "out-1", "server_seq": 7}
        assert notification is not None
        assert notification["method"] == "new_message"
        assert json.loads(fake_conn.sent_payloads[0])["method"] == "send"

        if ws._reader_task is not None:
            ws._reader_task.cancel()
            with suppress(asyncio.CancelledError):
                await ws._reader_task

    asyncio.run(_run())


def test_websocket_transport_uses_local_daemon(tmp_path: Path) -> None:
    """WebSocket mode message RPC should go through the localhost daemon."""

    async def _run() -> None:
        config = _build_config(tmp_path)
        token = "daemon-token"
        message_transport.write_receive_mode(
            message_transport.RECEIVE_MODE_WEBSOCKET,
            config=config,
            extra_transport_fields={
                "local_daemon_host": "127.0.0.1",
                "local_daemon_port": 18881,
                "local_daemon_token": token,
            },
        )

        captured: dict[str, object] = {}

        async def _handler(
            method: str,
            params: dict[str, object],
            credential_name: str,
        ) -> dict[str, object]:
            captured["method"] = method
            captured["params"] = params
            captured["credential_name"] = credential_name
            return {"id": "msg-1", "server_seq": 9}

        daemon = message_daemon.LocalMessageDaemon(
            message_daemon.LocalDaemonSettings(
                host="127.0.0.1",
                port=18881,
                token=token,
            ),
            _handler,
        )
        await daemon.start()
        try:
            result = await message_transport.websocket_message_rpc_call(
                "send",
                {"content": "hello"},
                credential_name="sender",
                config=config,
            )
        finally:
            await daemon.close()

        assert result == {"id": "msg-1", "server_seq": 9}
        assert captured["method"] == "send"
        assert captured["params"] == {"content": "hello"}
        assert captured["credential_name"] == "sender"

    asyncio.run(_run())


def test_local_daemon_timeout_is_wrapped_as_runtime_error(tmp_path: Path) -> None:
    """Local daemon client should raise RuntimeError instead of raw TimeoutError."""

    async def _run() -> None:
        config = _build_config(tmp_path)
        token = "daemon-token"
        message_transport.write_receive_mode(
            message_transport.RECEIVE_MODE_WEBSOCKET,
            config=config,
            extra_transport_fields={
                "local_daemon_host": "127.0.0.1",
                "local_daemon_port": 18882,
                "local_daemon_token": token,
            },
        )

        async def _slow_handler(
            method: str,
            params: dict[str, object],
            credential_name: str,
        ) -> dict[str, object]:
            del method, params, credential_name
            await asyncio.sleep(0.2)
            return {"ok": True}

        daemon = message_daemon.LocalMessageDaemon(
            message_daemon.LocalDaemonSettings(
                host="127.0.0.1",
                port=18882,
                token=token,
            ),
            _slow_handler,
        )
        await daemon.start()
        try:
            with pytest.raises(RuntimeError, match="timed out"):
                await message_daemon.call_local_daemon(
                    "send",
                    {"content": "hello"},
                    credential_name="default",
                    config=config,
                    timeout=0.05,
                )
        finally:
            await daemon.close()

    asyncio.run(_run())


def test_message_rpc_call_falls_back_to_http_on_websocket_transport_error(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Transport-layer WebSocket errors should transparently retry over HTTP."""

    async def _run() -> None:
        config = _build_config(tmp_path)
        http_calls: list[tuple[str, dict[str, object]]] = []
        recovery_calls: list[str] = []
        healthy_calls: list[str] = []

        message_transport.write_receive_mode(
            message_transport.RECEIVE_MODE_WEBSOCKET,
            config=config,
        )
        monkeypatch.setattr(
            message_transport,
            "websocket_message_rpc_call",
            lambda method, params, *, credential_name, config: (_raise_transport_error()),
        )
        monkeypatch.setattr(
            message_transport,
            "create_authenticator",
            lambda credential_name, config: (object(), {"did": "did:alice"}),
        )
        monkeypatch.setattr(
            message_transport,
            "create_molt_message_client",
            lambda config: _DummyAsyncClient(),
        )

        async def _fake_authenticated_rpc_call(
            client,
            endpoint: str,
            method: str,
            params: dict[str, object] | None = None,
            *,
            auth: object,
            credential_name: str,
        ) -> dict[str, object]:
            del client, endpoint, auth, credential_name
            http_calls.append((method, params or {}))
            return {"id": "http-msg-1", "server_seq": 10}

        monkeypatch.setattr(
            message_transport,
            "authenticated_rpc_call",
            _fake_authenticated_rpc_call,
        )
        monkeypatch.setattr(
            message_transport,
            "ensure_listener_runtime",
            lambda credential_name, *, config=None: recovery_calls.append(
                credential_name
            ) or {"running": False},
        )
        monkeypatch.setattr(
            message_transport,
            "note_listener_healthy",
            lambda credential_name, *, config=None: healthy_calls.append(credential_name),
        )

        result = await message_transport.message_rpc_call(
            "send",
            {"content": "hello"},
            credential_name="alice",
            config=config,
        )

        assert result == {"id": "http-msg-1", "server_seq": 10}
        assert http_calls == [("send", {"content": "hello"})]
        assert recovery_calls == ["alice"]
        assert healthy_calls == []

    async def _raise_transport_error() -> dict[str, object]:
        raise RuntimeError("Local message daemon is unavailable; make sure `ws_listener` is running in websocket mode")

    asyncio.run(_run())


def test_message_rpc_call_does_not_fallback_on_json_rpc_business_error(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Business-layer JSON-RPC errors should propagate without HTTP retry."""

    async def _run() -> None:
        config = _build_config(tmp_path)
        http_called = False

        message_transport.write_receive_mode(
            message_transport.RECEIVE_MODE_WEBSOCKET,
            config=config,
        )

        async def _raise_business_error(
            method: str,
            params: dict[str, object] | None = None,
            *,
            credential_name: str,
            config: SDKConfig | None = None,
        ) -> dict[str, object]:
            del method, params, credential_name, config
            raise RuntimeError("JSON-RPC error -32602: Invalid params")

        monkeypatch.setattr(
            message_transport,
            "websocket_message_rpc_call",
            _raise_business_error,
        )
        monkeypatch.setattr(
            message_transport,
            "http_message_rpc_call",
            lambda method, params, *, credential_name, config: _mark_http_called(),
        )
        monkeypatch.setattr(
            message_transport,
            "ensure_listener_runtime",
            lambda credential_name, *, config=None: {"running": False},
        )

        async def _mark_http_called() -> dict[str, object]:
            nonlocal http_called
            http_called = True
            return {"id": "unexpected"}

        with pytest.raises(RuntimeError, match="JSON-RPC error -32602"):
            await message_transport.message_rpc_call(
                "send",
                {"content": "hello"},
                credential_name="alice",
                config=config,
            )

        assert http_called is False

    asyncio.run(_run())
