"""Static config, treated like real data.

The gate task in CLAUDE.md section 7.10 confirmed RIT publishes none of this in
structured form, so these files are load bearing rather than a stopgap. That
means they get a schema, they are validated at startup, and a typo crashes the
container instead of quietly serving a wrong mailing address in October.

Every entry carries last_verified. A null or old date is surfaced by
/health/sources so seasonal hours get a nudge instead of silently going stale.
"""

from __future__ import annotations

import json
from datetime import date, datetime, timezone
from pathlib import Path

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator

from app import settings

WEEKDAYS = {
    "MONDAY",
    "TUESDAY",
    "WEDNESDAY",
    "THURSDAY",
    "FRIDAY",
    "SATURDAY",
    "SUNDAY",
}


class ConfigError(RuntimeError):
    """Static config failed validation. Fatal at boot, on purpose."""


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


class HoursRule(_Strict):
    days: list[str]
    opens_at: str
    closes_at: str
    season: str = "academic"
    # Post offices run two counters with different hours. Makerspaces do not,
    # so this defaults to a single unnamed service.
    service: str = "general"

    @field_validator("days")
    @classmethod
    def _known_days(cls, value: list[str]) -> list[str]:
        unknown = [d for d in value if d not in WEEKDAYS]
        if unknown:
            raise ValueError(f"unknown weekday(s): {unknown}")
        if not value:
            raise ValueError("days must not be empty")
        return value

    @field_validator("opens_at", "closes_at")
    @classmethod
    def _hhmm(cls, value: str) -> str:
        try:
            datetime.strptime(value, "%H:%M")
        except ValueError as exc:
            raise ValueError(f"expected HH:MM, got {value!r}") from exc
        return value


class PostOffice(_Strict):
    id: str
    name: str
    side: str
    building: str
    location_note: str | None = None
    street: str
    city: str
    state: str
    zip: str
    email: str | None = None
    phone: str | None = None
    last_verified: date | None = None
    hours: list[HoursRule]


class MakerSpace(_Strict):
    id: str
    name: str
    location: str
    last_verified: date | None = None
    hours: list[HoursRule]


class HousingArea(_Strict):
    """One mail zone.

    RIT runs a zone based system, not per hall street addresses. Every area
    routes to one of two campus post offices, and line 2 of the address is a
    building/room or apartment designator whose format varies by area.
    """

    id: str
    name: str
    post_office: str
    line2_format: str
    line2_example: str
    last_verified: date | None = None


class DirectDelivery(_Strict):
    """Housing whose mail bypasses the campus post offices entirely."""

    id: str
    name: str
    street: str
    city: str
    state: str
    zip: str
    note: str | None = None
    last_verified: date | None = None

    def mailing_address(self, student_name: str = "Your Name") -> list[str]:
        return [student_name, self.street, f"{self.city} {self.state} {self.zip}"]


class PostOfficeFile(_Strict):
    last_verified: date | None = None
    source_url: str | None = None
    source_note: str | None = None
    offices: list[PostOffice]


class ShedFile(_Strict):
    last_verified: date | None = None
    source_url: str | None = None
    source_note: str | None = None
    spaces: list[MakerSpace]


class HousingFile(_Strict):
    last_verified: date | None = None
    source_url: str | None = None
    source_note: str | None = None
    areas: list[HousingArea]
    direct_delivery: list[DirectDelivery] = []


class StaticConfig(BaseModel):
    post_offices: PostOfficeFile
    shed: ShedFile
    housing: HousingFile

    def area(self, area_id: str) -> HousingArea | None:
        return next((a for a in self.housing.areas if a.id == area_id), None)

    def direct(self, area_id: str) -> DirectDelivery | None:
        return next((d for d in self.housing.direct_delivery if d.id == area_id), None)

    def office(self, office_id: str) -> PostOffice | None:
        return next((o for o in self.post_offices.offices if o.id == office_id), None)

    def address_for(self, area_id: str, student_name: str, unit: str | None) -> list[str] | None:
        """Build the mailing address lines for an area.

        Line 2 is the student's own building/room designator. When it is not
        supplied, the area's documented format is shown as a placeholder rather
        than being invented.
        """
        direct = self.direct(area_id)
        if direct is not None:
            return direct.mailing_address(student_name)

        area = self.area(area_id)
        if area is None:
            return None
        office = self.office(area.post_office)
        if office is None:
            return None
        return [
            student_name,
            unit or area.line2_format,
            office.street,
            f"{office.city} {office.state} {office.zip}",
        ]


_FILES = {
    "post_offices": ("post_offices.json", PostOfficeFile),
    "shed": ("shed_hours.json", ShedFile),
    "housing": ("housing_areas.json", HousingFile),
}

_cache: StaticConfig | None = None


def load_config(data_dir: Path | None = None) -> StaticConfig:
    """Parse and validate every config file. Raises ConfigError on any problem."""
    directory = data_dir or settings.CONFIG_DATA_DIR
    parsed: dict = {}
    problems: list[str] = []

    for key, (filename, model) in _FILES.items():
        path = directory / filename
        if not path.exists():
            problems.append(f"{filename}: missing")
            continue
        try:
            parsed[key] = model.model_validate(json.loads(path.read_text()))
        except json.JSONDecodeError as exc:
            problems.append(f"{filename}: invalid JSON, {exc}")
        except ValidationError as exc:
            problems.append(f"{filename}: {exc.error_count()} error(s)\n{exc}")

    if problems:
        raise ConfigError("static config failed validation:\n" + "\n".join(problems))

    config = StaticConfig(**parsed)
    _check_referential_integrity(config)
    return config


def _check_referential_integrity(config: StaticConfig) -> None:
    """A hall pointing at a post office that does not exist is a typo, not data."""
    known = {office.id for office in config.post_offices.offices}
    dangling = sorted({a.post_office for a in config.housing.areas if a.post_office not in known})
    if dangling:
        raise ConfigError(
            f"housing_areas.json references unknown post_office id(s): {dangling}. "
            f"Known ids: {sorted(known)}"
        )

    duplicates = _duplicates(
        [a.id for a in config.housing.areas] + [d.id for d in config.housing.direct_delivery]
    )
    if duplicates:
        raise ConfigError(f"duplicate housing area id(s): {duplicates}")
    duplicates = _duplicates([o.id for o in config.post_offices.offices])
    if duplicates:
        raise ConfigError(f"duplicate post office id(s): {duplicates}")


def _duplicates(values: list[str]) -> list[str]:
    seen: set[str] = set()
    dupes: set[str] = set()
    for value in values:
        (dupes if value in seen else seen).add(value)
    return sorted(dupes)


def get_config() -> StaticConfig:
    """The validated config. Loaded once at startup by the app lifespan."""
    global _cache
    if _cache is None:
        _cache = load_config()
    return _cache


def set_config(config: StaticConfig | None) -> None:
    global _cache
    _cache = config


def staleness_report(today: date | None = None) -> list[dict]:
    """Entries whose last_verified is null or older than the threshold.

    Surfaced by /health/sources so seasonal hours get a nudge in November
    instead of quietly serving summer hours.
    """
    config = get_config()
    now = today or datetime.now(settings.CAMPUS_TZ).date()
    limit = settings.CONFIG_STALE_AFTER_DAYS
    stale: list[dict] = []

    def check(kind: str, entry_id: str, name: str, verified: date | None) -> None:
        if verified is None:
            stale.append(
                {
                    "kind": kind,
                    "id": entry_id,
                    "name": name,
                    "last_verified": None,
                    "age_days": None,
                    "reason": "never verified",
                }
            )
            return
        age = (now - verified).days
        if age > limit:
            stale.append(
                {
                    "kind": kind,
                    "id": entry_id,
                    "name": name,
                    "last_verified": verified.isoformat(),
                    "age_days": age,
                    "reason": f"older than {limit} days",
                }
            )

    for office in config.post_offices.offices:
        check("post_office", office.id, office.name, office.last_verified)
    for space in config.shed.spaces:
        check("makerspace", space.id, space.name, space.last_verified)
    for area in config.housing.areas:
        check("housing_area", area.id, area.name, area.last_verified)
    for direct in config.housing.direct_delivery:
        check("direct_delivery", direct.id, direct.name, direct.last_verified)

    return stale
