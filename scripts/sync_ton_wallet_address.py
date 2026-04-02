"""Sync TON wallet address to awiki user-service.

[INPUT]: Credential name (--credential), optional handle override, TON wallet address
[OUTPUT]: JSON summary of the update_wallet RPC result
[POS]: Repair/maintenance CLI so Agents can re-upload a TON wallet address
       for a Handle if the automatic sync after wallet create/import failed.

[PROTOCOL]:
1. Update this header when logic changes.
2. Keep the interface non-interactive and parameter-driven.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from typing import Any, Optional, List

from credential_store import create_authenticator, load_identity
from utils import SDKConfig, authenticated_rpc_call, create_user_service_client
from utils.logging_config import configure_logging


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Sync a TON wallet address for a Handle back to awiki user-service"
    )
    parser.add_argument(
        "--credential",
        type=str,
        default="default",
        help="awiki credential name to use for authentication (default: default)",
    )
    parser.add_argument(
        "--handle",
        type=str,
        help="Handle local-part; if omitted, will use the handle from the credential, if any",
    )
    parser.add_argument(
        "--address",
        type=str,
        required=True,
        help="TON wallet address (bounceable)",
    )
    return parser


async def _run(args: argparse.Namespace) -> None:
    config = SDKConfig()

    identity = load_identity(args.credential)
    handle: Optional[str] = args.handle or (identity.get("handle") if identity else None)
    if not handle:
        print(
            "Error: handle is required (no handle found in credential and --handle not provided).",
            file=sys.stderr,
        )
        raise SystemExit(1)

    auth_result = create_authenticator(args.credential, config)
    if auth_result is None:
        print(
            f"Error: failed to create authenticator for credential '{args.credential}'.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    auth, _ = auth_result

    async with create_user_service_client(config) as client:
        result: dict[str, Any] = await authenticated_rpc_call(
            client,
            "/user-service/handle/rpc",
            "update_wallet",
            {
                "handle": handle,
                "ton_wallet_address": args.address,
            },
            auth=auth,
            credential_name=args.credential,
        )

    output = {
        "credential": args.credential,
        "handle": handle,
        "ton_wallet_address": result.get("ton_wallet_address", args.address),
        "ok": bool(result.get("ok", False)),
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


def main(argv: Optional[List[str]] = None) -> None:
    configure_logging(console_level=None, mirror_stdio=True)
    parser = _build_parser()
    args = parser.parse_args(argv)

    try:
        asyncio.run(_run(args))
    except Exception as e:  # noqa: BLE001
        print(f"Error: {e}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()

