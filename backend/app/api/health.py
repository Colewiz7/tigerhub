"""Health endpoints.

/health is a liveness probe. /health/sources is the one that matters: it
reports per scraper last success and last error, plus stale static config, so a
broken parser or a config that drifted out of season surfaces before the UI
notices.
"""

from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Response

from app import settings
from app.api.schemas import Health, SourceHealth, SourcesReport, StaleConfigEntry
from app.config import staleness_report
from app.models import health as health_model

router = APIRouter(prefix="/health", tags=["health"])

DISCLAIMER = (
    "Not affiliated with, endorsed by, or officially connected to "
    "Rochester Institute of Technology. Student built and student maintained."
)

# A source counts as unhealthy once it has missed several cycles in a row, so a
# single transient upstream blip does not page anyone.
MAX_CONSECUTIVE_FAILURES = 3

# How long after its expected cadence a source is considered overdue.
EXPECTED_INTERVAL_MINUTES = {
    "tigercenter_dining": settings.INTERVAL_DINING_MINUTES,
    "campusgroups": settings.INTERVAL_EVENTS_MINUTES,
    "drupal": settings.INTERVAL_EVENTS_MINUTES,
    "makerspace_equipment": settings.INTERVAL_MAKERSPACE_MINUTES,
    "maps_occupancy": settings.INTERVAL_OCCUPANCY_MINUTES,
}
OVERDUE_GRACE = 3


@router.get("", response_model=Health)
def health():
    return Health(
        status="ok",
        app=settings.APP_NAME,
        version=settings.APP_VERSION,
        disclaimer=DISCLAIMER,
    )


def _is_healthy(row: dict) -> bool:
    if row.get("consecutive_failures", 0) >= MAX_CONSECUTIVE_FAILURES:
        return False
    last_success = row.get("last_success_at")
    if not last_success:
        return False

    interval = EXPECTED_INTERVAL_MINUTES.get(row["source"])
    if interval is None:
        return True
    try:
        seen = datetime.fromisoformat(last_success)
    except ValueError:
        return False
    if seen.tzinfo is None:
        seen = seen.replace(tzinfo=timezone.utc)
    deadline = seen + timedelta(minutes=interval * OVERDUE_GRACE)
    return datetime.now(timezone.utc) <= deadline


@router.get("/sources", response_model=SourcesReport)
def sources(response: Response):
    rows = health_model.all_sources()
    reported = [SourceHealth(**row, healthy=_is_healthy(row)) for row in rows]
    stale = [StaleConfigEntry(**entry) for entry in staleness_report()]

    # No rows at all means nothing has run yet, which is not healthy either.
    all_healthy = bool(reported) and all(s.healthy for s in reported)
    if not all_healthy:
        # 503 so a uptime check notices without having to parse the body.
        response.status_code = 503

    return SourcesReport(sources=reported, stale_config=stale, all_healthy=all_healthy)
