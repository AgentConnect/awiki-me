"""Unit tests for search_users module.

[INPUT]: search_users module, mock credential_store, mock authenticated_rpc_call
[OUTPUT]: Verification of parameter construction, error handling, and JSON output
[POS]: User search CLI unit tests

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

_scripts_dir = Path(__file__).resolve().parent.parent / "scripts"
sys.path.insert(0, str(_scripts_dir))

import search_users  # noqa: E402


class TestSearchUsersParams:
    """Verify search parameter construction and CLI behavior."""

    @pytest.mark.asyncio
    async def test_search_builds_correct_params(self, tmp_path: Path) -> None:
        """search_users() should call authenticated_rpc_call with type=keyword."""
        captured_params: dict = {}

        async def mock_rpc(client, endpoint, method, params=None, **kwargs):
            captured_params.update({
                "endpoint": endpoint,
                "method": method,
                "params": params,
            })
            return {"results": [], "total": 0}

        mock_auth = MagicMock()
        mock_client = AsyncMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with (
            patch("search_users.create_authenticator", return_value=(mock_auth, None)),
            patch("search_users.create_user_service_client", return_value=mock_client),
            patch("search_users.authenticated_rpc_call", side_effect=mock_rpc),
        ):
            await search_users.search_users("alice", "default")

        assert captured_params["endpoint"] == "/search/rpc"
        assert captured_params["method"] == "search.users"
        assert captured_params["params"] == {"type": "keyword", "q": "alice"}

    def test_missing_credential_exits(self) -> None:
        """Should exit with code 1 when credential is unavailable."""
        with (
            patch("search_users.create_authenticator", return_value=None),
            pytest.raises(SystemExit) as exc_info,
        ):
            import asyncio
            asyncio.run(search_users.search_users("test", "nonexistent"))

        assert exc_info.value.code == 1

    @pytest.mark.asyncio
    async def test_output_is_valid_json(self, capsys: pytest.CaptureFixture) -> None:
        """Output should be valid formatted JSON."""
        mock_result = {
            "results": [
                {
                    "did": "did:wba:awiki.ai:user:abc123",
                    "user_name": "Alice",
                    "nick_name": "Alice",
                    "match_score": 8.5,
                }
            ],
            "total": 1,
        }

        mock_auth = MagicMock()
        mock_client = AsyncMock()
        mock_client.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client.__aexit__ = AsyncMock(return_value=False)

        with (
            patch("search_users.create_authenticator", return_value=(mock_auth, None)),
            patch("search_users.create_user_service_client", return_value=mock_client),
            patch("search_users.authenticated_rpc_call", return_value=mock_result),
        ):
            await search_users.search_users("alice", "default")

        captured = capsys.readouterr()
        parsed = json.loads(captured.out)
        assert parsed["total"] == 1
        assert len(parsed["results"]) == 1
        assert parsed["results"][0]["user_name"] == "Alice"
