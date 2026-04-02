"""Unit tests for the indexed credential storage layout."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

import credential_layout  # noqa: E402
import credential_migration  # noqa: E402
import credential_store  # noqa: E402
import e2ee_store  # noqa: E402


@pytest.fixture()
def isolated_home(tmp_path, monkeypatch) -> Path:
    """Isolate the credential directory under a temporary HOME."""
    monkeypatch.setenv("HOME", str(tmp_path))
    return tmp_path


def _credentials_root(home: Path) -> Path:
    """Return the expected credentials root for the temporary HOME."""
    return home / ".openclaw" / "credentials" / "awiki-agent-id-message"


def _save_sample_identity(
    *,
    handle: str | None = None,
    name: str = "default",
    did: str = "did:wba:awiki.ai:user:k1_test",
    unique_id: str = "k1_test",
) -> Path:
    """Save a minimal credential_store identity for testing."""
    return credential_store.save_identity(
        did=did,
        unique_id=unique_id,
        user_id="user-1",
        private_key_pem=b"private-key",
        public_key_pem=b"public-key",
        jwt_token="jwt-token",
        display_name="Test User",
        handle=handle,
        name=name,
        did_document={"id": did},
        e2ee_signing_private_pem=b"e2ee-sign",
        e2ee_agreement_private_pem=b"e2ee-agree",
    )


def _write_legacy_credential(
    root: Path,
    *,
    credential_name: str,
    handle: str | None = None,
    did: str | None = None,
) -> None:
    """Write a legacy flat credential and E2EE state file."""
    resolved_did = did or (
        f"did:wba:awiki.ai:{handle}:k1_legacy"
        if handle
        else "did:wba:awiki.ai:user:k1_legacy"
    )
    legacy_credential = {
        "did": resolved_did,
        "unique_id": "k1_legacy",
        "user_id": "legacy-user",
        "private_key_pem": "legacy-private",
        "public_key_pem": "legacy-public",
        "jwt_token": "legacy-jwt",
        "name": "Legacy User",
        "handle": handle,
        "did_document": {"id": resolved_did},
        "created_at": "2026-01-01T00:00:00+00:00",
        "e2ee_signing_private_pem": "legacy-e2ee-sign",
        "e2ee_agreement_private_pem": "legacy-e2ee-agree",
    }
    root.mkdir(parents=True, exist_ok=True)
    (root / f"{credential_name}.json").write_text(
        json.dumps(legacy_credential, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (root / f"e2ee_{credential_name}.json").write_text(
        json.dumps({"local_did": resolved_did, "sessions": []}, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (root / f"{credential_name}_did_document.json").write_text("{}", encoding="utf-8")
    (root / f"{credential_name}_private_key.pem").write_text("legacy-private", encoding="utf-8")


def test_save_identity_with_handle_uses_unique_id_directory_and_indexes_handle(isolated_home) -> None:
    """Handle-registered credentials should still use unique_id as directory name."""
    path = _save_sample_identity(handle="alice", unique_id="k1_test")
    root = _credentials_root(isolated_home)
    index = json.loads((root / "index.json").read_text(encoding="utf-8"))
    loaded_data = credential_store.load_identity("default")

    assert path == root / "k1_test" / "identity.json"
    assert index["default_credential_name"] == "default"
    assert index["credentials"]["default"]["dir_name"] == "k1_test"
    assert index["credentials"]["default"]["handle"] == "alice"
    assert index["credentials"]["default"]["is_default"] is True
    assert loaded_data is not None
    assert loaded_data["handle"] == "alice"
    assert loaded_data["private_key_pem"] == "private-key"
    assert (root / "k1_test" / "key-1-private.pem").exists()
    assert (root / "k1_test" / "did_document.json").exists()


def test_save_identity_without_handle_uses_unique_id_directory(isolated_home) -> None:
    """DID-only credentials should use unique_id as the directory name."""
    path = _save_sample_identity(handle=None, unique_id="k1_unique")
    root = _credentials_root(isolated_home)
    loaded_data = credential_store.load_identity("default")

    assert path == root / "k1_unique" / "identity.json"
    assert loaded_data is not None
    assert "handle" not in loaded_data


def test_default_alias_falls_back_to_configured_default_credential_name(isolated_home) -> None:
    """The default alias should resolve to the configured index default entry."""
    did = "did:wba:awiki.ai:cgw:k1_cgw"
    _save_sample_identity(
        handle="cgw",
        name="cgw",
        did=did,
        unique_id="k1_cgw",
    )

    index = credential_layout.load_index()
    index["default_credential_name"] = "cgw"
    credential_layout.save_index(index)

    entry = credential_layout.get_index_entry("default")
    loaded_data = credential_store.load_identity("default")

    assert entry is not None
    assert entry["credential_name"] == "cgw"
    assert entry["is_default"] is True
    assert loaded_data is not None
    assert loaded_data["did"] == did
    assert loaded_data["handle"] == "cgw"


def test_save_identity_rejects_overwrite_for_different_did(isolated_home) -> None:
    """A credential name should not silently overwrite another DID."""
    _save_sample_identity(name="default", did="did:wba:awiki.ai:user:k1_first", unique_id="k1_first")

    with pytest.raises(ValueError, match="already exists for DID"):
        _save_sample_identity(
            name="default",
            did="did:wba:awiki.ai:user:k1_second",
            unique_id="k1_second",
        )


def test_save_identity_allows_replace_existing_when_requested(isolated_home) -> None:
    """Recovery flows should be able to replace the DID for one credential name."""
    _save_sample_identity(
        name="default",
        did="did:wba:awiki.ai:user:k1_first",
        unique_id="k1_first",
    )

    path = credential_store.save_identity(
        did="did:wba:awiki.ai:alice:k1_second",
        unique_id="k1_second",
        user_id="user-2",
        private_key_pem=b"private-key-2",
        public_key_pem=b"public-key-2",
        jwt_token="jwt-token-2",
        display_name="Recovered User",
        handle="alice",
        name="default",
        did_document={"id": "did:wba:awiki.ai:alice:k1_second"},
        replace_existing=True,
    )

    loaded_data = credential_store.load_identity("default")
    assert path == _credentials_root(isolated_home) / "k1_second" / "identity.json"
    assert loaded_data is not None
    assert loaded_data["did"] == "did:wba:awiki.ai:alice:k1_second"


def test_backup_identity_copies_current_credential_directory(isolated_home) -> None:
    """Existing credential directories should be backup-able before recovery."""
    _save_sample_identity(handle="alice", name="default")

    backup_dir = credential_store.backup_identity("default")

    assert backup_dir is not None
    assert (backup_dir / "k1_test" / "identity.json").exists()
    assert (backup_dir / "index_entry.json").exists()


def test_e2ee_state_is_stored_inside_credential_directory(isolated_home) -> None:
    """E2EE state should be saved in the credential's own directory."""
    _save_sample_identity(handle="alice", unique_id="k1_test")

    state_path = e2ee_store.save_e2ee_state({"local_did": "did:wba:awiki.ai:alice:k1_test"}, "default")
    loaded_state = e2ee_store.load_e2ee_state("default")

    assert state_path == _credentials_root(isolated_home) / "k1_test" / "e2ee-state.json"
    assert loaded_state == {"local_did": "did:wba:awiki.ai:alice:k1_test"}


def test_migrate_legacy_credentials_creates_new_layout_and_backup(isolated_home) -> None:
    """Legacy flat credential files should migrate into the new directory layout."""
    root = _credentials_root(isolated_home)
    _write_legacy_credential(root, credential_name="default", handle="alice")

    result = credential_migration.migrate_legacy_credentials()
    loaded_data = credential_store.load_identity("default")
    migrated_state = e2ee_store.load_e2ee_state("default")
    backup_root = root / ".legacy-backup"

    assert result["status"] == "migrated"
    assert result["migrated"][0]["credential_name"] == "default"
    assert result["migrated"][0]["dir_name"] == "k1_legacy"
    assert loaded_data is not None
    assert loaded_data["did"] == "did:wba:awiki.ai:alice:k1_legacy"
    assert migrated_state == {
        "local_did": "did:wba:awiki.ai:alice:k1_legacy",
        "sessions": [],
    }
    assert not (root / "default.json").exists()
    assert not (root / "e2ee_default.json").exists()
    assert any(backup_root.rglob("default.json"))
    assert any(backup_root.rglob("e2ee_default.json"))


def test_detect_legacy_layout_reports_legacy_files(isolated_home) -> None:
    """Legacy detection should identify flat credential files."""
    root = _credentials_root(isolated_home)
    _write_legacy_credential(root, credential_name="default", handle=None)

    detection = credential_migration.detect_legacy_layout()

    assert detection["status"] == "legacy"
    assert detection["legacy_credentials"] == ["default"]
    assert detection["unique_did_count"] == 1


def test_detect_legacy_layout_uses_payload_validation(isolated_home) -> None:
    """Only valid legacy credential payloads should count as migratable credentials."""
    root = _credentials_root(isolated_home)
    _write_legacy_credential(root, credential_name="default", handle=None)
    (root / "notes.json").write_text(
        json.dumps({"hello": "world"}, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (root / "e2ee_orphan.json").write_text(
        json.dumps({"local_did": "did:wba:awiki.ai:user:k1_orphan", "sessions": []}),
        encoding="utf-8",
    )

    detection = credential_migration.detect_legacy_layout()

    assert detection["status"] == "legacy"
    assert detection["legacy_credentials"] == ["default"]
    assert detection["unique_did_count"] == 1
    assert detection["invalid_json_files"] == [
        {
            "file": "notes.json",
            "reason": "not_a_legacy_credential_payload",
        }
    ]
    assert detection["orphan_e2ee_files"] == [
        {
            "credential_name": "orphan",
            "file": "e2ee_orphan.json",
        }
    ]


def test_detect_legacy_layout_reports_unique_dids_not_credential_count(isolated_home) -> None:
    """Multiple legacy credential names may still map to one unique DID."""
    root = _credentials_root(isolated_home)
    shared_did = "did:wba:awiki.ai:user:k1_same"
    _write_legacy_credential(root, credential_name="default", did=shared_did)
    _write_legacy_credential(root, credential_name="backup", did=shared_did)

    detection = credential_migration.detect_legacy_layout()

    assert detection["legacy_credentials"] == ["backup", "default"]
    assert detection["unique_dids"] == [shared_did]
    assert detection["unique_did_count"] == 1


def test_migrate_legacy_credentials_does_not_treat_orphan_files_as_users(isolated_home) -> None:
    """Orphan E2EE files and unrelated JSON should not be migrated as credentials."""
    root = _credentials_root(isolated_home)
    root.mkdir(parents=True, exist_ok=True)
    (root / "random.json").write_text(
        json.dumps({"foo": "bar"}, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    (root / "e2ee_orphan.json").write_text(
        json.dumps({"local_did": "did:wba:awiki.ai:user:k1_orphan", "sessions": []}),
        encoding="utf-8",
    )

    result = credential_migration.migrate_legacy_credentials()

    assert result["status"] == "not_needed"
    assert result["legacy_credentials"] == []
    assert result["migrated"] == []
    assert result["invalid_json_files"] == [
        {
            "file": "random.json",
            "reason": "not_a_legacy_credential_payload",
        }
    ]
    assert result["orphan_e2ee_files"] == [
        {
            "credential_name": "orphan",
            "file": "e2ee_orphan.json",
        }
    ]


def test_list_identities_reads_from_index(isolated_home) -> None:
    """Identity listing should be index-backed in the new layout."""
    _save_sample_identity(handle="alice", name="default")
    _save_sample_identity(handle=None, name="backup", did="did:wba:awiki.ai:user:k1_backup", unique_id="k1_backup")

    identities = credential_store.list_identities()

    assert [identity["credential_name"] for identity in identities] == ["backup", "default"]
    assert identities[1]["handle"] == "alice"
    assert identities[1]["is_default"] is True
    assert identities[1]["dir_name"] == "k1_test"


def test_multiple_credential_names_can_reference_same_unique_id_directory(isolated_home) -> None:
    """Different credential names for the same DID should share the unique_id directory."""
    _save_sample_identity(
        handle="alice",
        name="default",
        did="did:wba:awiki.ai:alice:k1_same",
        unique_id="k1_same",
    )
    path = _save_sample_identity(
        handle="alice",
        name="alice_alias",
        did="did:wba:awiki.ai:alice:k1_same",
        unique_id="k1_same",
    )

    root = _credentials_root(isolated_home)
    index = json.loads((root / "index.json").read_text(encoding="utf-8"))

    assert path == root / "k1_same" / "identity.json"
    assert index["credentials"]["default"]["dir_name"] == "k1_same"
    assert index["credentials"]["alice_alias"]["dir_name"] == "k1_same"


def test_delete_identity_keeps_shared_directory_until_last_reference(isolated_home) -> None:
    """Deleting one alias should not remove a shared unique_id directory too early."""
    _save_sample_identity(
        handle="alice",
        name="default",
        did="did:wba:awiki.ai:alice:k1_same",
        unique_id="k1_same",
    )
    _save_sample_identity(
        handle="alice",
        name="alice_alias",
        did="did:wba:awiki.ai:alice:k1_same",
        unique_id="k1_same",
    )

    root = _credentials_root(isolated_home)
    credential_dir = root / "k1_same"

    assert credential_store.delete_identity("alice_alias") is True
    assert credential_dir.exists()
    assert credential_store.delete_identity("default") is True
    assert not credential_dir.exists()
