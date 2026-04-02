"""Unit tests for private E2EE helper behavior.

Tests private-chat specific error mapping and inbox ordering helpers without
network access or persistent credentials.
"""

from __future__ import annotations

import sys
from pathlib import Path

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

import e2ee_messaging
import e2ee_handler
import check_inbox
import check_status
import send_message as send_message_script
from utils import e2ee as e2ee_utils


class TestDecryptErrorClassification:
    """Private decrypt errors should map to stable codes and retry hints."""

    def test_handler_classifies_session_not_found(self):
        assert e2ee_handler.E2eeHandler._classify_error(
            RuntimeError("Cannot find session for session_id=abc")
        ) == ("session_not_found", "rekey_then_resend")

    def test_cli_classifies_invalid_seq(self):
        assert e2ee_messaging._classify_decrypt_error(
            RuntimeError("Invalid seq: 8")
        ) == ("invalid_seq", "rekey_then_resend")

    def test_cli_classifies_generic_failure(self):
        assert e2ee_messaging._classify_decrypt_error(
            RuntimeError("ciphertext authentication failed")
        ) == ("decryption_failed", "resend")

    def test_cli_classifies_unsupported_version(self):
        assert e2ee_messaging._classify_decrypt_error(
            RuntimeError("unsupported_version: missing e2ee_version (required 1.1)")
        ) == ("unsupported_version", "drop")


class TestProtocolErrorClassification:
    """Protocol proof failures should map to sender-visible errors."""

    def test_protocol_classifies_proof_expired(self):
        assert e2ee_utils._classify_protocol_error(
            ValueError("e2ee_init proof verification failed: proof_expired")
        ) == ("proof_expired", "resend")

    def test_protocol_classifies_proof_from_future(self):
        assert e2ee_utils._classify_protocol_error(
            ValueError("e2ee_init proof verification failed: proof_from_future")
        ) == ("proof_from_future", "drop")

    def test_protocol_classifies_unsupported_version(self):
        assert e2ee_utils._classify_protocol_error(
            ValueError("unsupported_version: missing e2ee_version (required 1.1)")
        ) == ("unsupported_version", "drop")


class TestErrorMessageText:
    """Human-readable e2ee_error text should stay stable and consistent."""

    def test_upgrade_message_is_consistent(self):
        message = e2ee_utils.build_e2ee_error_message(
            "unsupported_version",
            required_e2ee_version="1.1",
        )
        assert "upgrade" in message.lower()
        assert "1.1" in message


class TestInboxSortKey:
    """Inbox sorting should prioritize server_seq within the sender stream."""

    def test_message_sort_key_prefers_server_seq(self):
        messages = [
            {
                "sender_did": "did:a",
                "server_seq": 9,
                "created_at": "2026-03-07T12:31:00Z",
                "type": "e2ee_msg",
            },
            {
                "sender_did": "did:a",
                "server_seq": 8,
                "created_at": "2026-03-07T12:32:00Z",
                "type": "e2ee_init",
            },
        ]

        messages.sort(key=e2ee_messaging._message_sort_key)

        assert messages[0]["server_seq"] == 8
        assert messages[1]["server_seq"] == 9

    def test_check_inbox_sort_key_tolerates_missing_timestamps(self):
        messages = [
            {
                "sender_did": "did:a",
                "server_seq": None,
                "sent_at": None,
                "created_at": None,
                "type": "e2ee_msg",
            },
            {
                "sender_did": "did:a",
                "server_seq": None,
                "sent_at": "2026-03-07T12:31:00Z",
                "created_at": None,
                "type": "e2ee_init",
            },
        ]

        messages.sort(key=check_inbox._message_sort_key)

        assert messages[0]["sent_at"] is None
        assert messages[1]["sent_at"] == "2026-03-07T12:31:00Z"

    def test_check_status_sort_key_tolerates_missing_timestamps(self):
        messages = [
            {
                "sender_did": "did:a",
                "server_seq": None,
                "sent_at": None,
                "created_at": None,
                "type": "e2ee_msg",
            },
            {
                "sender_did": "did:a",
                "server_seq": None,
                "sent_at": None,
                "created_at": "2026-03-07T12:31:00Z",
                "type": "e2ee_init",
            },
        ]

        messages.sort(key=check_status._message_sort_key)

        assert messages[0]["created_at"] is None
        assert messages[1]["created_at"] == "2026-03-07T12:31:00Z"

    def test_e2ee_messaging_sort_key_tolerates_missing_timestamps(self):
        messages = [
            {
                "sender_did": "did:a",
                "server_seq": None,
                "sent_at": None,
                "created_at": None,
                "type": "e2ee_msg",
            },
            {
                "sender_did": "did:a",
                "server_seq": None,
                "sent_at": None,
                "created_at": "2026-03-07T12:31:00Z",
                "type": "e2ee_init",
            },
        ]

        messages.sort(key=e2ee_messaging._message_sort_key)

        assert messages[0]["created_at"] is None
        assert messages[1]["created_at"] == "2026-03-07T12:31:00Z"

    def test_check_inbox_sort_key_tolerates_missing_sender_did(self):
        messages = [
            {
                "sender_did": None,
                "server_seq": None,
                "sent_at": "2026-03-10T12:00:00Z",
                "created_at": "2026-03-10T12:00:00Z",
                "type": "group_system_member_joined",
            },
            {
                "sender_did": "did:a",
                "server_seq": None,
                "sent_at": "2026-03-10T12:01:00Z",
                "created_at": "2026-03-10T12:01:00Z",
                "type": "e2ee_msg",
            },
        ]

        messages.sort(key=check_inbox._message_sort_key)

        assert messages[0]["sender_did"] is None
        assert messages[1]["sender_did"] == "did:a"

    def test_check_status_sort_key_tolerates_missing_sender_did(self):
        messages = [
            {
                "sender_did": None,
                "server_seq": None,
                "sent_at": "2026-03-10T12:00:00Z",
                "created_at": "2026-03-10T12:00:00Z",
                "type": "group_system_member_joined",
            },
            {
                "sender_did": "did:a",
                "server_seq": None,
                "sent_at": "2026-03-10T12:01:00Z",
                "created_at": "2026-03-10T12:01:00Z",
                "type": "e2ee_msg",
            },
        ]

        messages.sort(key=check_status._message_sort_key)

        assert messages[0]["sender_did"] is None
        assert messages[1]["sender_did"] == "did:a"

    def test_e2ee_messaging_sort_key_tolerates_missing_sender_did(self):
        messages = [
            {
                "sender_did": None,
                "server_seq": None,
                "sent_at": "2026-03-10T12:00:00Z",
                "created_at": "2026-03-10T12:00:00Z",
                "type": "group_system_member_joined",
            },
            {
                "sender_did": "did:a",
                "server_seq": None,
                "sent_at": "2026-03-10T12:01:00Z",
                "created_at": "2026-03-10T12:01:00Z",
                "type": "e2ee_msg",
            },
        ]

        messages.sort(key=e2ee_messaging._message_sort_key)

        assert messages[0]["sender_did"] is None
        assert messages[1]["sender_did"] == "did:a"

    def test_e2ee_messaging_sender_did_value_uses_placeholder_for_none(self):
        assert (
            e2ee_messaging._sender_did_value({"sender_did": None}) == "?"
        )
        assert (
            e2ee_messaging._sender_did_value({"sender_did": "did:a"}) == "did:a"
        )


class TestOutgoingHistoryRender:
    """Outgoing encrypted history items should be replaceable with local plaintext."""

    def test_render_outgoing_message_without_local_copy_returns_none(self):
        rendered = check_inbox._render_local_outgoing_e2ee_message(
            "default",
            {"id": "missing"},
        )
        assert rendered is None


class TestUserVisibleE2eePresentation:
    """User-facing E2EE output should stay minimal and stable."""

    def test_check_inbox_decorates_decrypted_message_with_minimal_notice(self):
        rendered = check_inbox._decorate_user_visible_e2ee_message(
            {"id": "m1", "type": "e2ee_msg", "content": "ciphertext"},
            original_type="text",
            plaintext="hello",
        )

        assert rendered["type"] == "text"
        assert rendered["content"] == "hello"
        assert rendered["_e2ee"] is True
        assert rendered["_e2ee_notice"] == "This is an encrypted message."

    def test_cli_renders_minimal_encrypted_message_text(self):
        rendered = e2ee_messaging._render_user_visible_e2ee_text("secret")

        assert "encrypted message" in rendered.lower()
        assert rendered.endswith("secret")

    def test_cli_renders_send_first_auto_init_notice(self):
        rendered = e2ee_messaging._render_auto_session_notice("did:wba:example:user:bob")

        assert "automatic init" in rendered.lower()
        assert "did:wba:example:user:bob" in rendered

    def test_check_status_hides_protocol_only_message_types(self):
        assert check_status._is_user_visible_message_type("text") is True
        assert check_status._is_user_visible_message_type("e2ee_init") is False
        assert check_status._is_user_visible_message_type("e2ee_msg") is False

    def test_check_inbox_strips_hidden_title_field(self):
        rendered = check_inbox._strip_hidden_user_fields(
            {"id": "m1", "content": "hello", "title": "secret-title"}
        )
        assert "title" not in rendered

    def test_send_message_result_strips_hidden_title_field(self):
        rendered = send_message_script._strip_hidden_result_fields(
            {"id": "m1", "title": "hidden", "content": "hello"}
        )
        assert "title" not in rendered
