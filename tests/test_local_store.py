"""Unit tests for local_store module."""

from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

import local_store  # noqa: E402

EXPECTED_SCHEMA_INDEXES = {
    "idx_contacts_owner",
    "idx_contacts_owner_source_group",
    "idx_messages_owner_thread",
    "idx_messages_owner_thread_seq",
    "idx_messages_owner_direction",
    "idx_messages_owner_sender",
    "idx_messages_owner",
    "idx_messages_credential",
    "idx_e2ee_outbox_owner_status",
    "idx_e2ee_outbox_owner_sent_msg",
    "idx_e2ee_outbox_owner_sent_seq",
    "idx_e2ee_outbox_credential",
    "idx_e2ee_sessions_owner_updated",
    "idx_e2ee_sessions_credential",
    "idx_groups_owner_status_last_message",
    "idx_groups_owner_slug",
    "idx_groups_owner_updated",
    "idx_group_members_owner_group_role",
    "idx_group_members_owner_group_status",
    "idx_relationship_events_owner_target_time",
    "idx_relationship_events_owner_status_time",
    "idx_relationship_events_owner_group",
}


def _schema_object_names(conn: sqlite3.Connection, object_type: str) -> set[str]:
    """Return named schema objects for assertions."""
    rows = conn.execute(
        """
        SELECT name FROM sqlite_master
        WHERE type = ? AND name NOT LIKE 'sqlite_%'
        """,
        (object_type,),
    ).fetchall()
    return {row[0] for row in rows}


@pytest.fixture()
def db(tmp_path, monkeypatch):
    """Create a temporary SQLite database for testing."""
    monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
    conn = local_store.get_connection()
    local_store.ensure_schema(conn)
    yield conn
    conn.close()


class TestSchema:
    """Schema creation and versioning."""

    def test_tables_created(self, db):
        tables = {
            row[0]
            for row in db.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        assert "contacts" in tables
        assert "messages" in tables
        assert "e2ee_outbox" in tables
        assert "e2ee_sessions" in tables
        assert "groups" in tables
        assert "group_members" in tables
        assert "relationship_events" in tables

    def test_views_created(self, db):
        views = _schema_object_names(db, "view")
        assert "threads" in views
        assert "inbox" in views
        assert "outbox" in views

    def test_expected_indexes_created(self, db):
        indexes = _schema_object_names(db, "index")
        assert EXPECTED_SCHEMA_INDEXES <= indexes

    def test_schema_version(self, db):
        version = db.execute("PRAGMA user_version").fetchone()[0]
        assert version == 11

    def test_ensure_schema_idempotent(self, db):
        """Calling ensure_schema multiple times is safe."""
        local_store.ensure_schema(db)
        local_store.ensure_schema(db)
        version = db.execute("PRAGMA user_version").fetchone()[0]
        assert version == 11

    def test_wal_mode(self, db):
        mode = db.execute("PRAGMA journal_mode").fetchone()[0]
        assert mode == "wal"

    def test_credential_name_column_exists(self, db):
        message_columns = {
            row[1]
            for row in db.execute("PRAGMA table_info(messages)").fetchall()
        }
        contact_columns = {
            row[1] for row in db.execute("PRAGMA table_info(contacts)").fetchall()
        }
        outbox_columns = {
            row[1] for row in db.execute("PRAGMA table_info(e2ee_outbox)").fetchall()
        }
        session_columns = {
            row[1] for row in db.execute("PRAGMA table_info(e2ee_sessions)").fetchall()
        }
        group_columns = {
            row[1] for row in db.execute("PRAGMA table_info(groups)").fetchall()
        }
        group_member_columns = {
            row[1] for row in db.execute("PRAGMA table_info(group_members)").fetchall()
        }
        relationship_event_columns = {
            row[1]
            for row in db.execute("PRAGMA table_info(relationship_events)").fetchall()
        }
        assert "credential_name" in message_columns
        assert "title" in message_columns
        assert "owner_did" in contact_columns
        assert "owner_did" in message_columns
        assert "owner_did" in outbox_columns
        assert "session_id" in session_columns
        assert "peer_confirmed" in session_columns
        assert "source_group_id" in contact_columns
        assert "recommended_reason" in contact_columns
        assert "followed" in contact_columns
        assert "messaged" in contact_columns
        assert "note" in contact_columns
        assert "join_code" in group_columns
        assert "join_code_expires_at" in group_columns
        assert "group_owner_did" in group_columns
        assert "member_did" in group_member_columns
        assert "profile_url" in group_member_columns
        assert "event_type" in relationship_event_columns
        assert "source_group_id" in relationship_event_columns
        assert "score" in relationship_event_columns

    def test_database_path(self, tmp_path, monkeypatch):
        monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
        conn = local_store.get_connection()
        local_store.ensure_schema(conn)
        conn.close()
        assert (tmp_path / "database" / "awiki.db").exists()

    def test_ensure_schema_repairs_missing_indexes_on_v6_database(self, db):
        db.execute("DROP INDEX idx_messages_owner_thread")
        db.execute("DROP INDEX idx_messages_owner_direction")
        db.execute("DROP INDEX idx_e2ee_outbox_owner_status")
        db.commit()

        before_indexes = _schema_object_names(db, "index")
        assert "idx_messages_owner_thread" not in before_indexes
        assert "idx_messages_owner_direction" not in before_indexes
        assert "idx_e2ee_outbox_owner_status" not in before_indexes

        local_store.ensure_schema(db)

        after_indexes = _schema_object_names(db, "index")
        version = db.execute("PRAGMA user_version").fetchone()[0]

        assert version == 11
        assert EXPECTED_SCHEMA_INDEXES <= after_indexes


class TestThreadId:
    """Thread ID generation."""

    def test_dm_sorted(self):
        tid1 = local_store.make_thread_id("did:a", peer_did="did:b")
        tid2 = local_store.make_thread_id("did:b", peer_did="did:a")
        assert tid1 == tid2
        assert tid1.startswith("dm:")

    def test_group(self):
        tid = local_store.make_thread_id("did:a", group_id="g1")
        assert tid == "group:g1"


class TestStoreMessage:
    """Single message storage."""

    def test_store_and_retrieve(self, db):
        local_store.store_message(
            db,
            msg_id="m1",
            owner_did="did:self",
            thread_id="dm:a:b",
            direction=0,
            sender_did="did:a",
            content="hello",
        )
        rows = db.execute("SELECT * FROM messages WHERE msg_id='m1'").fetchall()
        assert len(rows) == 1
        assert rows[0]["content"] == "hello"
        assert rows[0]["owner_did"] == "did:self"

    def test_dedup_scoped_by_owner_did(self, db):
        local_store.store_message(
            db,
            msg_id="m_dup",
            owner_did="did:alice",
            thread_id="dm:a:b",
            direction=0,
            sender_did="did:a",
            content="hello",
        )
        local_store.store_message(
            db,
            msg_id="m_dup",
            owner_did="did:alice",
            thread_id="dm:a:b",
            direction=0,
            sender_did="did:a",
            content="hello",
        )
        local_store.store_message(
            db,
            msg_id="m_dup",
            owner_did="did:bob",
            thread_id="dm:a:b",
            direction=0,
            sender_did="did:a",
            content="hello",
        )
        count = db.execute(
            "SELECT COUNT(*) FROM messages WHERE msg_id='m_dup'"
        ).fetchone()[0]
        assert count == 2

    def test_get_message_by_id_uses_owner_did(self, db):
        local_store.store_message(
            db,
            msg_id="m_lookup",
            owner_did="did:alice",
            thread_id="dm:a:b",
            direction=1,
            sender_did="did:alice",
            content="lookup",
            credential_name="alice",
        )
        row = local_store.get_message_by_id(
            db,
            msg_id="m_lookup",
            owner_did="did:alice",
        )
        assert row is not None
        assert row["content"] == "lookup"


class TestStoreMessagesBatch:
    """Batch message storage."""

    def test_batch_with_default_owner(self, db):
        batch = [
            {"msg_id": f"b{i}", "thread_id": "dm:a:b", "direction": 0,
             "sender_did": "did:a", "content": f"msg {i}"}
            for i in range(3)
        ]
        local_store.store_messages_batch(db, batch, owner_did="did:alice")
        owners = {
            row["owner_did"]
            for row in db.execute("SELECT owner_did FROM messages").fetchall()
        }
        assert owners == {"did:alice"}

    def test_batch_per_message_owner_override(self, db):
        batch = [
            {"msg_id": "bo1", "owner_did": "did:alice", "thread_id": "dm:a:b", "direction": 0,
             "sender_did": "did:a", "content": "msg1"},
            {"msg_id": "bo2", "thread_id": "dm:a:b", "direction": 0,
             "sender_did": "did:a", "content": "msg2"},
        ]
        local_store.store_messages_batch(db, batch, owner_did="did:bob")
        rows = {
            row["msg_id"]: row["owner_did"]
            for row in db.execute("SELECT msg_id, owner_did FROM messages").fetchall()
        }
        assert rows["bo1"] == "did:alice"
        assert rows["bo2"] == "did:bob"


class TestUpsertContact:
    """Contact insert/update with owner isolation."""

    def test_insert_new_contact(self, db):
        local_store.upsert_contact(
            db,
            owner_did="did:alice",
            did="did:c1",
            name="Alice",
            handle="alice",
        )
        row = db.execute(
            "SELECT * FROM contacts WHERE owner_did='did:alice' AND did='did:c1'"
        ).fetchone()
        assert row["name"] == "Alice"
        assert row["handle"] == "alice"

    def test_contact_sedimentation_fields_are_persisted(self, db):
        local_store.upsert_contact(
            db,
            owner_did="did:alice",
            did="did:bob",
            source_type="meetup",
            source_name="OpenClaw Meetup Hangzhou 2026",
            source_group_id="grp_1",
            connected_at="2026-03-10T10:00:00+00:00",
            recommended_reason="Strong protocol fit",
            followed=True,
            messaged=False,
            note="Met at the venue.",
        )
        row = db.execute(
            """
            SELECT source_type, source_name, source_group_id, connected_at,
                   recommended_reason, followed, messaged, note
            FROM contacts
            WHERE owner_did='did:alice' AND did='did:bob'
            """
        ).fetchone()
        assert row["source_type"] == "meetup"
        assert row["source_group_id"] == "grp_1"
        assert row["recommended_reason"] == "Strong protocol fit"
        assert row["followed"] == 1
        assert row["messaged"] == 0
        assert row["note"] == "Met at the venue."

    def test_same_contact_can_exist_for_multiple_owners(self, db):
        local_store.upsert_contact(
            db,
            owner_did="did:alice",
            did="did:bob",
            relationship="following",
        )
        local_store.upsert_contact(
            db,
            owner_did="did:charlie",
            did="did:bob",
            relationship="none",
        )
        rows = db.execute(
            "SELECT owner_did, relationship FROM contacts WHERE did='did:bob' ORDER BY owner_did"
        ).fetchall()
        assert len(rows) == 2
        assert rows[0]["relationship"] == "following"
        assert rows[1]["relationship"] == "none"

    def test_rebind_owner_did_moves_contacts(self, db):
        local_store.upsert_contact(
            db,
            owner_did="did:old",
            did="did:bob",
            relationship="following",
        )
        summary = local_store.rebind_owner_did(
            db,
            old_owner_did="did:old",
            new_owner_did="did:new",
        )
        row = db.execute(
            "SELECT owner_did, relationship FROM contacts WHERE did='did:bob'"
        ).fetchone()
        assert summary["contacts"] == 1
        assert row["owner_did"] == "did:new"

    def test_rebind_owner_did_moves_groups_and_members(self, db):
        local_store.upsert_group(
            db,
            owner_did="did:old",
            group_id="grp_1",
            name="Group One",
            my_role="member",
            membership_status="active",
        )
        local_store.replace_group_members(
            db,
            owner_did="did:old",
            group_id="grp_1",
            members=[{"user_id": "user_1", "did": "did:old", "role": "member"}],
        )
        local_store.append_relationship_event(
            db,
            owner_did="did:old",
            target_did="did:bob",
            event_type="ai_recommended",
            source_group_id="grp_1",
        )

        summary = local_store.rebind_owner_did(
            db,
            old_owner_did="did:old",
            new_owner_did="did:new",
        )
        group_row = db.execute(
            "SELECT owner_did FROM groups WHERE group_id='grp_1'"
        ).fetchone()
        member_row = db.execute(
            "SELECT owner_did FROM group_members WHERE group_id='grp_1' AND user_id='user_1'"
        ).fetchone()
        event_row = db.execute(
            "SELECT owner_did FROM relationship_events WHERE target_did='did:bob'"
        ).fetchone()
        assert summary["groups"] == 1
        assert summary["group_members"] == 1
        assert summary["relationship_events"] == 1
        assert group_row["owner_did"] == "did:new"
        assert member_row["owner_did"] == "did:new"
        assert event_row["owner_did"] == "did:new"


class TestRelationshipEvents:
    """Relationship-event persistence."""

    def test_append_relationship_event(self, db):
        event_id = local_store.append_relationship_event(
            db,
            owner_did="did:alice",
            target_did="did:bob",
            target_handle="bob.awiki.ai",
            event_type="ai_recommended",
            source_type="meetup",
            source_name="OpenClaw Meetup Hangzhou 2026",
            source_group_id="grp_1",
            reason="Strong protocol fit",
            score=0.91,
            status="pending",
            metadata={"why": "shared infra focus"},
            credential_name="alice",
        )
        row = db.execute(
            "SELECT * FROM relationship_events WHERE event_id = ?",
            (event_id,),
        ).fetchone()
        assert row["owner_did"] == "did:alice"
        assert row["target_did"] == "did:bob"
        assert row["event_type"] == "ai_recommended"
        assert row["source_group_id"] == "grp_1"
        assert row["status"] == "pending"
        assert row["score"] == 0.91


class TestGroups:
    """Local group-state persistence."""

    def test_upsert_group_persists_owner_and_join_code(self, db):
        local_store.upsert_group(
            db,
            owner_did="did:alice",
            group_id="grp_1",
            name="OpenClaw Meetup",
            my_role="owner",
            membership_status="active",
            join_enabled=True,
            join_code="314159",
            join_code_expires_at="2026-03-10T12:00:00+00:00",
            group_owner_did="did:alice",
            group_owner_handle="alice.awiki.ai",
            credential_name="alice",
        )
        row = db.execute(
            "SELECT * FROM groups WHERE owner_did='did:alice' AND group_id='grp_1'"
        ).fetchone()
        assert row["name"] == "OpenClaw Meetup"
        assert row["group_mode"] == "general"
        assert row["my_role"] == "owner"
        assert row["join_enabled"] == 1
        assert row["join_code"] == "314159"

    def test_replace_group_members_replaces_snapshot(self, db):
        local_store.replace_group_members(
            db,
            owner_did="did:alice",
            group_id="grp_1",
            members=[
                {
                    "user_id": "user_1",
                    "did": "did:alice",
                    "handle": "alice.awiki.ai",
                    "profile_url": "https://awiki.ai/profiles/user_1",
                    "role": "owner",
                    "joined_at": "2026-03-10T00:00:00+00:00",
                    "sent_message_count": 1,
                },
                {
                    "user_id": "user_2",
                    "did": "did:bob",
                    "handle": "bob.awiki.ai",
                    "profile_url": "https://awiki.ai/profiles/user_2",
                    "role": "member",
                    "joined_at": "2026-03-10T00:01:00+00:00",
                    "sent_message_count": 0,
                },
            ],
            credential_name="alice",
        )
        local_store.replace_group_members(
            db,
            owner_did="did:alice",
            group_id="grp_1",
            members=[
                {
                    "user_id": "user_1",
                    "did": "did:alice",
                    "handle": "alice.awiki.ai",
                    "profile_url": "https://awiki.ai/profiles/user_1",
                    "role": "owner",
                    "joined_at": "2026-03-10T00:00:00+00:00",
                    "sent_message_count": 2,
                }
            ],
            credential_name="alice",
        )
        rows = db.execute(
            """
            SELECT user_id, profile_url, sent_message_count
            FROM group_members
            WHERE owner_did='did:alice' AND group_id='grp_1'
            """
        ).fetchall()
        assert len(rows) == 1
        assert rows[0]["user_id"] == "user_1"
        assert rows[0]["profile_url"] == "https://awiki.ai/profiles/user_1"
        assert rows[0]["sent_message_count"] == 2

    def test_delete_group_members_by_target_did(self, db):
        local_store.replace_group_members(
            db,
            owner_did="did:alice",
            group_id="grp_1",
            members=[
                {
                    "user_id": "user_1",
                    "did": "did:alice",
                    "role": "owner",
                },
                {
                    "user_id": "user_2",
                    "did": "did:bob",
                    "role": "member",
                },
            ],
        )
        deleted = local_store.delete_group_members(
            db,
            owner_did="did:alice",
            group_id="grp_1",
            target_did="did:bob",
        )
        count = db.execute(
            "SELECT COUNT(*) FROM group_members WHERE owner_did='did:alice' AND group_id='grp_1'"
        ).fetchone()[0]
        assert deleted == 1
        assert count == 1

    def test_sync_group_member_from_system_event_updates_status(self, db):
        local_store.upsert_group(
            db,
            owner_did="did:alice",
            group_id="grp_1",
            name="Group One",
        )
        synced = local_store.sync_group_member_from_system_event(
            db,
            owner_did="did:alice",
            group_id="grp_1",
            system_event={
                "kind": "member_joined",
                "subject": {
                    "id": "user_2",
                    "did": "did:bob",
                    "handle": "bob.awiki.ai",
                    "profile_url": "https://awiki.ai/profiles/user_2",
                },
                "actor": {
                    "id": "user_2",
                    "did": "did:bob",
                    "handle": "bob.awiki.ai",
                    "profile_url": "https://awiki.ai/profiles/user_2",
                },
            },
        )
        row = db.execute(
            """
            SELECT status, member_did, profile_url
            FROM group_members
            WHERE owner_did='did:alice' AND group_id='grp_1' AND user_id='user_2'
            """
        ).fetchone()
        assert synced is True
        assert row["status"] == "active"
        assert row["member_did"] == "did:bob"
        assert row["profile_url"] == "https://awiki.ai/profiles/user_2"


class TestE2eeOutbox:
    """E2EE outbox persistence and retry status tracking."""

    def test_queue_and_fetch_outbox_record(self, db):
        outbox_id = local_store.queue_e2ee_outbox(
            db,
            owner_did="did:alice",
            peer_did="did:b",
            plaintext="secret",
            session_id="sess-1",
            credential_name="alice",
        )
        record = local_store.get_e2ee_outbox(
            db,
            outbox_id=outbox_id,
            owner_did="did:alice",
        )
        assert record is not None
        assert record["peer_did"] == "did:b"
        assert record["owner_did"] == "did:alice"

    def test_mark_outbox_failed_uses_owner_did(self, db):
        outbox_id = local_store.queue_e2ee_outbox(
            db,
            owner_did="did:alice",
            peer_did="did:b",
            plaintext="secret",
            session_id="sess-1",
            credential_name="alice",
        )
        local_store.mark_e2ee_outbox_sent(
            db,
            outbox_id=outbox_id,
            owner_did="did:alice",
            credential_name="alice",
            sent_msg_id="msg-1",
            sent_server_seq=7,
        )
        matched = local_store.mark_e2ee_outbox_failed(
            db,
            owner_did="did:alice",
            peer_did="did:b",
            failed_msg_id="msg-1",
            error_code="decryption_failed",
            retry_hint="resend",
        )
        assert matched == outbox_id
        record = local_store.get_e2ee_outbox(
            db,
            outbox_id=outbox_id,
            owner_did="did:alice",
        )
        assert record["local_status"] == "failed"

    def test_clear_owner_e2ee_data_removes_session_and_outbox_records(self, db):
        outbox_id = local_store.queue_e2ee_outbox(
            db,
            owner_did="did:alice",
            peer_did="did:b",
            plaintext="secret",
            credential_name="alice",
        )
        db.execute(
            """
            INSERT INTO e2ee_sessions
            (owner_did, peer_did, session_id, is_initiator, send_chain_key,
             recv_chain_key, send_seq, recv_seq, expires_at, created_at,
             active_at, peer_confirmed, credential_name, updated_at)
            VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "did:alice",
                "did:b",
                "sess-1",
                1,
                "send",
                "recv",
                1,
                2,
                None,
                "2026-03-10T00:00:00+00:00",
                "2026-03-10T00:00:00+00:00",
                0,
                "alice",
                "2026-03-10T00:00:00+00:00",
            ),
        )
        db.commit()
        summary = local_store.clear_owner_e2ee_data(
            db,
            owner_did="did:alice",
            credential_name="alice",
        )
        record = local_store.get_e2ee_outbox(
            db,
            outbox_id=outbox_id,
            owner_did="did:alice",
        )
        session = db.execute(
            "SELECT * FROM e2ee_sessions WHERE owner_did = ?",
            ("did:alice",),
        ).fetchone()
        assert summary["e2ee_outbox"] == 1
        assert summary["e2ee_sessions"] == 1
        assert record is None
        assert session is None


class TestViews:
    """View correctness with owner_did grouping."""

    def test_threads_view_groups_by_owner_did(self, db):
        local_store.store_message(
            db,
            msg_id="v1",
            owner_did="did:alice",
            thread_id="group:g1",
            direction=0,
            sender_did="did:x",
            content="hello",
        )
        local_store.store_message(
            db,
            msg_id="v2",
            owner_did="did:bob",
            thread_id="group:g1",
            direction=0,
            sender_did="did:x",
            content="world",
        )
        rows = db.execute(
            "SELECT owner_did, thread_id, message_count FROM threads ORDER BY owner_did"
        ).fetchall()
        assert len(rows) == 2
        assert rows[0]["owner_did"] == "did:alice"
        assert rows[1]["owner_did"] == "did:bob"

    def test_inbox_and_outbox_views_include_owner_did(self, db):
        local_store.store_message(
            db,
            msg_id="in1",
            owner_did="did:alice",
            thread_id="dm:a:b",
            direction=0,
            sender_did="did:a",
            content="incoming",
        )
        local_store.store_message(
            db,
            msg_id="out1",
            owner_did="did:alice",
            thread_id="dm:a:b",
            direction=1,
            sender_did="did:alice",
            content="outgoing",
        )
        inbox = db.execute("SELECT owner_did, msg_id FROM inbox").fetchall()
        outbox = db.execute("SELECT owner_did, msg_id FROM outbox").fetchall()
        assert inbox[0]["owner_did"] == "did:alice"
        assert outbox[0]["owner_did"] == "did:alice"


class TestExecuteSql:
    """SQL safety checks."""

    def test_select(self, db):
        local_store.store_message(
            db,
            msg_id="s1",
            owner_did="did:self",
            thread_id="dm:a:b",
            direction=0,
            sender_did="did:a",
            content="test",
        )
        result = local_store.execute_sql(db, "SELECT COUNT(*) as cnt FROM messages")
        assert result[0]["cnt"] == 1

    def test_reject_drop(self, db):
        with pytest.raises(ValueError, match="Forbidden"):
            local_store.execute_sql(db, "DROP TABLE messages")

    def test_reject_delete_without_where(self, db):
        with pytest.raises(
            ValueError,
            match="Forbidden SQL operation: DELETE without WHERE clause is not allowed",
        ):
            local_store.execute_sql(db, "DELETE FROM messages")

    def test_allow_delete_with_where(self, db):
        local_store.store_message(
            db,
            msg_id="del1",
            owner_did="did:self",
            thread_id="dm:a:b",
            direction=0,
            sender_did="did:a",
            content="to delete",
        )
        result = local_store.execute_sql(
            db, "DELETE FROM messages WHERE msg_id='del1'"
        )
        assert result[0]["rows_affected"] == 1


class TestMigration:
    """Migration from legacy schemas should preserve v6 ownership semantics."""

    def test_migrate_v4_schema_to_v6(self, tmp_path, monkeypatch):
        monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
        monkeypatch.setenv("HOME", str(tmp_path))
        db_dir = tmp_path / "database"
        db_dir.mkdir(parents=True, exist_ok=True)
        db_path = db_dir / "awiki.db"

        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        conn.executescript("""
            CREATE TABLE contacts (
                did TEXT PRIMARY KEY,
                name TEXT,
                handle TEXT,
                nick_name TEXT,
                bio TEXT,
                profile_md TEXT,
                tags TEXT,
                relationship TEXT,
                first_seen_at TEXT,
                last_seen_at TEXT,
                metadata TEXT
            );
            CREATE TABLE messages (
                msg_id TEXT NOT NULL,
                thread_id TEXT NOT NULL,
                direction INTEGER NOT NULL DEFAULT 0,
                sender_did TEXT,
                receiver_did TEXT,
                group_id TEXT,
                group_did TEXT,
                content_type TEXT DEFAULT 'text',
                content TEXT,
                server_seq INTEGER,
                sent_at TEXT,
                stored_at TEXT NOT NULL,
                is_e2ee INTEGER DEFAULT 0,
                is_read INTEGER DEFAULT 0,
                sender_name TEXT,
                metadata TEXT,
                credential_name TEXT NOT NULL DEFAULT '',
                PRIMARY KEY (msg_id, credential_name)
            );
            CREATE TABLE e2ee_outbox (
                outbox_id TEXT PRIMARY KEY,
                peer_did TEXT NOT NULL,
                session_id TEXT,
                original_type TEXT NOT NULL DEFAULT 'text',
                plaintext TEXT NOT NULL,
                local_status TEXT NOT NULL DEFAULT 'queued',
                attempt_count INTEGER NOT NULL DEFAULT 0,
                sent_msg_id TEXT,
                sent_server_seq INTEGER,
                last_error_code TEXT,
                retry_hint TEXT,
                failed_msg_id TEXT,
                failed_server_seq INTEGER,
                metadata TEXT,
                last_attempt_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                credential_name TEXT NOT NULL DEFAULT ''
            );
            PRAGMA user_version = 4;
        """)
        conn.execute(
            "INSERT INTO contacts (did, relationship) VALUES ('did:peer', 'following')"
        )
        conn.execute(
            """
            INSERT INTO messages
            (msg_id, thread_id, direction, sender_did, receiver_did, content, stored_at, credential_name)
            VALUES ('m1', 'dm:did:alice:did:peer', 1, 'did:alice', 'did:peer', 'hello', '2026-01-01T00:00:00+00:00', 'alice')
            """
        )
        conn.execute(
            """
            INSERT INTO e2ee_outbox
            (outbox_id, peer_did, plaintext, created_at, updated_at, credential_name)
            VALUES ('o1', 'did:peer', 'secret', '2026-01-01T00:00:00+00:00', '2026-01-01T00:00:00+00:00', 'alice')
            """
        )
        conn.commit()
        conn.close()

        cred_root = tmp_path / ".openclaw" / "credentials" / "awiki-agent-id-message"
        cred_root.mkdir(parents=True, exist_ok=True)
        (cred_root / "index.json").write_text(
            json.dumps(
                {
                    "schema_version": 3,
                    "default_credential_name": "alice",
                    "credentials": {
                        "alice": {
                            "credential_name": "alice",
                            "dir_name": "k1_alice",
                            "did": "did:alice",
                            "unique_id": "k1_alice",
                            "is_default": True,
                        }
                    },
                },
                indent=2,
                ensure_ascii=False,
            ),
            encoding="utf-8",
        )

        conn = local_store.get_connection()
        local_store.ensure_schema(conn)
        version = conn.execute("PRAGMA user_version").fetchone()[0]
        migrated_message = conn.execute(
            "SELECT owner_did FROM messages WHERE msg_id='m1'"
        ).fetchone()
        migrated_contact = conn.execute(
            "SELECT owner_did FROM contacts WHERE did='did:peer'"
        ).fetchone()
        migrated_outbox = conn.execute(
            "SELECT owner_did FROM e2ee_outbox WHERE outbox_id='o1'"
        ).fetchone()
        migrated_new_tables = {
            row[0]
            for row in conn.execute(
                """
                SELECT name FROM sqlite_master
                WHERE type='table'
                  AND name IN ('groups', 'group_members', 'relationship_events', 'e2ee_sessions')
                """
            ).fetchall()
        }
        conn.close()

        assert version == 11
        assert migrated_message["owner_did"] == "did:alice"
        assert migrated_contact["owner_did"] == "did:alice"
        assert migrated_outbox["owner_did"] == "did:alice"
        assert migrated_new_tables == {
            "groups",
            "group_members",
            "relationship_events",
            "e2ee_sessions",
        }

    def test_migrate_real_v6_schema_to_v9_without_manual_contact_column_patch(
        self,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        """A historical v6 database should upgrade even when contacts lacks v8 fields."""
        monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))
        db_dir = tmp_path / "database"
        db_dir.mkdir(parents=True, exist_ok=True)
        db_path = db_dir / "awiki.db"

        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        conn.executescript("""
            CREATE TABLE contacts (
                owner_did TEXT NOT NULL DEFAULT '',
                did TEXT NOT NULL,
                name TEXT,
                handle TEXT,
                nick_name TEXT,
                bio TEXT,
                profile_md TEXT,
                tags TEXT,
                relationship TEXT,
                first_seen_at TEXT,
                last_seen_at TEXT,
                metadata TEXT,
                PRIMARY KEY (owner_did, did)
            );
            CREATE TABLE messages (
                msg_id TEXT NOT NULL,
                owner_did TEXT NOT NULL DEFAULT '',
                thread_id TEXT NOT NULL,
                direction INTEGER NOT NULL DEFAULT 0,
                sender_did TEXT,
                receiver_did TEXT,
                group_id TEXT,
                group_did TEXT,
                content_type TEXT DEFAULT 'text',
                content TEXT,
                title TEXT,
                server_seq INTEGER,
                sent_at TEXT,
                stored_at TEXT NOT NULL,
                is_e2ee INTEGER DEFAULT 0,
                is_read INTEGER DEFAULT 0,
                sender_name TEXT,
                metadata TEXT,
                credential_name TEXT NOT NULL DEFAULT '',
                PRIMARY KEY (msg_id, owner_did)
            );
            CREATE TABLE e2ee_outbox (
                outbox_id TEXT PRIMARY KEY,
                owner_did TEXT NOT NULL DEFAULT '',
                peer_did TEXT NOT NULL,
                session_id TEXT,
                original_type TEXT NOT NULL DEFAULT 'text',
                plaintext TEXT NOT NULL,
                local_status TEXT NOT NULL DEFAULT 'queued',
                attempt_count INTEGER NOT NULL DEFAULT 0,
                sent_msg_id TEXT,
                sent_server_seq INTEGER,
                last_error_code TEXT,
                retry_hint TEXT,
                failed_msg_id TEXT,
                failed_server_seq INTEGER,
                metadata TEXT,
                last_attempt_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                credential_name TEXT NOT NULL DEFAULT ''
            );
            PRAGMA user_version = 6;
        """)
        conn.execute(
            """
            INSERT INTO contacts
            (owner_did, did, name, relationship, first_seen_at, last_seen_at)
            VALUES
            ('did:owner', 'did:peer', 'Peer', 'following',
             '2026-03-10T00:00:00+00:00', '2026-03-10T00:00:00+00:00')
            """
        )
        conn.commit()

        local_store.ensure_schema(conn)

        version = conn.execute("PRAGMA user_version").fetchone()[0]
        contact_columns = {
            row[1] for row in conn.execute("PRAGMA table_info(contacts)").fetchall()
        }
        indexes = _schema_object_names(conn, "index")
        migrated_contact = conn.execute(
            """
            SELECT owner_did, did, source_group_id, recommended_reason, followed, messaged, note
            FROM contacts
            WHERE owner_did = 'did:owner' AND did = 'did:peer'
            """
        ).fetchone()
        conn.close()

        assert version == local_store._SCHEMA_VERSION
        assert "source_group_id" in contact_columns
        assert "recommended_reason" in contact_columns
        assert "followed" in contact_columns
        assert "messaged" in contact_columns
        assert "note" in contact_columns
        assert "idx_contacts_owner_source_group" in indexes
        assert migrated_contact["owner_did"] == "did:owner"
        assert migrated_contact["did"] == "did:peer"
        assert migrated_contact["source_group_id"] is None
        assert migrated_contact["recommended_reason"] is None
        assert migrated_contact["followed"] == 0
        assert migrated_contact["messaged"] == 0
        assert migrated_contact["note"] is None

    def test_rebind_owner_did_moves_messages_without_duplicate_conflicts(self, db):
        local_store.store_message(
            db,
            msg_id="m1",
            owner_did="did:old",
            thread_id="dm:a:b",
            direction=0,
            sender_did="did:b",
            content="old",
        )
        local_store.store_message(
            db,
            msg_id="m1",
            owner_did="did:new",
            thread_id="dm:a:b",
            direction=0,
            sender_did="did:b",
            content="new",
        )
        summary = local_store.rebind_owner_did(
            db,
            old_owner_did="did:old",
            new_owner_did="did:new",
        )
        count = db.execute(
            "SELECT COUNT(*) FROM messages WHERE msg_id='m1'"
        ).fetchone()[0]
        assert summary["messages"] == 1
        assert count == 1
