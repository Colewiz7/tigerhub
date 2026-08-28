"""Health endpoints.

/health is a liveness probe. /health/sources is the one that matters: it
reports per scraper last success and last error, plus stale static config, so a
broken parser or a config that drifted out of season surfaces before the UI
notices.
"""

from fastapi import APIRouter, Response

from app import freshness, settings
from app.api.schemas import Health, SourceHealth, SourcesReport, StaleConfigEntry
from app.config import staleness_report
from app.models import health as health_model

router = APIRouter(prefix="/health", tags=["health"])

DISCLAIMER = (
    "Not affiliated with, endorsed by, or officially connected to "
    "Rochester Institute of Technology. Student built and student maintained."
)



@router.get("", response_model=Health)
def health():
    """Liveness. Answers as soon as the port is bound.

    Deliberately independent of scraper state: a cold cache is a normal phase
    of a container that just started, not a failed rollout. Point the k8s
    readiness probe here, and use /health/sources for monitoring.
    """
    return Health(
        status="ok",
        app=settings.APP_NAME,
        version=settings.APP_VERSION,
        disclaimer=DISCLAIMER,
    )


@router.get("/sources", response_model=SourcesReport)
def sources(response: Response):
    """Per scraper detail, plus static config that needs re-verifying.

    States: priming (never scraped, still inside the startup grace), ok, stale
    (last success older than several cycles), failing. Only stale and failing
    count against health, so a container that just booted is not reported as
    broken.
    """
    rows = health_model.all_sources()
    known = set(freshness.EXPECTED_INTERVAL_MINUTES)
    seen = {row["source"] for row in rows}

    # A source with no row yet still belongs in the report, as priming.
    for missing in sorted(known - seen):
        rows.append(
            {
                "source": missing,
                "last_success_at": None,
                "last_attempt_at": None,
                "last_error": None,
                "last_error_at": None,
                "consecutive_failures": 0,
                "last_record_count": None,
            }
        )

    reported = []
    for row in rows:
        state = freshness.state_of(row)
        reported.append(SourceHealth(**row, state=state, healthy=state in ("ok", "priming")))

    stale_config = [StaleConfigEntry(**entry) for entry in staleness_report()]
    priming = any(s.state == "priming" for s in reported)
    all_healthy = all(s.healthy for s in reported)

    # 503 only for a real problem. Priming is not one.
    if not all_healthy:
        response.status_code = 503

    return SourcesReport(
        sources=reported,
        stale_config=stale_config,
        all_healthy=all_healthy,
        priming=priming,
    )
