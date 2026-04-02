"""Unit tests for the SQLite-backed E2EE session store."""

from __future__ import annotations

import base64
import sys
import time
from pathlib import Path

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

import e2ee_session_store  # noqa: E402
import local_store  # noqa: E402
from utils import E2eeClient  # noqa: E402


def _generate_private_pems() -> tuple[str, str]:
    """Generate real E2EE key PEM strings for test clients."""
    signing_key = ec.generate_private_key(ec.SECP256R1())
    x25519_key = X25519PrivateKey.generate()
    signing_pem = signing_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("utf-8")
    x25519_pem = x25519_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("utf-8")
    return signing_pem, x25519_pem


def _build_state(
    *,
    local_did: str,
    peer_did: str,
    session_id: str,
    signing_pem: str,
    x25519_pem: str,
    confirmed: bool = False,
) -> dict:
    """Build one valid ``E2eeClient.from_state`` payload."""
    chain_key = base64.b64encode(b"a" * 32).decode("ascii")
    expires_at = time.time() + 3600
    return {
        "version": "hpke_v1",
        "local_did": local_did,
        "signing_pem": signing_pem,
        "x25519_pem": x25519_pem,
        "confirmed_session_ids": [session_id] if confirmed else [],
        "sessions": [
            {
                "session_id": session_id,
                "local_did": local_did,
                "peer_did": peer_did,
                "is_initiator": True,
                "send_chain_key": chain_key,
                "recv_chain_key": chain_key,
                "send_seq": 3,
                "recv_seq": 4,
                "expires_at": expires_at,
                "created_at": "2026-03-23T10:00:00+00:00",
                "active_at": "2026-03-23T10:00:01+00:00",
            }
        ],
    }


def test_save_and_load_round_trip_uses_sqlite(tmp_path, monkeypatch) -> None:
    """Persisted E2EE sessions should round-trip through awiki.db."""
    monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
    signing_pem, x25519_pem = _generate_private_pems()
    monkeypatch.setattr(
        e2ee_session_store,
        "load_identity",
        lambda credential_name: {
            "did": "did:alice",
            "e2ee_signing_private_pem": signing_pem,
            "e2ee_agreement_private_pem": x25519_pem,
        },
    )

    client = E2eeClient.from_state(
        _build_state(
            local_did="did:alice",
            peer_did="did:bob",
            session_id="sess-1",
            signing_pem=signing_pem,
            x25519_pem=x25519_pem,
            confirmed=True,
        )
    )
    e2ee_session_store.save_e2ee_client(client, "alice")

    conn = local_store.get_connection()
    local_store.ensure_schema(conn)
    row = conn.execute(
        "SELECT session_id, peer_confirmed FROM e2ee_sessions WHERE owner_did = ?",
        ("did:alice",),
    ).fetchone()
    conn.close()

    loaded = e2ee_session_store.load_e2ee_client("did:alice", "alice")
    assert row["session_id"] == "sess-1"
    assert row["peer_confirmed"] == 1
    assert loaded.has_active_session("did:bob") is True
    assert loaded.has_session_id("sess-1") is True
    assert loaded.is_session_confirmed("sess-1") is True


def test_save_replaces_old_session_for_same_peer(tmp_path, monkeypatch) -> None:
    """Saving a newer session for one peer should replace the old session row."""
    monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
    signing_pem, x25519_pem = _generate_private_pems()
    monkeypatch.setattr(
        e2ee_session_store,
        "load_identity",
        lambda credential_name: {
            "did": "did:alice",
            "e2ee_signing_private_pem": signing_pem,
            "e2ee_agreement_private_pem": x25519_pem,
        },
    )

    old_client = E2eeClient.from_state(
        _build_state(
            local_did="did:alice",
            peer_did="did:bob",
            session_id="sess-old",
            signing_pem=signing_pem,
            x25519_pem=x25519_pem,
        )
    )
    new_client = E2eeClient.from_state(
        _build_state(
            local_did="did:alice",
            peer_did="did:bob",
            session_id="sess-new",
            signing_pem=signing_pem,
            x25519_pem=x25519_pem,
            confirmed=True,
        )
    )

    e2ee_session_store.save_e2ee_client(old_client, "alice")
    e2ee_session_store.save_e2ee_client(new_client, "alice")

    conn = local_store.get_connection()
    local_store.ensure_schema(conn)
    rows = conn.execute(
        "SELECT session_id FROM e2ee_sessions WHERE owner_did = ?",
        ("did:alice",),
    ).fetchall()
    conn.close()

    assert [row["session_id"] for row in rows] == ["sess-new"]


def test_load_migrates_legacy_json_state_into_sqlite(tmp_path, monkeypatch) -> None:
    """Legacy JSON state should be imported into SQLite on first load."""
    monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
    signing_pem, x25519_pem = _generate_private_pems()
    legacy_state = _build_state(
        local_did="did:alice",
        peer_did="did:bob",
        session_id="sess-legacy",
        signing_pem=signing_pem,
        x25519_pem=x25519_pem,
        confirmed=True,
    )
    delete_calls: list[str] = []
    monkeypatch.setattr(
        e2ee_session_store,
        "load_identity",
        lambda credential_name: {
            "did": "did:alice",
            "e2ee_signing_private_pem": signing_pem,
            "e2ee_agreement_private_pem": x25519_pem,
        },
    )
    monkeypatch.setattr(
        e2ee_session_store,
        "load_e2ee_state",
        lambda credential_name: legacy_state,
    )
    monkeypatch.setattr(
        e2ee_session_store,
        "delete_e2ee_state",
        lambda credential_name: delete_calls.append(credential_name),
    )

    loaded = e2ee_session_store.load_e2ee_client("did:alice", "alice")

    conn = local_store.get_connection()
    local_store.ensure_schema(conn)
    row = conn.execute(
        "SELECT session_id FROM e2ee_sessions WHERE owner_did = ?",
        ("did:alice",),
    ).fetchone()
    conn.close()

    assert row["session_id"] == "sess-legacy"
    assert loaded.has_session_id("sess-legacy") is True
    assert delete_calls == ["alice"]
