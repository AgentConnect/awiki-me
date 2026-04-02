"""TON wallet management entrypoint for awiki-agent-id-message.

[INPUT]: Credential name (--credential), TonConfig, TonWallet
[OUTPUT]: JSON summaries for wallet create/import/info/balance/send/tx-history/etc.
[POS]: High-level CLI wrapper used by Agents to manage per-credential TON wallets
       without exposing storage layout details.

[PROTOCOL]:
1. Update this header when CLI behavior changes.
2. Keep the interface non-interactive and parameter-driven.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path
from typing import Any, List, Optional

from credential_layout import resolve_credential_paths
from utils import (
    SDKConfig,
    authenticated_rpc_call,
    create_user_service_client,
)
from utils.logging_config import configure_logging
from ton_wallet import TonWallet, NetworkType, WalletError, NetworkError
from credential_store import create_authenticator, load_identity


def _resolve_storage_dir(credential_name: str) -> Path:
    """Resolve the per-credential TON wallet storage directory."""
    paths = resolve_credential_paths(credential_name)
    if paths is None:
        print(
            f"Credential '{credential_name}' not found. "
            "Create an identity first via setup_identity.py.",
            file=sys.stderr,
        )
        raise SystemExit(1)
    return paths.credential_dir / "ton_wallet"


def _build_wallet_from_args(args: argparse.Namespace) -> TonWallet:
    """Construct a TonWallet bound to a specific credential."""
    credential = args.credential
    storage_dir = _resolve_storage_dir(credential)

    network: Optional[NetworkType] = None
    if getattr(args, "network", None):
        network = NetworkType(args.network)

    return TonWallet(network=network, storage_dir=str(storage_dir))


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="TON wallet management (per awiki credential)")

    parser.add_argument(
        "--credential",
        type=str,
        default="default",
        help="awiki credential name to bind the wallet to (default: default)",
    )
    parser.add_argument(
        "--network",
        choices=[n.value for n in NetworkType],
        help="Override TON network (mainnet/testnet); defaults to TonConfig network",
    )

    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--create",
        action="store_true",
        help="Create a new TON wallet for this credential",
    )
    group.add_argument(
        "--import",
        dest="do_import",
        action="store_true",
        help="Import an existing TON wallet from a mnemonic",
    )
    group.add_argument(
        "--info",
        action="store_true",
        help="Show wallet info (offline or online when password is provided)",
    )
    group.add_argument(
        "--balance",
        action="store_true",
        help="Show wallet balance",
    )
    group.add_argument(
        "--send",
        action="store_true",
        help="Send TON from this wallet",
    )
    group.add_argument(
        "--tx-history",
        action="store_true",
        help="Show recent transactions",
    )
    group.add_argument(
        "--tx-status",
        action="store_true",
        help="Show status for a single transaction hash",
    )
    group.add_argument(
        "--export-mnemonic",
        action="store_true",
        help="Export the 24-word mnemonic (high risk; requires password)",
    )
    group.add_argument(
        "--change-password",
        action="store_true",
        help="Change the local encryption password for this wallet",
    )
    group.add_argument(
        "--delete-wallet",
        action="store_true",
        help="Delete the local wallet file for this credential",
    )
    group.add_argument(
        "--max-sendable",
        action="store_true",
        help="Compute the max sendable amount with current fee reserve",
    )

    # Common parameters
    parser.add_argument(
        "--password",
        type=str,
        help="Wallet password for operations that require decryption",
    )

    # Create-specific
    parser.add_argument(
        "--wallet-version",
        type=str,
        choices=["v3r2", "v4r2", "v5r1"],
        help="Wallet contract version when creating or importing",
    )

    # Import-specific
    mnemo_group = parser.add_mutually_exclusive_group()
    mnemo_group.add_argument(
        "--mnemonic",
        type=str,
        help="24 English words separated by spaces",
    )
    mnemo_group.add_argument(
        "--mnemonic-file",
        type=str,
        help="Path to a file containing the mnemonic words",
    )

    # Send-specific
    parser.add_argument(
        "--to",
        type=str,
        help="Destination address for sending TON",
    )
    parser.add_argument(
        "--amount",
        type=float,
        help="Amount to send in TON units",
    )
    parser.add_argument(
        "--comment",
        type=str,
        help="Optional transfer comment",
    )
    parser.add_argument(
        "--no-auto-deploy",
        dest="auto_deploy",
        action="store_false",
        help="Disable automatic wallet deployment before sending",
    )
    parser.set_defaults(auto_deploy=True)
    parser.add_argument(
        "--no-auto-detect-bounce",
        dest="auto_detect_bounce",
        action="store_false",
        help="Disable automatic bounceable/non-bounceable address selection",
    )
    parser.set_defaults(auto_detect_bounce=True)
    parser.add_argument(
        "--wait",
        dest="wait_for_confirmation",
        action="store_true",
        help="Wait for transaction confirmation after sending",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=60,
        help="Max seconds to wait for confirmation (default: 60)",
    )
    parser.add_argument(
        "--check-interval",
        type=int,
        default=5,
        help="Polling interval in seconds when waiting for confirmation (default: 5)",
    )

    # History / status
    parser.add_argument(
        "--limit",
        type=int,
        default=10,
        help="Number of transactions to fetch for --tx-history (default: 10)",
    )
    parser.add_argument(
        "--formatted",
        action="store_true",
        help="Return formatted balance/amount strings where applicable",
    )
    parser.add_argument(
        "--hash",
        type=str,
        help="Transaction hash (or prefix) for --tx-status",
    )

    # Delete-wallet safety confirm
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Confirm irreversible wallet deletion when using --delete-wallet",
    )

    # Change-password
    parser.add_argument(
        "--old-password",
        type=str,
        help="Current wallet password for --change-password",
    )
    parser.add_argument(
        "--new-password",
        type=str,
        help="New wallet password for --change-password",
    )

    return parser


async def _sync_wallet_to_backend(credential_name: str, ton_wallet_address: str) -> None:
    """Best-effort sync of TON wallet address to user-service Handle record.

    This helper is intentionally lenient: failures are logged to stderr but do not
    abort the CLI operation.
    """
    # Load local identity to discover handle and JWT
    identity = load_identity(credential_name)
    handle = identity.get("handle") if identity else None
    if not handle:
        print(
            f"[ton-wallet] Skipping backend sync: credential '{credential_name}' has no handle.",
            file=sys.stderr,
        )
        return

    config = SDKConfig()
    auth_result = create_authenticator(credential_name, config)
    if auth_result is None:
        print(
            f"[ton-wallet] Skipping backend sync: authenticator unavailable for credential '{credential_name}'.",
            file=sys.stderr,
        )
        return

    auth, _ = auth_result
    async with create_user_service_client(config) as client:
        try:
            await authenticated_rpc_call(
                client,
                "/user-service/handle/rpc",
                "update_wallet",
                {
                    "handle": handle,
                    "ton_wallet_address": ton_wallet_address,
                },
                auth=auth,
                credential_name=credential_name,
            )
            print(
                f"[ton-wallet] Synced TON wallet address to backend for handle '{handle}'.",
                file=sys.stderr,
            )
        except Exception as e:  # noqa: BLE001
            print(
                f"[ton-wallet] Warning: failed to sync wallet address to backend: {e}",
                file=sys.stderr,
            )


async def _run(args: argparse.Namespace) -> None:
    if args.create:
        if not args.password:
            print("Error: --password is required for --create", file=sys.stderr)
            raise SystemExit(1)
        wallet = _build_wallet_from_args(args)
        mnemonics = await wallet.create_new_wallet(
            password=args.password,
            wallet_version=args.wallet_version,
        )
        info = wallet.get_wallet_info()
        await wallet.close()
        # Sync bounceable address to backend if available
        address_bounceable = info.get("address_bounceable")
        if address_bounceable:
            await _sync_wallet_to_backend(args.credential, address_bounceable)
        result: dict[str, Any] = {
            "credential": args.credential,
            "mnemonic": mnemonics,
            "address_bounceable": info.get("address_bounceable"),
            "address_non_bounceable": info.get("address_non_bounceable"),
            "wallet_version": info.get("wallet_version"),
            "storage_dir": info.get("storage_dir"),
            "wallet_file": info.get("wallet_file"),
            "network": info.get("network"),
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if args.do_import:
        if not args.password:
            print("Error: --password is required for --import", file=sys.stderr)
            raise SystemExit(1)
        if not args.mnemonic and not args.mnemonic_file:
            print(
                "Error: either --mnemonic or --mnemonic-file is required for --import",
                file=sys.stderr,
            )
            raise SystemExit(1)

        if args.mnemonic:
            words = args.mnemonic.split()
        else:
            with open(args.mnemonic_file, "r", encoding="utf-8") as f:
                content = f.read()
            words = content.split()

        wallet = _build_wallet_from_args(args)
        info = await wallet.import_wallet(
            mnemonics=words,
            password=args.password,
            wallet_version=args.wallet_version,
        )
        await wallet.close()
        address = info.get("address")
        if address:
            await _sync_wallet_to_backend(args.credential, address)
        result = {
            "credential": args.credential,
            "address": info.get("address"),
            "wallet_version": info.get("wallet_version"),
            "is_deployed": info.get("is_deployed"),
            "balance": info.get("balance"),
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if args.info:
        wallet = _build_wallet_from_args(args)
        if args.password:
            await wallet.load_wallet(args.password)
            info = wallet.get_wallet_info()
            await wallet.close()
        else:
            info = wallet.get_wallet_info_offline()
            if info is None:
                info = {
                    "initialized": False,
                    "message": "No local TON wallet found for this credential",
                }
        info["credential"] = args.credential
        print(json.dumps(info, ensure_ascii=False, indent=2))
        return

    if args.balance:
        if not args.password:
            print("Error: --password is required for --balance", file=sys.stderr)
            raise SystemExit(1)
        wallet = _build_wallet_from_args(args)
        await wallet.load_wallet(args.password)
        balance = await wallet.get_balance(formatted=args.formatted)
        await wallet.close()
        result = {
            "credential": args.credential,
            "balance": balance,
            "formatted": args.formatted,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if args.send:
        if not args.password:
            print("Error: --password is required for --send", file=sys.stderr)
            raise SystemExit(1)
        if not args.to or args.amount is None:
            print("Error: --to and --amount are required for --send", file=sys.stderr)
            raise SystemExit(1)

        wallet = _build_wallet_from_args(args)
        await wallet.load_wallet(args.password)
        result = await wallet.send_ton(
            destination=args.to,
            amount=args.amount,
            comment=args.comment,
            auto_deploy=args.auto_deploy,
            auto_detect_bounce=args.auto_detect_bounce,
            wait_for_confirmation=args.wait_for_confirmation,
            confirmation_timeout=args.timeout,
            confirmation_check_interval=args.check_interval,
        )
        await wallet.close()
        result["credential"] = args.credential
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if args.tx_history:
        if not args.password:
            print("Error: --password is required for --tx-history", file=sys.stderr)
            raise SystemExit(1)
        wallet = _build_wallet_from_args(args)
        await wallet.load_wallet(args.password)
        txs = await wallet.get_transactions(limit=args.limit, formatted=args.formatted)
        await wallet.close()
        result = {
            "credential": args.credential,
            "transactions": txs,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if args.tx_status:
        if not args.password:
            print("Error: --password is required for --tx-status", file=sys.stderr)
            raise SystemExit(1)
        if not args.hash:
            print("Error: --hash is required for --tx-status", file=sys.stderr)
            raise SystemExit(1)
        wallet = _build_wallet_from_args(args)
        await wallet.load_wallet(args.password)
        status = await wallet.get_transaction_status(args.hash)
        await wallet.close()
        status["credential"] = args.credential
        print(json.dumps(status, ensure_ascii=False, indent=2))
        return

    if args.export_mnemonic:
        if not args.password:
            print("Error: --password is required for --export-mnemonic", file=sys.stderr)
            raise SystemExit(1)
        wallet = _build_wallet_from_args(args)
        words = wallet.export_mnemonic(args.password)
        result = {"credential": args.credential, "mnemonic": words}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if args.change_password:
        if not args.old_password or not args.new_password:
            print(
                "Error: --old-password and --new-password are required for --change-password",
                file=sys.stderr,
            )
            raise SystemExit(1)
        wallet = _build_wallet_from_args(args)
        wallet.change_password(args.old_password, args.new_password)
        result = {"credential": args.credential, "success": True, "message": "Password changed"}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if args.delete_wallet:
        if not args.yes:
            print(
                "Error: --delete-wallet requires --yes to confirm (operation is irreversible)",
                file=sys.stderr,
            )
            raise SystemExit(1)
        wallet = _build_wallet_from_args(args)
        wallet.delete_wallet_file()
        result = {"credential": args.credential, "success": True, "message": "Wallet file deleted"}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    if args.max_sendable:
        if not args.password:
            print("Error: --password is required for --max-sendable", file=sys.stderr)
            raise SystemExit(1)
        wallet = _build_wallet_from_args(args)
        await wallet.load_wallet(args.password)
        max_amount = await wallet.get_max_sendable_amount()
        await wallet.close()
        result = {
            "credential": args.credential,
            "max_sendable": max_amount,
            "fee_reserve": wallet.fee_reserve,
        }
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return

    # Should not reach here because one of the mutually exclusive flags is required.
    raise SystemExit("No operation selected")


def main(argv: Optional[List[str]] = None) -> None:
    configure_logging(console_level=None, mirror_stdio=True)
    parser = _build_parser()
    args = parser.parse_args(argv)

    try:
        asyncio.run(_run(args))
    except (WalletError, NetworkError, ValueError, FileNotFoundError) as e:
        print(f"Error: {e}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
