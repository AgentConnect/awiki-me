"""Tests for group heartbeat summaries in check_status.

[INPUT]: check_status group-watch helper, local_store SQLite fixtures, and monkeypatched status helpers
[OUTPUT]: Regression coverage for active-group heartbeat summaries and report integration
[POS]: Unit tests for group watch state exposed by check_status.py

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

import check_status  # noqa: E402
import local_store  # noqa: E402


def test_summarize_group_watch_reports_active_group_metrics(
    monkeypatch: pytest.MonkeyPatch,
    tmp_path: Path,
) -> None:
    """Group-watch summary should expose heartbeat-relevant local metrics."""
    monkeypatch.setenv("AWIKI_DATA_DIR", str(tmp_path))

    conn = local_store.get_connection()
    try:
        local_store.ensure_schema(conn)
        local_store.upsert_group(
            conn,
            owner_did="did:alice",
            group_id="grp_1",
            name="OpenClaw Meetup",
            group_mode="general",
            slug="openclaw-meetup",
            my_role="member",
            membership_status="active",
            member_count=6,
            group_owner_did="did:owner",
            group_owner_handle="owner.awiki.ai",
            last_synced_seq=12,
            last_message_at="2026-03-10T02:00:00+00:00",
            credential_name="alice",
        )
        local_store.replace_group_members(
            conn,
            owner_did="did:alice",
            group_id="grp_1",
            credential_name="alice",
            members=[
                {
                    "user_id": f"user_{index}",
                    "did": f"did:user:{index}",
                    "handle": f"user{index}.awiki.ai",
                    "profile_url": f"https://awiki.ai/profiles/user_{index}",
                    "role": "member",
                    "joined_at": f"2026-03-10T00:0{index}:00+00:00",
                    "sent_message_count": index,
                }
                for index in range(1, 6)
            ],
        )
        local_store.store_message(
            conn,
            msg_id="owner_msg_1",
            owner_did="did:alice",
            thread_id=local_store.make_thread_id("did:alice", group_id="grp_1"),
            direction=0,
            sender_did="did:owner",
            group_id="grp_1",
            content_type="group_user",
            content="Please introduce yourselves clearly.",
            server_seq=11,
            sent_at="2026-03-10T01:55:00+00:00",
            sender_name="owner.awiki.ai",
            credential_name="alice",
        )
        local_store.store_message(
            conn,
            msg_id="member_msg_1",
            owner_did="did:alice",
            thread_id=local_store.make_thread_id("did:alice", group_id="grp_1"),
            direction=0,
            sender_did="did:user:1",
            group_id="grp_1",
            content_type="group_user",
            content="I work on agent infra.",
            server_seq=12,
            sent_at="2026-03-10T02:00:00+00:00",
            sender_name="user1.awiki.ai",
            credential_name="alice",
        )
        local_store.append_relationship_event(
            conn,
            owner_did="did:alice",
            target_did="did:user:2",
            target_handle="user2.awiki.ai",
            event_type="ai_recommended",
            source_type="meetup",
            source_name="OpenClaw Meetup",
            source_group_id="grp_1",
            reason="Strong infra fit",
            status="pending",
            credential_name="alice",
        )
        local_store.upsert_contact(
            conn,
            owner_did="did:alice",
            did="did:user:3",
            handle="user3.awiki.ai",
            source_type="meetup",
            source_name="OpenClaw Meetup",
            source_group_id="grp_1",
            connected_at="2026-03-10T02:05:00+00:00",
            recommended_reason="Already saved",
        )
    finally:
        conn.close()

    summary = check_status.summarize_group_watch("did:alice")

    assert summary["status"] == "ok"
    assert summary["active_groups"] == 1
    assert summary["groups_with_pending_recommendations"] == 1
    group = summary["groups"][0]
    assert group["group_id"] == "grp_1"
    assert group["group_mode"] == "general"
    assert group["tracked_active_members"] == 5
    assert group["local_group_user_messages"] == 2
    assert group["local_owner_messages"] == 1
    assert group["latest_owner_message_at"] == "2026-03-10T01:55:00+00:00"
    assert group["pending_recommendations"] == 1
    assert group["saved_contacts"] == 1
    assert group["recommendation_signal_ready"] is True


def test_check_status_includes_group_watch_summary(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Unified status should attach group-watch data for heartbeat callers."""
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

    async def _fake_check_identity(credential_name: str) -> dict[str, object]:
        del credential_name
        return {
            "status": "ok",
            "did": "did:alice",
            "name": "Alice",
            "jwt_valid": True,
        }

    async def _fake_build_inbox_report_with_auto_e2ee(
        credential_name: str,
        listener_status: dict | None = None,
    ) -> dict[str, object]:
        del credential_name, listener_status
        return {
            "status": "ok",
            "total": 0,
            "text_messages": 0,
            "by_type": {},
            "text_by_sender": {},
            "messages": [],
        }

    monkeypatch.setattr(check_status, "check_identity", _fake_check_identity)
    monkeypatch.setattr(
        check_status,
        "_build_inbox_report_with_auto_e2ee",
        _fake_build_inbox_report_with_auto_e2ee,
    )
    monkeypatch.setattr(
        check_status,
        "summarize_group_watch",
        lambda owner_did: {
            "status": "ok",
            "active_groups": 1,
            "groups_with_pending_recommendations": 0,
            "groups": [{"group_id": "grp_1", "name": "OpenClaw Meetup"}],
        }
        if owner_did == "did:alice"
        else {"status": "no_identity", "active_groups": 0, "groups": []},
    )
    monkeypatch.setattr(
        check_status,
        "load_e2ee_client",
        lambda local_did, credential_name: SimpleNamespace(
            export_state=lambda: {"sessions": []},
        ),
    )

    async def _fake_fetch_group_messages(
        group_watch, *, owner_did, credential_name
    ):
        return {"fetched_groups": 0, "total_new_messages": 0, "errors": []}

    monkeypatch.setattr(
        check_status, "fetch_group_messages", _fake_fetch_group_messages
    )

    report = asyncio.run(check_status.check_status("alice"))

    assert report["group_watch"]["status"] == "ok"
    assert report["group_watch"]["active_groups"] == 1
    assert report["group_watch"]["groups"][0]["group_id"] == "grp_1"
