"""Test fixtures.

Every test runs against a throwaway SQLite file and saved real responses.
respx is installed and asserted on, so an accidental live call fails the suite
rather than silently hitting RIT from CI.
"""

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import db, settings  # noqa: E402
from app.config import load_config  # noqa: E402
from app.config.static import set_config  # noqa: E402

FIXTURES = Path(__file__).parent / "fixtures"


def fixture_text(name: str) -> str:
    return (FIXTURES / name).read_text(encoding="utf-8")


def fixture_bytes(name: str) -> bytes:
    return (FIXTURES / name).read_bytes()


def fixture_json(name: str) -> dict:
    return json.loads(fixture_text(name))


@pytest.fixture
def temp_db(tmp_path, monkeypatch):
    """A migrated, empty database scoped to one test."""
    monkeypatch.setattr(settings, "DB_PATH", tmp_path / "test.db")
    db.reset_for_tests(tmp_path / "test.db")
    db.migrate()
    yield
    db.reset_for_tests(tmp_path / "test.db")


@pytest.fixture
def config():
    cfg = load_config()
    set_config(cfg)
    yield cfg
    set_config(None)


@pytest.fixture
def block_network(respx_mock):
    """Any unmocked outbound request raises, which is the point."""
    return respx_mock
