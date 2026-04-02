"""TON wallet configuration.

[INPUT]: SDKConfig (for data_dir), optional ton_wallet.json override
[OUTPUT]: TonConfig dataclass with network, default_fee_reserve, default_wallet_version
[POS]: Centralized configuration for TON wallet behavior, independent from awiki
       DID/messaging settings, but sharing the same <DATA_DIR>/config root.

[PROTOCOL]:
1. Update this header when TON configuration logic changes.
2. Check the folder's CLAUDE.md after updates.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import ClassVar

from .config import SDKConfig


@dataclass(frozen=True, slots=True)
class TonConfig:
    """TON wallet module configuration.

    Values come from <DATA_DIR>/config/ton_wallet.json when present,
    otherwise sane defaults are used:

      - network: "mainnet"
      - default_fee_reserve: 0.01
      - default_wallet_version: "v4r2"
    """

    __test__: ClassVar[bool] = False

    network: str = field(default="mainnet")
    default_fee_reserve: float = field(default=0.01)
    default_wallet_version: str = field(default="v4r2")

    @classmethod
    def load(cls) -> "TonConfig":
        """Load TON config from <DATA_DIR>/config/ton_wallet.json.

        Priority: JSON file when present > hard-coded defaults.
        """
        sdk_config = SDKConfig.load()
        data_dir: Path = sdk_config.data_dir
        settings_path = data_dir / "config" / "ton_wallet.json"

        if not settings_path.exists():
            # No explicit TON config; return defaults.
            return cls()

        try:
            file_data = json.loads(settings_path.read_text(encoding="utf-8"))
        except Exception:
            # On parse error, fall back to defaults.
            return cls()

        network = file_data.get("network", "mainnet")
        # Guard against unexpected values; fall back to mainnet.
        if network not in ("mainnet", "testnet"):
            network = "mainnet"

        default_fee_reserve = file_data.get("default_fee_reserve", 0.01)
        try:
            fee = float(default_fee_reserve)
        except (TypeError, ValueError):
            fee = 0.01

        default_wallet_version = file_data.get("default_wallet_version", "v4r2")

        return cls(
            network=network,
            default_fee_reserve=fee,
            default_wallet_version=default_wallet_version,
        )


__all__ = ["TonConfig"]

