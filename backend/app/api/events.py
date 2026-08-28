"""Event routes. One merged feed, filterable by source and organizer."""

from datetime import datetime, timedelta

from fastapi import APIRouter, Query

from app import settings
from app.api.schemas import Event, Organizer
from app.models import events as events_model

router = APIRouter(prefix="/events", tags=["events"])


@router.get("", response_model=list[Event])
def list_events(
    days: int = Query(14, ge=1, le=180, description="Window length from `start`"),
    start: datetime | None = Query(None, description="Defaults to now"),
    source: list[str] | None = Query(None, description="campusgroups and/or drupal"),
    organizer: list[str] | None = Query(None, description="organizer_key allowlist"),
    mute: list[str] | None = Query(None, description="organizer_key denylist"),
    limit: int = Query(500, ge=1, le=2000),
):
    begins = start or datetime.now(settings.CAMPUS_TZ)
    return events_model.query(
        start=begins,
        end=begins + timedelta(days=days),
        sources=source,
        organizer_keys=organizer,
        exclude_organizer_keys=mute,
        limit=limit,
    )


@router.get("/organizers", response_model=list[Organizer])
def list_organizers():
    """Facets for grouping, collapsing, or muting a noisy source."""
    return events_model.organizers()
