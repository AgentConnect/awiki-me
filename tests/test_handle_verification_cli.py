"""Unit tests for non-interactive verification CLI flows.

[INPUT]: send_verification_code/register_handle/recover_handle/bind_contact CLI
         modules, monkeypatched async SDK calls, and CLI argv
[OUTPUT]: Regression coverage for OTP-first and activation-link-first workflows
[POS]: CLI tests for non-interactive verification behavior

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

import bind_contact as bind_cli  # noqa: E402
import recover_handle as recover_cli  # noqa: E402
import register_handle as register_cli  # noqa: E402
import send_verification_code as verification_cli  # noqa: E402
from utils.handle import EmailVerificationResult  # noqa: E402
from utils.rpc import JsonRpcError  # noqa: E402


class _AsyncClientContext:
    """Minimal async client context manager for CLI tests."""

    async def __aenter__(self) -> object:
        return object()

    async def __aexit__(self, exc_type, exc, tb) -> bool:
        del exc_type, exc, tb
        return False


class _ArgvContext:
    """Temporarily replace sys.argv for CLI entry-point tests."""

    def __init__(self, argv: list[str]):
        self._argv = argv
        self._old_argv: list[str] | None = None

    def __enter__(self) -> None:
        self._old_argv = sys.argv[:]
        sys.argv = self._argv[:]

    def __exit__(self, exc_type, exc, tb) -> bool:
        del exc_type, exc, tb
        assert self._old_argv is not None
        sys.argv = self._old_argv
        return False


def test_send_verification_code_sends_phone_otp(monkeypatch: pytest.MonkeyPatch, capsys) -> None:
    """The verification CLI should normalize phone numbers and send OTPs."""
    captured: dict[str, str] = {}

    monkeypatch.setattr(
        verification_cli,
        "create_user_service_client",
        lambda config: _AsyncClientContext(),
    )

    async def fake_send_otp(client, phone):
        del client
        captured["phone"] = phone
        return {"status": "ok"}

    monkeypatch.setattr(verification_cli, "send_otp", fake_send_otp)

    asyncio.run(verification_cli.do_send("13800138000"))

    output = capsys.readouterr().out
    assert captured["phone"] == "13800138000"
    assert "Verification code sent successfully." in output
    assert "Next step" in output



def test_register_handle_main_requires_preissued_otp(
    monkeypatch: pytest.MonkeyPatch,
    capsys,
) -> None:
    """register_handle should reject phone registration without a pre-issued OTP."""
    monkeypatch.setattr(register_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(register_cli, "create_user_service_client", lambda config: _AsyncClientContext())

    with _ArgvContext(
        [
            "register_handle.py",
            "--handle",
            "alice",
            "--phone",
            "+8613800138000",
        ]
    ):
        with pytest.raises(SystemExit) as exc_info:
            register_cli.main()

    assert exc_info.value.code == 2
    assert capsys.readouterr().err.strip() == (
        "Error: OTP code is required for phone registration."
    )



def test_recover_handle_main_requires_preissued_otp(
    monkeypatch: pytest.MonkeyPatch,
    capsys,
) -> None:
    """recover_handle should reject phone recovery without a pre-issued OTP."""
    monkeypatch.setattr(recover_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(recover_cli, "create_user_service_client", lambda config: _AsyncClientContext())

    with _ArgvContext(
        [
            "recover_handle.py",
            "--handle",
            "alice",
            "--phone",
            "+8613800138000",
        ]
    ):
        with pytest.raises(SystemExit) as exc_info:
            recover_cli.main()

    assert exc_info.value.code == 2
    assert capsys.readouterr().err.strip() == (
        "Error: OTP code is required for handle recovery."
    )


def test_register_handle_main_renders_jsonrpc_error_without_traceback(
    monkeypatch: pytest.MonkeyPatch,
    capsys,
) -> None:
    """register_handle should print only the server-side reason on failure."""
    monkeypatch.setattr(register_cli, "configure_logging", lambda **kwargs: None)

    async def fake_do_register(**kwargs) -> bool:
        del kwargs
        raise JsonRpcError(-32004, "该邮箱已注册 3 个 Handle，配额上限为 3")

    monkeypatch.setattr(register_cli, "do_register", fake_do_register)

    with _ArgvContext(
        [
            "register_handle.py",
            "--handle",
            "alice",
            "--email",
            "user@example.com",
        ]
    ):
        with pytest.raises(SystemExit) as exc_info:
            register_cli.main()

    assert exc_info.value.code == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err.strip() == "Error: 该邮箱已注册 3 个 Handle，配额上限为 3"
    assert "Traceback" not in captured.err


def test_send_verification_code_main_renders_jsonrpc_error_without_traceback(
    monkeypatch: pytest.MonkeyPatch,
    capsys,
) -> None:
    """send_verification_code should keep terminal errors concise."""
    monkeypatch.setattr(verification_cli, "configure_logging", lambda **kwargs: None)

    async def fake_do_send(phone: str) -> None:
        del phone
        raise JsonRpcError(-32010, "OTP sent too frequently")

    monkeypatch.setattr(verification_cli, "do_send", fake_do_send)

    with _ArgvContext(
        [
            "send_verification_code.py",
            "--phone",
            "+8613800138000",
        ]
    ):
        with pytest.raises(SystemExit) as exc_info:
            verification_cli.main()

    assert exc_info.value.code == 1
    captured = capsys.readouterr()
    assert captured.out == ""
    assert captured.err.strip() == "Error: OTP sent too frequently"
    assert "Traceback" not in captured.err



def test_do_register_email_returns_pending_when_verification_is_not_complete(
    monkeypatch: pytest.MonkeyPatch,
    capsys,
) -> None:
    """Email registration should return pending instead of prompting for stdin."""
    monkeypatch.setattr(register_cli, "create_user_service_client", lambda config: _AsyncClientContext())

    async def fake_ensure_email_verification(client, email, **kwargs):
        del client, email, kwargs
        return EmailVerificationResult(verified=False, activation_sent=True, verified_at=None)

    monkeypatch.setattr(register_cli, "ensure_email_verification", fake_ensure_email_verification)
    monkeypatch.setattr(
        register_cli,
        "register_handle_with_email",
        lambda **kwargs: pytest.fail(f"register_handle_with_email should not be called: {kwargs}"),
    )

    completed = asyncio.run(
        register_cli.do_register(
            handle="alice",
            email="user@example.com",
        )
    )

    assert completed is False
    assert "Email verification pending." in capsys.readouterr().out



def test_bind_contact_send_phone_otp_flow(monkeypatch: pytest.MonkeyPatch, capsys) -> None:
    """Phone binding should support an explicit send-only OTP step."""
    monkeypatch.setattr(bind_cli, "create_user_service_client", lambda config: _AsyncClientContext())
    monkeypatch.setattr(
        bind_cli,
        "load_identity",
        lambda name: {"jwt_token": "jwt-token"} if name == "default" else None,
    )
    captured: dict[str, str] = {}

    async def fake_bind_phone_send_otp(client, phone, jwt_token):
        del client
        captured["phone"] = phone
        captured["jwt_token"] = jwt_token
        return {"message": "sent"}

    monkeypatch.setattr(bind_cli, "bind_phone_send_otp", fake_bind_phone_send_otp)

    completed = asyncio.run(
        bind_cli.do_bind(
            bind_phone="+8613800138000",
            send_phone_otp=True,
            credential_name="default",
        )
    )

    output = capsys.readouterr().out
    assert completed is True
    assert captured == {"phone": "+8613800138000", "jwt_token": "jwt-token"}
    assert "OTP sent." in output
    assert "Next step" in output



def test_bind_contact_main_requires_explicit_phone_step(
    monkeypatch: pytest.MonkeyPatch,
    capsys,
) -> None:
    """Phone binding should require either --send-phone-otp or --otp-code."""
    monkeypatch.setattr(bind_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(bind_cli, "create_user_service_client", lambda config: _AsyncClientContext())
    monkeypatch.setattr(
        bind_cli,
        "load_identity",
        lambda name: {"jwt_token": "jwt-token"} if name == "default" else None,
    )

    with _ArgvContext(
        [
            "bind_contact.py",
            "--bind-phone",
            "+8613800138000",
        ]
    ):
        with pytest.raises(SystemExit) as exc_info:
            bind_cli.main()

    assert exc_info.value.code == 2
    assert capsys.readouterr().err.strip() == "Error: OTP code is required for phone binding."



def test_bind_contact_email_pending_exits_non_interactively(
    monkeypatch: pytest.MonkeyPatch,
    capsys,
) -> None:
    """Email binding should return pending instead of requesting stdin."""
    monkeypatch.setattr(bind_cli, "create_user_service_client", lambda config: _AsyncClientContext())
    monkeypatch.setattr(
        bind_cli,
        "load_identity",
        lambda name: {"jwt_token": "jwt-token"} if name == "default" else None,
    )

    async def fake_ensure_email_verification(client, email, **kwargs):
        del client, email, kwargs
        return EmailVerificationResult(verified=False, activation_sent=True, verified_at=None)

    monkeypatch.setattr(bind_cli, "ensure_email_verification", fake_ensure_email_verification)

    completed = asyncio.run(
        bind_cli.do_bind(
            bind_email="user@example.com",
            credential_name="default",
        )
    )

    assert completed is False
    assert "Email verification pending." in capsys.readouterr().out
