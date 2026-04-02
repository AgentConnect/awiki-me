"""Tests for local contact sedimentation workflows.

[INPUT]: manage_contacts / manage_relationship / send_message entrypoints with monkeypatched
         local identity and RPC dependencies
[OUTPUT]: Regression coverage for contact snapshot and relationship-event persistence
[POS]: CLI-level tests for local relationship sedimentation

[PROTOCOL]:
1. Update this header when logic changes
2. Check the folder's CLAUDE.md after updates
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

import local_store  # noqa: E402
import manage_contacts as manage_contacts_cli  # noqa: E402
import manage_relationship as manage_relationship_cli  # noqa: E402
import send_message as send_message_cli  # noqa: E402


class _AsyncClientContext:
    """Simple async context manager for fake clients."""

    def __init__(self, client: object) -> None:
        self._client = client

    async def __aenter__(self) -> object:
        return self._client

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        del exc_type, exc, tb
        return False


@pytest.fixture()
def temp_local_db(tmp_path, monkeypatch):
    """Provide a temporary local SQLite database."""
    monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
    conn = local_store.get_connection()
    local_store.ensure_schema(conn)
    conn.close()
    return tmp_path


class TestManageContactsCli:
    """manage_contacts persistence behavior."""

    def test_record_recommendation_writes_event(
        self,
        monkeypatch: pytest.MonkeyPatch,
        temp_local_db: Path,
    ) -> None:
        del temp_local_db
        monkeypatch.setattr(
            manage_contacts_cli,
            "_identity_or_exit",
            lambda credential_name: {"did": "did:alice", "handle": "alice.awiki.ai"},
        )
        args = manage_contacts_cli._build_parser().parse_args(
            [
                "--record-recommendation",
                "--target-did",
                "did:bob",
                "--target-handle",
                "bob.awiki.ai",
                "--source-type",
                "meetup",
                "--source-name",
                "OpenClaw Meetup Hangzhou 2026",
                "--source-group-id",
                "grp_1",
                "--reason",
                "Strong protocol fit",
                "--score",
                "0.9",
            ]
        )

        manage_contacts_cli.record_recommendation(args)

        conn = local_store.get_connection()
        row = conn.execute(
            "SELECT event_type, status, source_group_id FROM relationship_events WHERE target_did='did:bob'"
        ).fetchone()
        conn.close()
        assert row["event_type"] == "ai_recommended"
        assert row["status"] == "pending"
        assert row["source_group_id"] == "grp_1"

    def test_save_from_group_writes_contact_snapshot(
        self,
        monkeypatch: pytest.MonkeyPatch,
        temp_local_db: Path,
    ) -> None:
        del temp_local_db
        monkeypatch.setattr(
            manage_contacts_cli,
            "_identity_or_exit",
            lambda credential_name: {"did": "did:alice", "handle": "alice.awiki.ai"},
        )
        args = manage_contacts_cli._build_parser().parse_args(
            [
                "--save-from-group",
                "--target-did",
                "did:bob",
                "--target-handle",
                "bob.awiki.ai",
                "--source-type",
                "meetup",
                "--source-name",
                "OpenClaw Meetup Hangzhou 2026",
                "--source-group-id",
                "grp_1",
                "--reason",
                "Strong protocol fit",
                "--text",
                "Met at the venue.",
            ]
        )

        manage_contacts_cli.save_from_group(args)

        conn = local_store.get_connection()
        contact_row = conn.execute(
            """
            SELECT source_type, source_name, source_group_id, recommended_reason, note
            FROM contacts
            WHERE owner_did='did:alice' AND did='did:bob'
            """
        ).fetchone()
        event_row = conn.execute(
            """
            SELECT event_type, status
            FROM relationship_events
            WHERE owner_did='did:alice' AND target_did='did:bob'
            ORDER BY created_at DESC
            LIMIT 1
            """
        ).fetchone()
        conn.close()
        assert contact_row["source_type"] == "meetup"
        assert contact_row["source_group_id"] == "grp_1"
        assert contact_row["recommended_reason"] == "Strong protocol fit"
        assert contact_row["note"] == "Met at the venue."
        assert event_row["event_type"] == "saved_to_contacts"
        assert event_row["status"] == "accepted"


class TestSocialPersistence:
    """Existing social actions should update local sedimentation."""

    def test_follow_updates_contact_and_event(
        self,
        monkeypatch: pytest.MonkeyPatch,
        temp_local_db: Path,
    ) -> None:
        del temp_local_db
        monkeypatch.setattr(
            manage_relationship_cli,
            "create_authenticator",
            lambda credential_name, config: (object(), {"did": "did:alice"}),
        )
        monkeypatch.setattr(
            manage_relationship_cli,
            "create_user_service_client",
            lambda config: _AsyncClientContext(object()),
        )

        async def _fake_rpc_call(client, endpoint, method, params, auth, credential_name):
            del client, endpoint, params, auth, credential_name
            assert method == "follow"
            return {"ok": True}

        monkeypatch.setattr(
            manage_relationship_cli,
            "authenticated_rpc_call",
            _fake_rpc_call,
        )

        asyncio.run(manage_relationship_cli.follow("did:bob", "alice"))

        conn = local_store.get_connection()
        contact_row = conn.execute(
            "SELECT relationship, followed FROM contacts WHERE owner_did='did:alice' AND did='did:bob'"
        ).fetchone()
        event_row = conn.execute(
            """
            SELECT event_type, status
            FROM relationship_events
            WHERE owner_did='did:alice' AND target_did='did:bob'
            ORDER BY created_at DESC
            LIMIT 1
            """
        ).fetchone()
        conn.close()
        assert contact_row["relationship"] == "following"
        assert contact_row["followed"] == 1
        assert event_row["event_type"] == "followed"
        assert event_row["status"] == "applied"

    def test_send_message_marks_contact_as_messaged(
        self,
        monkeypatch: pytest.MonkeyPatch,
        temp_local_db: Path,
    ) -> None:
        del temp_local_db
        monkeypatch.setattr(
            send_message_cli,
            "resolve_to_did",
            lambda receiver, config: asyncio.sleep(0, result="did:bob"),
        )
        monkeypatch.setattr(
            send_message_cli,
            "create_authenticator",
            lambda credential_name, config: (object(), {"did": "did:alice"}),
        )
        monkeypatch.setattr(
            send_message_cli,
            "create_molt_message_client",
            lambda config: _AsyncClientContext(object()),
        )

        async def _fake_rpc_call(client, endpoint, method, params, auth, credential_name):
            del client, endpoint, auth, credential_name
            assert method == "send"
            assert params["receiver_did"] == "did:bob"
            return {
                "id": "msg_1",
                "server_seq": 3,
                "sent_at": "2026-03-10T12:00:00+00:00",
            }

        monkeypatch.setattr(send_message_cli, "authenticated_rpc_call", _fake_rpc_call)

        asyncio.run(
            send_message_cli.send_message(
                receiver="did:bob",
                content="Hello Bob",
                credential_name="alice",
            )
        )

        conn = local_store.get_connection()
        contact_row = conn.execute(
            "SELECT messaged FROM contacts WHERE owner_did='did:alice' AND did='did:bob'"
        ).fetchone()
        event_row = conn.execute(
            """
            SELECT event_type, status
            FROM relationship_events
            WHERE owner_did='did:alice' AND target_did='did:bob'
            ORDER BY created_at DESC
            LIMIT 1
            """
        ).fetchone()
        conn.close()
        assert contact_row["messaged"] == 1
        assert event_row["event_type"] == "messaged"
        assert event_row["status"] == "applied"
