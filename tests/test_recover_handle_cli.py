"""Unit tests for recover_handle CLI safety behavior."""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

import recover_handle as recover_cli  # noqa: E402
from utils.identity import DIDIdentity  # noqa: E402


class _AsyncClientContext:
    """Minimal async client context manager for CLI tests."""

    async def __aenter__(self) -> object:
        return object()

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        del exc_type, exc, tb
        return False


def _make_identity(did: str, *, user_id: str = "user-1") -> DIDIdentity:
    """Create a minimal DID identity for CLI tests."""
    return DIDIdentity(
        did=did,
        did_document={"id": did, "proof": {"challenge": "nonce"}},
        private_key_pem=b"private-key",
        public_key_pem=b"public-key",
        user_id=user_id,
        jwt_token="jwt-token",
        e2ee_signing_private_pem=b"e2ee-signing-key",
        e2ee_agreement_private_pem=b"e2ee-agreement-key",
    )


def test_resolve_recovery_target_auto_selects_non_destructive_alias(monkeypatch: pytest.MonkeyPatch) -> None:
    """Automatic recovery aliases should skip occupied credential names."""
    existing_credentials = {
        "alice": {"did": "did:wba:awiki.ai:alice:k1_old"},
        "alice_recovered": {"did": "did:wba:awiki.ai:alice:k1_other"},
    }
    monkeypatch.setattr(
        recover_cli,
        "load_identity",
        lambda name: existing_credentials.get(name),
    )

    credential_name, existing_credential = recover_cli._resolve_recovery_target(
        handle="alice",
        requested_credential_name=None,
        replace_existing=False,
    )

    assert credential_name == "alice_recovered_2"
    assert existing_credential is None


def test_resolve_recovery_target_rejects_implicit_overwrite(monkeypatch: pytest.MonkeyPatch) -> None:
    """Explicit credential targets should not overwrite existing data by default."""
    monkeypatch.setattr(
        recover_cli,
        "load_identity",
        lambda name: {"did": "did:wba:awiki.ai:user:k1_existing"} if name == "default" else None,
    )

    with pytest.raises(ValueError, match="already exists for DID"):
        recover_cli._resolve_recovery_target(
            handle="alice",
            requested_credential_name="default",
            replace_existing=False,
        )


def test_do_recover_preserves_existing_default_when_no_credential_is_requested(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Recovery without --credential should save to a new alias and keep default intact."""
    saved_payload: dict[str, object] = {}
    existing_credentials = {
        "default": {
            "did": "did:wba:awiki.ai:user:k1_default",
            "unique_id": "k1_default",
            "name": "Default User",
        }
    }

    monkeypatch.setattr(
        recover_cli,
        "load_identity",
        lambda name: existing_credentials.get(name),
    )
    monkeypatch.setattr(recover_cli, "create_user_service_client", lambda config: _AsyncClientContext())

    async def fake_recover_handle(client, config, *, phone, otp_code, handle):
        del client, config, phone, otp_code, handle
        return _make_identity("did:wba:awiki.ai:alice:k1_new"), {
            "handle": "alice",
            "full_handle": "alice.awiki.ai",
            "message": "recovered",
        }

    monkeypatch.setattr(recover_cli, "recover_handle", fake_recover_handle)
    monkeypatch.setattr(
        recover_cli,
        "save_identity",
        lambda **kwargs: saved_payload.update(kwargs),
    )
    monkeypatch.setattr(
        recover_cli,
        "backup_identity",
        lambda name: pytest.fail(f"backup_identity should not be called: {name}"),
    )
    monkeypatch.setattr(
        recover_cli,
        "_migrate_local_cache",
        lambda **kwargs: pytest.fail(f"_migrate_local_cache should not be called: {kwargs}"),
    )
    monkeypatch.setattr(
        recover_cli,
        "prune_unreferenced_credential_dir",
        lambda dir_name: pytest.fail(
            f"prune_unreferenced_credential_dir should not be called: {dir_name}"
        ),
    )

    asyncio.run(
        recover_cli.do_recover(
            handle="alice",
            phone="+8613800138000",
            otp_code="123456",
            requested_credential_name=None,
            replace_existing=False,
        )
    )

    assert saved_payload["name"] == "alice"
    assert saved_payload["replace_existing"] is False
    assert saved_payload["did"] == "did:wba:awiki.ai:alice:k1_new"


def test_do_recover_replaces_existing_credential_only_when_requested(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Intentional replacement should back up and migrate the selected credential."""
    events: dict[str, object] = {}
    existing_credential = {
        "did": "did:wba:awiki.ai:alice:k1_old",
        "unique_id": "k1_old",
        "name": "Recovered User",
    }

    monkeypatch.setattr(
        recover_cli,
        "load_identity",
        lambda name: existing_credential if name == "default" else None,
    )
    monkeypatch.setattr(recover_cli, "create_user_service_client", lambda config: _AsyncClientContext())

    async def fake_recover_handle(client, config, *, phone, otp_code, handle):
        del client, config, phone, otp_code, handle
        return _make_identity("did:wba:awiki.ai:alice:k1_new"), {
            "handle": "alice",
            "full_handle": "alice.awiki.ai",
            "message": "recovered",
        }

    monkeypatch.setattr(recover_cli, "recover_handle", fake_recover_handle)
    monkeypatch.setattr(
        recover_cli,
        "backup_identity",
        lambda name: Path(f"/tmp/{name}-backup"),
    )
    monkeypatch.setattr(
        recover_cli,
        "save_identity",
        lambda **kwargs: events.setdefault("save_identity", kwargs),
    )
    monkeypatch.setattr(
        recover_cli,
        "_migrate_local_cache",
        lambda **kwargs: events.setdefault("cache_migration", kwargs) or {
            "messages_rebound": 3,
            "contacts_rebound": 1,
            "e2ee_outbox_cleared": 0,
            "e2ee_state_deleted": True,
        },
    )
    monkeypatch.setattr(
        recover_cli,
        "prune_unreferenced_credential_dir",
        lambda dir_name: events.setdefault("pruned_unique_id", dir_name) or True,
    )

    asyncio.run(
        recover_cli.do_recover(
            handle="alice",
            phone="+8613800138000",
            otp_code="123456",
            requested_credential_name="default",
            replace_existing=True,
        )
    )

    save_call = events["save_identity"]
    assert isinstance(save_call, dict)
    assert save_call["name"] == "default"
    assert save_call["replace_existing"] is True
    assert save_call["did"] == "did:wba:awiki.ai:alice:k1_new"

    migration_call = events["cache_migration"]
    assert isinstance(migration_call, dict)
    assert migration_call["credential_name"] == "default"
    assert migration_call["old_did"] == "did:wba:awiki.ai:alice:k1_old"
    assert migration_call["new_did"] == "did:wba:awiki.ai:alice:k1_new"
    assert events["pruned_unique_id"] == "k1_old"
