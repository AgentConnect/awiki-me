"""SDK configuration.

[INPUT]: Environment variables, settings.json file, openclaw.json
[OUTPUT]: SDKConfig dataclass with credentials_dir, data_dir and load() classmethod;
          resolve_openclaw_gateway_port() for dynamic port resolution
[POS]: Centralized management of service URLs, domain configuration, credential directory, data directory,
       and OpenClaw Gateway port resolution

[PROTOCOL]:
1. Update this header when logic changes
2. Check the folder's CLAUDE.md after updates
"""

from __future__ import annotations

import json
import logging
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import ClassVar

# Skill name used for path construction
_SKILL_NAME = "awiki-agent-id-message"

# SKILL_DIR: project root (two levels up from utils/config.py)
_SKILL_DIR = Path(__file__).resolve().parent.parent.parent


def _default_credentials_dir() -> Path:
    """Resolve credentials directory: ~/.openclaw/credentials/<skill>/."""
    return Path.home() / ".openclaw" / "credentials" / _SKILL_NAME


def _default_data_dir() -> Path:
    """Resolve data directory.

    Priority:
      1. AWIKI_DATA_DIR env (direct full path override)
      2. AWIKI_WORKSPACE env / data / <skill>
      3. ~/.openclaw/workspace / data / <skill>
    """
    env_data = os.environ.get("AWIKI_DATA_DIR")
    if env_data:
        return Path(env_data)

    workspace = os.environ.get("AWIKI_WORKSPACE")
    if workspace:
        return Path(workspace) / "data" / _SKILL_NAME

    return Path.home() / ".openclaw" / "workspace" / "data" / _SKILL_NAME


@dataclass(frozen=True, slots=True)
class SDKConfig:
    """awiki system service configuration."""

    __test__: ClassVar[bool] = False

    user_service_url: str = field(
        default_factory=lambda: os.environ.get(
            "E2E_USER_SERVICE_URL", "https://awiki.ai"
        )
    )
    molt_message_url: str = field(
        default_factory=lambda: os.environ.get(
            "E2E_MOLT_MESSAGE_URL", "https://awiki.ai"
        )
    )
    molt_message_ws_url: str | None = field(
        default_factory=lambda: os.environ.get("E2E_MOLT_MESSAGE_WS_URL")
    )
    did_domain: str = field(
        default_factory=lambda: os.environ.get("E2E_DID_DOMAIN", "awiki.ai")
    )
    credentials_dir: Path = field(default_factory=_default_credentials_dir)
    data_dir: Path = field(default_factory=_default_data_dir)

    @classmethod
    def load(cls) -> SDKConfig:
        """Load config from <DATA_DIR>/config/settings.json with env var overrides.

        Priority: environment variables > settings.json > defaults.
        """
        credentials_dir = _default_credentials_dir()
        data_dir = _default_data_dir()
        settings_path = data_dir / "config" / "settings.json"

        file_data: dict = {}
        if settings_path.exists():
            file_data = json.loads(settings_path.read_text(encoding="utf-8"))

        return cls(
            user_service_url=os.environ.get(
                "E2E_USER_SERVICE_URL",
                file_data.get("user_service_url", "https://awiki.ai"),
            ),
            molt_message_url=os.environ.get(
                "E2E_MOLT_MESSAGE_URL",
                file_data.get("molt_message_url", "https://awiki.ai"),
            ),
            molt_message_ws_url=os.environ.get(
                "E2E_MOLT_MESSAGE_WS_URL",
                file_data.get("molt_message_ws_url"),
            ),
            did_domain=os.environ.get(
                "E2E_DID_DOMAIN",
                file_data.get("did_domain", "awiki.ai"),
            ),
            credentials_dir=credentials_dir,
            data_dir=data_dir,
        )


__all__ = ["SDKConfig", "resolve_openclaw_gateway_port"]


_logger = logging.getLogger(__name__)

# OpenClaw Gateway default port
_DEFAULT_GATEWAY_PORT = 18789


def _openclaw_config_path() -> Path:
    """Return the path to OpenClaw's config file."""
    env = os.environ.get("OPENCLAW_CONFIG_PATH")
    if env:
        return Path(env)
    return Path.home() / ".openclaw" / "openclaw.json"


def resolve_openclaw_gateway_port(default: int = _DEFAULT_GATEWAY_PORT) -> int:
    """Resolve the OpenClaw Gateway port.

    Priority: OPENCLAW_GATEWAY_PORT env > gateway.port in openclaw.json > default (18789).
    """
    # 1. Environment variable (highest priority we can read)
    env_port = os.environ.get("OPENCLAW_GATEWAY_PORT")
    if env_port:
        try:
            return int(env_port)
        except ValueError:
            _logger.warning("Invalid OPENCLAW_GATEWAY_PORT=%r, ignoring", env_port)

    # 2. Read from openclaw.json
    config_path = _openclaw_config_path()
    if config_path.exists():
        try:
            data = json.loads(config_path.read_text(encoding="utf-8"))
            gateway = data.get("gateway", {})
            if isinstance(gateway, dict) and "port" in gateway:
                return int(gateway["port"])
        except (json.JSONDecodeError, OSError, ValueError, TypeError) as exc:
            _logger.warning("Failed to read gateway.port from %s: %s", config_path, exc)

    # 3. Default
    return default
