"""Unit tests for DID document update auth helpers."""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import httpx
import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

from utils.auth import update_did_document  # noqa: E402
from utils.identity import DIDIdentity  # noqa: E402
from utils.rpc import JsonRpcError  # noqa: E402


def _make_identity() -> DIDIdentity:
    """Create a minimal DIDIdentity for testing."""
    return DIDIdentity(
        did="did:wba:test.example.com:user:alice",
        did_document={
            "@context": ["https://www.w3.org/ns/did/v1"],
            "id": "did:wba:test.example.com:user:alice",
            "verificationMethod": [],
            "authentication": [],
            "proof": {"challenge": "nonce"},
        },
        private_key_pem=b"test-private-key",
        public_key_pem=b"test-public-key",
    )


def test_update_did_document_uses_body_access_token(monkeypatch) -> None:
    """Body access_token should be returned as-is."""
    monkeypatch.setattr(
        "utils.auth.generate_wba_auth_header", lambda identity, domain: "DIDWba test"
    )

    async def handler(request: httpx.Request) -> httpx.Response:
        assert request.headers["Authorization"] == "DIDWba test"
        return httpx.Response(
            200,
            json={
                "jsonrpc": "2.0",
                "result": {
                    "did": "did:wba:test.example.com:user:alice",
                    "user_id": "user-1",
                    "message": "DID document updated",
                    "access_token": "body-token",
                },
                "id": 1,
            },
        )

    async def _run() -> dict[str, str]:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
            base_url="https://example.com",
        ) as client:
            return await update_did_document(
                client,
                _make_identity(),
                "test.example.com",
                is_public=True,
            )

    result = asyncio.run(_run())
    assert result["access_token"] == "body-token"


def test_update_did_document_uses_authorization_header_fallback(monkeypatch) -> None:
    """Authorization response header should populate access_token when body omits it."""
    monkeypatch.setattr(
        "utils.auth.generate_wba_auth_header", lambda identity, domain: "DIDWba test"
    )

    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={"authorization": "bearer header-token"},
            json={
                "jsonrpc": "2.0",
                "result": {
                    "did": "did:wba:test.example.com:user:alice",
                    "user_id": "user-1",
                    "message": "DID document updated",
                },
                "id": 1,
            },
        )

    async def _run() -> dict[str, str]:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
            base_url="https://example.com",
        ) as client:
            return await update_did_document(
                client, _make_identity(), "test.example.com"
            )

    result = asyncio.run(_run())
    assert result["access_token"] == "header-token"


def test_update_did_document_raises_json_rpc_error(monkeypatch) -> None:
    """JSON-RPC errors should raise JsonRpcError."""
    monkeypatch.setattr(
        "utils.auth.generate_wba_auth_header", lambda identity, domain: "DIDWba test"
    )

    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            json={
                "jsonrpc": "2.0",
                "result": None,
                "error": {
                    "code": -32003,
                    "message": "DID already registered",
                    "data": None,
                },
                "id": 1,
            },
        )

    async def _run() -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler),
            base_url="https://example.com",
        ) as client:
            await update_did_document(client, _make_identity(), "test.example.com")

    with pytest.raises(JsonRpcError, match="DID already registered"):
        asyncio.run(_run())
