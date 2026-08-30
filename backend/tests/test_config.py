"""Static config is load bearing, so it is validated like real data."""

import json

import pytest

from app.config import ConfigError, load_config, staleness_report
from app.config.static import set_config


def test_real_config_validates():
    config = load_config()
    assert config.post_offices.offices
    assert config.housing.areas
    assert config.shed.spaces


def test_every_area_points_at_a_real_post_office():
    config = load_config()
    known = {o.id for o in config.post_offices.offices}
    assert all(a.post_office in known for a in config.housing.areas)


def test_only_two_post_offices_exist():
    """Zone based, not per hall. Two offices serve all of campus housing."""
    config = load_config()
    assert {o.id for o in config.post_offices.offices} == {"global-village", "dsp"}
    assert {o.side for o in config.post_offices.offices} == {"east", "west"}


def test_street_addresses_match_the_authoritative_page():
    config = load_config()
    streets = {o.id: o.street for o in config.post_offices.offices}
    assert streets["global-village"] == "6000 Reynolds Drive"
    assert streets["dsp"] == "43 Greenleaf Court"


def test_lomb_memorial_drive_is_never_used():
    """RIT states explicitly that 1 Lomb Memorial Drive is not a student
    package address and mail sent there is delayed."""
    config = load_config()
    for office in config.post_offices.offices:
        assert "Lomb" not in office.street


def test_address_matches_the_published_examples():
    """The page gives worked examples. Ours must reproduce them exactly."""
    config = load_config()
    assert config.address_for("global-village", "Justin Case", "GV 400 1020") == [
        "Justin Case", "GV 400 1020", "6000 Reynolds Drive", "Rochester NY 14623",
    ]
    assert config.address_for("residence-halls", "Joseph Tigeroni", "Peterson 1234") == [
        "Joseph Tigeroni", "Peterson 1234", "43 Greenleaf Court", "Rochester NY 14623",
    ]
    assert config.address_for("riverknoll", "Ophelia Payne", "RK 123") == [
        "Ophelia Payne", "RK 123", "6000 Reynolds Drive", "Rochester NY 14623",
    ]


def test_missing_unit_shows_the_format_not_a_guess():
    config = load_config()
    lines = config.address_for("riverknoll", "Cole", None)
    assert lines[1] == "RK Apartment #"


def test_direct_delivery_bypasses_the_campus_post_offices():
    config = load_config()
    assert config.address_for("rit-inn", "Cole", None) == [
        "Cole", "5257 W Henrietta Rd", "Henrietta NY 14467",
    ]
    assert config.area("rit-inn") is None


def test_unknown_area_returns_none():
    assert load_config().address_for("does-not-exist", "Cole", None) is None


OFFICE = {
    "id": "gv", "name": "GV", "side": "west", "building": "GV",
    "street": "6000 Reynolds Drive", "city": "Rochester", "state": "NY", "zip": "14623",
    "hours": [],
}


def _write(tmp_path, housing=None, offices=None, shed=None):
    (tmp_path / "post_offices.json").write_text(json.dumps(offices or {
        "last_verified": "2026-08-28", "offices": [OFFICE],
    }))
    (tmp_path / "shed_hours.json").write_text(json.dumps(shed or {
        "last_verified": "2026-08-28", "spaces": [],
    }))
    (tmp_path / "housing_areas.json").write_text(json.dumps(housing or {
        "last_verified": "2026-08-28", "areas": [],
    }))
    (tmp_path / "fd_locations.json").write_text(json.dumps({
        "last_verified": "2026-08-30", "tenant_id": 20, "locations": [],
    }))
    (tmp_path / "dining_categories.json").write_text(json.dumps({
        "last_verified": "2026-08-28",
        "categories": [{"id": "other", "name": "Everything else", "order": 1}],
        "default_category": "other",
        "assignments": {},
    }))
    return tmp_path


def test_dangling_post_office_reference_is_fatal(tmp_path):
    _write(tmp_path, housing={
        "last_verified": "2026-08-28",
        "areas": [{
            "id": "x", "name": "X", "post_office": "does-not-exist",
            "line2_format": "F", "line2_example": "E",
        }],
    })
    with pytest.raises(ConfigError, match="unknown post_office"):
        load_config(tmp_path)


def test_bad_weekday_is_fatal(tmp_path):
    _write(tmp_path, offices={
        "last_verified": "2026-08-28",
        "offices": [{**OFFICE,
            "hours": [{"days": ["FUNDAY"], "opens_at": "08:00", "closes_at": "17:00"}]}],
    })
    with pytest.raises(ConfigError, match="unknown weekday"):
        load_config(tmp_path)


def test_bad_time_format_is_fatal(tmp_path):
    _write(tmp_path, offices={
        "last_verified": "2026-08-28",
        "offices": [{**OFFICE,
            "hours": [{"days": ["MONDAY"], "opens_at": "8am", "closes_at": "17:00"}]}],
    })
    with pytest.raises(ConfigError, match="expected HH:MM"):
        load_config(tmp_path)


def test_unknown_field_is_fatal(tmp_path):
    """extra=forbid, so a typo in a key crashes rather than being ignored."""
    _write(tmp_path, offices={
        "last_verified": "2026-08-28",
        "offices": [{**OFFICE, "emial": "typo@rit.edu"}],
    })
    with pytest.raises(ConfigError):
        load_config(tmp_path)


def test_duplicate_ids_are_fatal(tmp_path):
    _write(tmp_path, offices={
        "last_verified": "2026-08-28",
        "offices": [OFFICE, {**OFFICE, "name": "GV again"}],
    })
    with pytest.raises(ConfigError, match="duplicate post office"):
        load_config(tmp_path)


def test_missing_file_is_fatal(tmp_path):
    with pytest.raises(ConfigError, match="missing"):
        load_config(tmp_path)


def test_verified_config_is_not_reported_stale(config):
    """Everything now carries a real last_verified from the authoritative page."""
    assert staleness_report() == []


def test_old_entries_are_reported_stale(config):
    from datetime import date
    stale = staleness_report(today=date(2030, 1, 1))
    kinds = {entry["kind"] for entry in stale}
    assert "post_office" in kinds
    assert "housing_area" in kinds
    assert "makerspace" in kinds


def test_dining_categories_cover_every_known_location():
    """TigerCenter exposes no category, so these live in config. A location
    missing from the map silently falls into the default bucket."""
    import json
    from pathlib import Path

    config = load_config()
    fixture = json.loads(
        (Path(__file__).parent / "fixtures" / "tigercenter_dining_all.json").read_text()
    )
    ids = {str(loc["id"]) for loc in fixture["locations"]}
    assigned = set(config.dining_categories.assignments)
    assert ids - assigned == set(), "these locations have no category"


def test_dining_category_lookup_falls_back_for_an_unknown_location():
    config = load_config()
    assert config.dining_categories.category_for(999999) == "other"


def test_unknown_dining_category_is_fatal(tmp_path):
    _write(tmp_path)
    (tmp_path / "fd_locations.json").write_text(json.dumps({
        "last_verified": "2026-08-30", "tenant_id": 20, "locations": [],
    }))
    (tmp_path / "dining_categories.json").write_text(json.dumps({
        "last_verified": "2026-08-28",
        "categories": [{"id": "market", "name": "Markets", "order": 1}],
        "default_category": "market",
        "assignments": {"23": "does-not-exist"},
    }))
    with pytest.raises(ConfigError, match="unknown category"):
        load_config(tmp_path)
