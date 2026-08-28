"""Static config is load bearing, so it is validated like real data."""

import json

import pytest

from app.config import ConfigError, load_config, staleness_report
from app.config.static import set_config


def test_real_config_validates():
    config = load_config()
    assert config.post_offices.offices
    assert config.residence_halls.halls
    assert config.shed.spaces


def test_every_hall_points_at_a_real_post_office():
    config = load_config()
    known = {o.id for o in config.post_offices.offices}
    assert all(h.post_office in known for h in config.residence_halls.halls)


def test_mailing_address_format():
    config = load_config()
    hall = config.hall("global-village")
    lines = hall.mailing_address("Cole")
    assert lines[0] == "Cole"
    assert "14623" in lines[-1]


def _write(tmp_path, halls=None, offices=None, shed=None):
    (tmp_path / "post_offices.json").write_text(json.dumps(offices or {
        "last_verified": "2026-08-28",
        "offices": [{"id": "gv", "name": "GV", "building": "GV", "hours": []}],
    }))
    (tmp_path / "shed_hours.json").write_text(json.dumps(shed or {
        "last_verified": "2026-08-28", "spaces": [],
    }))
    (tmp_path / "residence_halls.json").write_text(json.dumps(halls or {
        "last_verified": "2026-08-28", "halls": [],
    }))
    return tmp_path


def test_dangling_post_office_reference_is_fatal(tmp_path):
    _write(tmp_path, halls={
        "last_verified": "2026-08-28",
        "halls": [{
            "id": "x", "name": "X", "area": "A", "post_office": "does-not-exist",
            "street": "1 Road", "city": "Rochester", "state": "NY", "zip": "14623",
        }],
    })
    with pytest.raises(ConfigError, match="unknown post_office"):
        load_config(tmp_path)


def test_bad_weekday_is_fatal(tmp_path):
    _write(tmp_path, offices={
        "last_verified": "2026-08-28",
        "offices": [{
            "id": "gv", "name": "GV", "building": "GV",
            "hours": [{"days": ["FUNDAY"], "opens_at": "08:00", "closes_at": "17:00"}],
        }],
    })
    with pytest.raises(ConfigError, match="unknown weekday"):
        load_config(tmp_path)


def test_bad_time_format_is_fatal(tmp_path):
    _write(tmp_path, offices={
        "last_verified": "2026-08-28",
        "offices": [{
            "id": "gv", "name": "GV", "building": "GV",
            "hours": [{"days": ["MONDAY"], "opens_at": "8am", "closes_at": "17:00"}],
        }],
    })
    with pytest.raises(ConfigError, match="expected HH:MM"):
        load_config(tmp_path)


def test_unknown_field_is_fatal(tmp_path):
    """extra=forbid, so a typo in a key crashes rather than being ignored."""
    _write(tmp_path, offices={
        "last_verified": "2026-08-28",
        "offices": [{
            "id": "gv", "name": "GV", "building": "GV", "hours": [],
            "emial": "typo@rit.edu",
        }],
    })
    with pytest.raises(ConfigError):
        load_config(tmp_path)


def test_duplicate_ids_are_fatal(tmp_path):
    _write(tmp_path, offices={
        "last_verified": "2026-08-28",
        "offices": [
            {"id": "gv", "name": "GV", "building": "GV", "hours": []},
            {"id": "gv", "name": "GV again", "building": "GV", "hours": []},
        ],
    })
    with pytest.raises(ConfigError, match="duplicate post office"):
        load_config(tmp_path)


def test_missing_file_is_fatal(tmp_path):
    with pytest.raises(ConfigError, match="missing"):
        load_config(tmp_path)


def test_unverified_entries_are_reported_stale(config):
    """Residence hall addresses ship unverified on purpose, so they must show up."""
    stale = staleness_report()
    halls = [entry for entry in stale if entry["kind"] == "residence_hall"]
    assert halls, "unverified residence halls must surface in /health/sources"
    assert all(entry["reason"] == "never verified" for entry in halls)


def test_old_entries_are_reported_stale(config):
    from datetime import date
    stale = staleness_report(today=date(2030, 1, 1))
    kinds = {entry["kind"] for entry in stale}
    assert "post_office" in kinds
    assert "makerspace" in kinds
