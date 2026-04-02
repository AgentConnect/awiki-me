"""Unit tests for Handle recovery client helpers."""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

from utils.config import SDKConfig  # noqa: E402
from utils.identity import DIDIdentity  # noqa: E402
from utils import handle as handle_utils  # noqa: E402


def _make_identity(did: str) -> DIDIdentity:
    """Create a minimal DID identity for recovery tests."""
    return DIDIdentity(
        did=did,
        did_document={"id": did, "proof": {"challenge": "nonce"}},
        private_key_pem=b"private-key",
        public_key_pem=b"public-key",
    )


def test_recover_handle_uses_new_rpc_and_access_token(monkeypatch) -> None:
    """recover_handle should call the new RPC and preserve access_token."""
    recorded: dict[str, object] = {}

    async def fake_rpc_call(client, endpoint, method, payload):
        recorded["endpoint"] = endpoint
        recorded["method"] = method
        recorded["payload"] = payload
        return {
            "did": "did:wba:awiki.ai:alice:k1_new",
            "user_id": "user-1",
            "handle": "alice",
            "full_handle": "alice.awiki.ai",
            "access_token": "jwt-token",
            "message": "recovered",
        }

    monkeypatch.setattr(
        handle_utils,
        "create_identity",
        lambda **kwargs: _make_identity("did:wba:awiki.ai:alice:k1_new"),
    )
    monkeypatch.setattr(handle_utils, "rpc_call", fake_rpc_call)

    async def _run():
        identity, result = await handle_utils.recover_handle(
            client=object(),
            config=SDKConfig(did_domain="awiki.ai"),
            phone="+8613800138000",
            otp_code="123456",
            handle="alice",
        )
        return identity, result

    identity, result = asyncio.run(_run())

    assert recorded["endpoint"] == "/user-service/did-auth/rpc"
    assert recorded["method"] == "recover_handle"
    assert recorded["payload"]["handle"] == "alice"
    assert recorded["payload"]["otp_code"] == "123456"
    assert identity.did == "did:wba:awiki.ai:alice:k1_new"
    assert identity.jwt_token == "jwt-token"
    assert result["full_handle"] == "alice.awiki.ai"
