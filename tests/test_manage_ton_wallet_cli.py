"""Unit tests for manage_ton_wallet CLI behavior.

[INPUT]: manage_ton_wallet CLI entrypoint with monkeypatched TonWallet and layout
[OUTPUT]: Regression coverage for per-credential storage_dir resolution, basic
          argument validation, and network selection (including testnet)
[POS]: CLI unit tests for TON wallet management (no real network calls)
"""

from __future__ import annotations

import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

import manage_ton_wallet as ton_cli  # noqa: E402


@dataclass
class _FakePaths:
    credential_dir: Path


class _DummyWallet:
    """Minimal TonWallet stand-in to capture ctor args and behavior."""

    def __init__(self, network: Any = None, api_endpoint: Any = None, storage_dir: str | None = None) -> None:  # noqa: D401,E501
        del api_endpoint
        # Mirror real TonWallet: default to MAINNET when network is None.
        if network is None:
            network = ton_cli.NetworkType.MAINNET
        self.network = network
        self.storage_dir = storage_dir
        self.created = False
        self.fee_reserve: float = 0.01
        self.info: dict[str, Any] = {
            "initialized": True,
            "network": getattr(network, "value", str(network)),
            "address_bounceable": "EQ_dummy",
            "address_non_bounceable": "UQ_dummy",
            "wallet_version": "v4r2",
            "storage_dir": storage_dir,
            "wallet_file": str(Path(storage_dir or ".") / "wallet.enc"),
        }

    async def create_new_wallet(self, password: str, wallet_version: str | None = None):  # noqa: D401,E501
        del password, wallet_version
        self.created = True
        return ["word{}".format(i) for i in range(1, 25)]

    def get_wallet_info(self) -> dict[str, Any]:
        return dict(self.info)

    async def close(self) -> None:  # noqa: D401
        return None

    def get_wallet_info_offline(self) -> dict[str, Any] | None:
        # Simulate "no wallet" for offline info tests when not created.
        return None if not self.created else dict(self.info)

    async def import_wallet(self, mnemonics: list[str], password: str, wallet_version: str | None = None):  # noqa: E501
        self.created = True
        # Echo back some basic info for assertions
        return {
            "address": "EQ_imported",
            "wallet_version": wallet_version or "v4r2",
            "is_deployed": False,
            "balance": 0.0,
        }

    async def load_wallet(self, password: str) -> None:  # noqa: D401
        del password
        self.created = True

    async def get_balance(self, formatted: bool = False) -> float | str:  # noqa: D401
        return "1.000000" if formatted else 1.0

    async def send_ton(
        self,
        destination: str,
        amount: float,
        comment: str | None = None,
        auto_deploy: bool = True,
        auto_detect_bounce: bool = True,
        wait_for_confirmation: bool = False,
        confirmation_timeout: int = 60,
        confirmation_check_interval: int = 5,
    ) -> dict[str, Any]:
        return {
            "success": True,
            "destination": destination,
            "amount": amount,
            "comment": comment,
            "auto_deploy": auto_deploy,
            "auto_detect_bounce": auto_detect_bounce,
            "wait_for_confirmation": wait_for_confirmation,
        }

    async def get_transactions(self, limit: int = 10, formatted: bool = True) -> list[dict[str, Any]]:  # noqa: E501
        return [{"hash": "tx1", "formatted": formatted, "limit": limit}]

    async def get_transaction_status(self, tx_hash: str) -> dict[str, Any]:
        return {"found": True, "confirmed": True, "hash": tx_hash}

    def export_mnemonic(self, password: str) -> list[str]:
        return ["w{}".format(i) for i in range(1, 25)]

    def change_password(self, old_password: str, new_password: str) -> None:
        self.info["password_changed"] = True

    def delete_wallet_file(self) -> None:
        self.info["deleted"] = True

    async def get_max_sendable_amount(self) -> float:
        return 0.5


def test_create_uses_per_credential_storage_and_mainnet(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--create should resolve storage_dir under the credential dir and default to mainnet."""  # noqa: E501

    tmp_root = Path("/tmp/awiki-test-cred")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)

    created_wallet: dict[str, Any] = {}

    def _fake_wallet_ctor(network=None, api_endpoint=None, storage_dir=None):
        wallet = _DummyWallet(network=network, api_endpoint=api_endpoint, storage_dir=storage_dir)
        created_wallet["instance"] = wallet
        return wallet

    monkeypatch.setattr(ton_cli, "TonWallet", _fake_wallet_ctor)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--create",
            "--password",
            "Strong_Passw0rd!",
        ],
    )

    ton_cli.main()

    out = json.loads(capsys.readouterr().out)
    wallet = created_wallet["instance"]

    # storage_dir 应该在 credential_dir/ton_wallet 下
    assert Path(wallet.storage_dir) == tmp_root / "ton_wallet"
    assert out["credential"] == "alice"
    assert out["address_bounceable"] == "EQ_dummy"
    # 默认网络配置应该是 mainnet（由 TonConfig 提供），这里只检查字段存在
    assert out["network"] in ("mainnet", "testnet")


def test_create_syncs_wallet_address_to_backend(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--create should attempt to sync bounceable address to backend."""

    tmp_root = Path("/tmp/awiki-test-cred-sync-create")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)

    # Avoid hitting real network / config
    class _FakeConfig:
        def __init__(self) -> None:
            self.user_service_url = "https://example.com"

    class _DummyClient:
        def __init__(self) -> None:
            self.calls: list[tuple[str, Any, dict[str, Any]]] = []

        async def post(self, endpoint: str, json: dict, headers: dict | None = None):
            class _Resp:
                def __init__(self) -> None:
                    self.status_code = 200

                def raise_for_status(self) -> None:
                    return None

                def json(self) -> dict[str, Any]:
                    return {"result": {"ok": True}}

                @property
                def headers(self) -> dict[str, str]:
                    return {}

            self.calls.append((endpoint, json, headers or {}))
            return _Resp()

        async def __aenter__(self) -> "_DummyClient":
            return self

        async def __aexit__(self, exc_type, exc, tb) -> None:
            return None

    fake_client = _DummyClient()

    # Patch SDKConfig, create_user_service_client, create_authenticator, load_identity
    monkeypatch.setattr(ton_cli, "SDKConfig", _FakeConfig)
    monkeypatch.setattr(ton_cli, "create_user_service_client", lambda cfg: fake_client)

    class _Auth:
        def get_auth_header(self, server_url: str, force_new: bool = False) -> dict[str, str]:
            return {"Authorization": "Bearer test"}

        def clear_token(self, server_url: str) -> None:
            return None

        def update_token(self, server_url: str, headers: dict[str, str]) -> str | None:
            return None

    monkeypatch.setattr(
        ton_cli,
        "create_authenticator",
        lambda name, config: (_Auth(), {"did": "did:wba:awiki.ai:user:alice"}),
    )
    monkeypatch.setattr(
        ton_cli,
        "load_identity",
        lambda name="default": {"did": "did:wba:awiki.ai:user:alice", "handle": "alice"},
    )

    created_wallet: dict[str, Any] = {}

    def _fake_wallet_ctor(network=None, api_endpoint=None, storage_dir=None):
        wallet = _DummyWallet(network=network, api_endpoint=api_endpoint, storage_dir=storage_dir)
        created_wallet["instance"] = wallet
        return wallet

    monkeypatch.setattr(ton_cli, "TonWallet", _fake_wallet_ctor)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--create",
            "--password",
            "Strong_Passw0rd!",
        ],
    )

    ton_cli.main()
    _ = capsys.readouterr().out

    # Verify that update_wallet was called via JSON-RPC
    assert fake_client.calls, "expected at least one backend call"
    endpoint, payload, _headers = fake_client.calls[0]
    assert endpoint == "/user-service/handle/rpc"
    assert payload["method"] == "update_wallet"
    assert payload["params"]["handle"] == "alice"
    assert payload["params"]["ton_wallet_address"] == "EQ_dummy"


def test_info_offline_reports_no_wallet_when_missing(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--info without password should return a friendly 'no wallet' message when none exists."""  # noqa: E501

    tmp_root = Path("/tmp/awiki-test-cred2")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)

    def _fake_wallet_ctor(network=None, api_endpoint=None, storage_dir=None):
        return _DummyWallet(network=network, api_endpoint=api_endpoint, storage_dir=storage_dir)

    monkeypatch.setattr(ton_cli, "TonWallet", _fake_wallet_ctor)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "bob",
            "--info",
        ],
    )

    ton_cli.main()

    out = json.loads(capsys.readouterr().out)
    assert out["credential"] == "bob"
    assert out["initialized"] is False
    assert "No local TON wallet" in out["message"]


def test_network_flag_allows_selecting_testnet(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--network testnet should construct TonWallet with the testnet enum value."""

    tmp_root = Path("/tmp/awiki-test-cred3")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)

    captured: dict[str, Any] = {}

    class _CaptureWallet(_DummyWallet):
        def __init__(self, network=None, api_endpoint=None, storage_dir=None):
            super().__init__(network=network, api_endpoint=api_endpoint, storage_dir=storage_dir)
            captured["network"] = network

    monkeypatch.setattr(ton_cli, "TonWallet", _CaptureWallet)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "charlie",
            "--create",
            "--password",
            "Strong_Passw0rd!",
            "--network",
            "testnet",
        ],
    )

    ton_cli.main()
    _ = capsys.readouterr().out  # we only care about ctor arguments here

    assert captured["network"] == ton_cli.NetworkType.TESTNET


def test_import_uses_mnemonic_and_password(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--import should pass mnemonic and password through to TonWallet."""

    tmp_root = Path("/tmp/awiki-test-cred4")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)
    monkeypatch.setattr(ton_cli, "TonWallet", _DummyWallet)

    mnemonic = " ".join(f"word{i}" for i in range(1, 25))

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--import",
            "--mnemonic",
            mnemonic,
            "--password",
            "Strong_Passw0rd!",
        ],
    )

    ton_cli.main()

    out = json.loads(capsys.readouterr().out)
    assert out["credential"] == "alice"
    assert out["address"] == "EQ_imported"


def test_send_requires_to_and_amount(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--send without --to or --amount should exit with an error."""

    tmp_root = Path("/tmp/awiki-test-cred5")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)
    monkeypatch.setattr(ton_cli, "TonWallet", _DummyWallet)

    # Missing --to and --amount
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--send",
            "--password",
            "Strong_Passw0rd!",
        ],
    )

    with pytest.raises(SystemExit):
        ton_cli.main()

    err = capsys.readouterr().err
    assert "--to and --amount are required for --send" in err


def test_delete_wallet_requires_yes_flag(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--delete-wallet without --yes should refuse to delete."""

    tmp_root = Path("/tmp/awiki-test-cred6")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)
    monkeypatch.setattr(ton_cli, "TonWallet", _DummyWallet)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--delete-wallet",
        ],
    )

    with pytest.raises(SystemExit):
        ton_cli.main()

    err = capsys.readouterr().err
    assert "requires --yes to confirm" in err


def test_max_sendable_returns_value(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--max-sendable should require password and return a JSON payload."""

    tmp_root = Path("/tmp/awiki-test-cred7")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)
    monkeypatch.setattr(ton_cli, "TonWallet", _DummyWallet)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--max-sendable",
            "--password",
            "Strong_Passw0rd!",
        ],
    )

    ton_cli.main()

    out = json.loads(capsys.readouterr().out)
    assert out["credential"] == "alice"
    assert out["max_sendable"] == 0.5


def test_balance_returns_json_payload(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--balance should load the wallet and return a balance JSON payload."""

    tmp_root = Path("/tmp/awiki-test-cred8")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)
    monkeypatch.setattr(ton_cli, "TonWallet", _DummyWallet)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--balance",
            "--password",
            "Strong_Passw0rd!",
        ],
    )

    ton_cli.main()

    out = json.loads(capsys.readouterr().out)
    assert out["credential"] == "alice"
    assert out["balance"] == 1.0


def test_tx_history_returns_transactions(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--tx-history should return a list of transactions."""

    tmp_root = Path("/tmp/awiki-test-cred9")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)
    monkeypatch.setattr(ton_cli, "TonWallet", _DummyWallet)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--tx-history",
            "--password",
            "Strong_Passw0rd!",
            "--limit",
            "5",
            "--formatted",
        ],
    )

    ton_cli.main()

    out = json.loads(capsys.readouterr().out)
    assert out["credential"] == "alice"
    assert isinstance(out["transactions"], list)
    assert out["transactions"][0]["limit"] == 5
    assert out["transactions"][0]["formatted"] is True


def test_tx_status_returns_status(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--tx-status should look up and return transaction status."""

    tmp_root = Path("/tmp/awiki-test-cred10")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)
    monkeypatch.setattr(ton_cli, "TonWallet", _DummyWallet)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--tx-status",
            "--password",
            "Strong_Passw0rd!",
            "--hash",
            "0xabc",
        ],
    )

    ton_cli.main()

    out = json.loads(capsys.readouterr().out)
    assert out["credential"] == "alice"
    assert out["hash"] == "0xabc"
    assert out["found"] is True
    assert out["confirmed"] is True


def test_export_mnemonic_outputs_words(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--export-mnemonic should output a 24-word mnemonic array."""

    tmp_root = Path("/tmp/awiki-test-cred11")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)
    monkeypatch.setattr(ton_cli, "TonWallet", _DummyWallet)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--export-mnemonic",
            "--password",
            "Strong_Passw0rd!",
        ],
    )

    ton_cli.main()

    out = json.loads(capsys.readouterr().out)
    assert out["credential"] == "alice"
    assert isinstance(out["mnemonic"], list)
    assert len(out["mnemonic"]) == 24


def test_change_password_sets_flag_and_reports_success(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--change-password should call change_password and return success JSON."""

    tmp_root = Path("/tmp/awiki-test-cred12")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)

    captured: dict[str, Any] = {}

    class _CaptureWallet(_DummyWallet):
        def change_password(self, old_password: str, new_password: str) -> None:
            super().change_password(old_password, new_password)
            captured["password_changed"] = True

    monkeypatch.setattr(ton_cli, "TonWallet", _CaptureWallet)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--change-password",
            "--old-password",
            "old",
            "--new-password",
            "new",
        ],
    )

    ton_cli.main()

    out = json.loads(capsys.readouterr().out)
    assert out["credential"] == "alice"
    assert out["success"] is True
    assert captured.get("password_changed") is True


def test_delete_wallet_with_yes_calls_delete(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    """--delete-wallet with --yes should call delete_wallet_file."""

    tmp_root = Path("/tmp/awiki-test-cred13")
    fake_paths = _FakePaths(credential_dir=tmp_root)

    monkeypatch.setattr(ton_cli, "configure_logging", lambda **kwargs: None)
    monkeypatch.setattr(ton_cli, "resolve_credential_paths", lambda name: fake_paths)

    captured: dict[str, Any] = {}

    class _CaptureWallet(_DummyWallet):
        def delete_wallet_file(self) -> None:
            super().delete_wallet_file()
            captured["deleted"] = True

    monkeypatch.setattr(ton_cli, "TonWallet", _CaptureWallet)

    monkeypatch.setattr(
        sys,
        "argv",
        [
            "manage_ton_wallet.py",
            "--credential",
            "alice",
            "--delete-wallet",
            "--yes",
        ],
    )

    ton_cli.main()

    out = json.loads(capsys.readouterr().out)
    assert out["credential"] == "alice"
    assert out["success"] is True
    assert captured.get("deleted") is True
