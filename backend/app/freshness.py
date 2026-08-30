"""Data freshness, shared by the API envelope and the health report.

A cold cache is not an error state. It is a normal phase of a container that
just started, so it is reported as `priming` rather than as a failure, and data
endpoints answer 200 with an empty array plus stale: true.
"""

from datetime import datetime, timedelta, timezone

from app import settings
from app.models import health as health_model

# How long after a source's expected cadence its data counts as stale.
STALE_GRACE_MULTIPLIER = 3

# Grace period after boot during which "never scraped" reads as priming, not
# as a failure. Generous, because the first Drupal sweep takes a few seconds
# and a slow upstream should not look like a broken deploy.
PRIMING_GRACE = timedelta(minutes=15)

EXPECTED_INTERVAL_MINUTES = {
    "tigercenter_dining": settings.INTERVAL_DINING_MINUTES,
    "campusgroups": settings.INTERVAL_EVENTS_MINUTES,
    "drupal": settings.INTERVAL_EVENTS_MINUTES,
    "athletics": settings.INTERVAL_EVENTS_MINUTES,
    "makerspace_equipment": settings.INTERVAL_MAKERSPACE_MINUTES,
    "maps_occupancy": settings.INTERVAL_OCCUPANCY_MINUTES,
    "recreation_hours": settings.INTERVAL_RECREATION_MINUTES,
    # Rotating, so a full cycle takes twelve runs.
    "fd_menus": settings.INTERVAL_MENUS_MINUTES * 12,
}

STARTED_AT = datetime.now(timezone.utc)


def _parse(stamp: str | None) -> datetime | None:
    if not stamp:
        return None
    try:
        parsed = datetime.fromisoformat(stamp)
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _row(source: str) -> dict | None:
    return next((r for r in health_model.all_sources() if r["source"] == source), None)


def last_success(source: str) -> datetime | None:
    row = _row(source)
    return _parse(row.get("last_success_at")) if row else None


def state_of(row: dict, now: datetime | None = None) -> str:
    """One of priming, ok, stale, failing."""
    moment = now or datetime.now(timezone.utc)
    succeeded = _parse(row.get("last_success_at"))

    if succeeded is None:
        # Never scraped. That is priming right after boot, and a real problem
        # once the grace period has passed.
        return "priming" if moment - STARTED_AT < PRIMING_GRACE else "failing"

    interval = EXPECTED_INTERVAL_MINUTES.get(row["source"])
    if interval is not None:
        deadline = succeeded + timedelta(minutes=interval * STALE_GRACE_MULTIPLIER)
        if moment > deadline:
            return "stale"

    if row.get("consecutive_failures", 0) >= 3:
        return "failing"
    return "ok"


def is_stale(source: str, now: datetime | None = None) -> bool:
    """Is the cached data for this source missing or overdue?"""
    row = _row(source)
    if row is None:
        moment = now or datetime.now(timezone.utc)
        # No health row at all means nothing has ever run for this source.
        return True
    return state_of(row, now) in ("priming", "stale", "failing")
