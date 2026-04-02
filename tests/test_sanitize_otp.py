"""Unit tests for OTP code sanitization in handle utilities."""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

from utils import handle as handle_utils  # noqa: E402
from utils.config import SDKConfig  # noqa: E402
from utils.identity import DIDIdentity  # noqa: E402


# ---------------------------------------------------------------------------
# _sanitize_otp unit tests
# ---------------------------------------------------------------------------

@pytest.mark.parametrize(
    "raw, expected",
    [
        ("123456", "123456"),          # already clean
        ("123 456", "123456"),         # single space
        ("12 34 56", "123456"),        # multiple spaces
        (" 123456 ", "123456"),        # leading/trailing spaces
        ("123\n456", "123456"),        # newline
        ("123\t456", "123456"),        # tab
        ("123\r\n456", "123456"),      # CRLF
        (" 1 2 3\n4 5 6 ", "123456"), # mixed whitespace everywhere
    ],
)
def test_sanitize_otp(raw: str, expected: str) -> None:
    assert handle_utils._sanitize_otp(raw) == expected


# ---------------------------------------------------------------------------
# Integration: verify sanitized OTP reaches the RPC payload
# ---------------------------------------------------------------------------

def _make_identity(did: str) -> DIDIdentity:
    return DIDIdentity(
        did=did,
        did_document={"id": did, "proof": {"challenge": "nonce"}},
        private_key_pem=b"private-key",
        public_key_pem=b"public-key",
    )


def _patch_handle_deps(monkeypatch, recorded: dict):
    """Patch create_identity and rpc_call so register/recover run offline."""

    async def fake_rpc_call(client, endpoint, method, payload):
        recorded["method"] = method
        recorded["payload"] = dict(payload)
        return {
            "did": "did:wba:awiki.ai:alice:k1_new",
            "user_id": "user-1",
            "handle": "alice",
            "full_handle": "alice.awiki.ai",
            "access_token": "jwt-token",
            "message": "ok",
        }

    monkeypatch.setattr(
        handle_utils,
        "create_identity",
        lambda **kwargs: _make_identity("did:wba:awiki.ai:alice:k1_new"),
    )
    monkeypatch.setattr(handle_utils, "rpc_call", fake_rpc_call)


def test_register_handle_sanitizes_otp(monkeypatch) -> None:
    """register_handle() should strip whitespace from OTP before API call."""
    recorded: dict = {}
    _patch_handle_deps(monkeypatch, recorded)

    async def _run():
        return await handle_utils.register_handle(
            client=object(),
            config=SDKConfig(did_domain="awiki.ai"),
            phone="+8613800138000",
            otp_code="123 456",
            handle="alice",
        )

    asyncio.run(_run())
    assert recorded["payload"]["otp_code"] == "123456"


def test_recover_handle_sanitizes_otp(monkeypatch) -> None:
    """recover_handle() should strip whitespace from OTP before API call."""
    recorded: dict = {}
    _patch_handle_deps(monkeypatch, recorded)

    async def _run():
        return await handle_utils.recover_handle(
            client=object(),
            config=SDKConfig(did_domain="awiki.ai"),
            phone="+8613800138000",
            otp_code="12\n34\t56",
            handle="alice",
        )

    asyncio.run(_run())
    assert recorded["payload"]["otp_code"] == "123456"
