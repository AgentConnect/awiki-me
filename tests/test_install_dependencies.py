"""Tests for install_dependencies post-install database upgrade behavior.

[INPUT]: install_dependencies helpers with monkeypatched dependency install and
         database upgrade results
[OUTPUT]: Regression coverage for post-install local database upgrade checks
[POS]: Unit tests for the root install script

[PROTOCOL]:
1. Update this header when logic changes
2. Check the containing folder's CLAUDE.md after updates
"""

from __future__ import annotations

import importlib.util
from pathlib import Path
import sys


_MODULE_PATH = Path(__file__).resolve().parent.parent / "install_dependencies.py"
_SPEC = importlib.util.spec_from_file_location("install_dependencies", _MODULE_PATH)
assert _SPEC is not None
assert _SPEC.loader is not None
install_dependencies = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(install_dependencies)


def test_find_installer_prefers_current_python_pip(
    monkeypatch,
) -> None:
    """Installer selection should prefer the current interpreter's pip."""
    monkeypatch.setattr(
        install_dependencies.importlib.util,
        "find_spec",
        lambda name: object() if name == "pip" else None,
    )
    monkeypatch.setattr(install_dependencies.shutil, "which", lambda name: "/usr/bin/pip")

    installer_name, cmd = install_dependencies.find_installer()

    assert installer_name == "current-python-pip"
    assert cmd[:3] == [sys.executable, "-m", "pip"]


def test_find_installer_falls_back_to_system_pip_when_current_python_cannot_provide_pip(
    monkeypatch,
) -> None:
    """A bare pip is only used when the current interpreter lacks both pip and ensurepip."""
    monkeypatch.setattr(
        install_dependencies.importlib.util,
        "find_spec",
        lambda name: None,
    )
    monkeypatch.setattr(install_dependencies.shutil, "which", lambda name: "/usr/bin/pip")

    installer_name, cmd = install_dependencies.find_installer()

    assert installer_name == "pip"
    assert cmd[0] == "pip"


def test_main_runs_database_upgrade_after_successful_install(
    monkeypatch,
    capsys,
) -> None:
    """Successful installs should always run the local database upgrade check."""
    monkeypatch.setattr(
        install_dependencies,
        "find_installer",
        lambda: ("pip", ["pip", "install", "-r", "requirements.txt"]),
    )
    monkeypatch.setattr(install_dependencies, "run_command", lambda cmd: True)

    called = {"upgrade": False}

    def _fake_upgrade():
        called["upgrade"] = True
        return True, {
            "status": "migrated",
            "db_path": "/tmp/awiki.db",
            "before_version": 8,
            "after_version": 10,
            "backup_path": "/tmp/awiki-backup.db",
        }

    monkeypatch.setattr(
        install_dependencies,
        "run_local_database_upgrade",
        _fake_upgrade,
    )

    assert install_dependencies.main() == 0
    assert called["upgrade"] is True
    output = capsys.readouterr().out
    assert "Dependencies installed successfully!" in output


def test_main_bootstraps_current_python_pip_when_missing(
    monkeypatch,
    capsys,
) -> None:
    """Install should bootstrap pip for the current interpreter before installing."""
    monkeypatch.setattr(
        install_dependencies,
        "find_installer",
        lambda: ("current-python-pip", [sys.executable, "-m", "pip", "install", "-r", "requirements.txt"]),
    )

    def _fake_find_spec(name: str):
        if name == "pip":
            return None
        if name == "ensurepip":
            return object()
        return None

    monkeypatch.setattr(
        install_dependencies.importlib.util,
        "find_spec",
        _fake_find_spec,
    )

    commands: list[list[str]] = []

    def _fake_run_command(cmd):
        commands.append(cmd)
        return True

    monkeypatch.setattr(install_dependencies, "run_command", _fake_run_command)
    monkeypatch.setattr(
        install_dependencies,
        "run_local_database_upgrade",
        lambda: (True, {"status": "ready"}),
    )

    assert install_dependencies.main() == 0
    assert commands[0] == [sys.executable, "-m", "ensurepip", "--upgrade"]
    assert commands[1][:3] == [sys.executable, "-m", "pip"]
    output = capsys.readouterr().out
    assert "Bootstrapping with ensurepip" in output


def test_main_fails_when_database_upgrade_check_fails(
    monkeypatch,
    capsys,
) -> None:
    """Install should fail loudly when the post-install database upgrade check fails."""
    monkeypatch.setattr(
        install_dependencies,
        "find_installer",
        lambda: ("pip", ["pip", "install", "-r", "requirements.txt"]),
    )
    monkeypatch.setattr(install_dependencies, "run_command", lambda cmd: True)
    monkeypatch.setattr(
        install_dependencies,
        "run_local_database_upgrade",
        lambda: (False, None),
    )

    assert install_dependencies.main() == 1
    output = capsys.readouterr().out
    assert "local database upgrade check failed" in output
    assert "python scripts/migrate_local_database.py" in output
