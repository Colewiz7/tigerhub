"""Event routes. One merged feed, filterable by source and organizer."""

from datetime import datetime, timedelta

from fastapi import APIRouter, Query

from app import settings
from app import freshness
from app.api.schemas import Collection, Event, Organizer
from app.models import events as events_model

router = APIRouter(prefix="/events", tags=["events"])


@router.get("", response_model=Collection[Event])
def list_events(
    days: int = Query(14, ge=1, le=180, description="Window length from `start`"),
    start: datetime | None = Query(None, description="Defaults to now"),
    source: list[str] | None = Query(None, description="campusgroups and/or drupal"),
    organizer: list[str] | None = Query(None, description="organizer_key allowlist"),
    mute: list[str] | None = Query(None, description="organizer_key denylist"),
    limit: int = Query(500, ge=1, le=2000),
):
    begins = start or datetime.now(settings.CAMPUS_TZ)
    rows = events_model.query(
        start=begins,
        end=begins + timedelta(days=days),
        sources=source,
        organizer_keys=organizer,
        exclude_organizer_keys=mute,
        limit=limit,
    )
    # Either feed being cold makes the merged view incomplete.
    stale = freshness.is_stale("campusgroups") or freshness.is_stale("drupal")
    updates = [freshness.last_success("campusgroups"), freshness.last_success("drupal")]
    seen = [u for u in updates if u]
    return Collection[Event](data=rows, stale=stale, last_updated=min(seen) if seen else None)


@router.get("/organizers", response_model=Collection[Organizer])
def list_organizers():
    """Facets for grouping, collapsing, or muting a noisy source."""
    return Collection[Organizer](
        data=events_model.organizers(),
        stale=freshness.is_stale("campusgroups") or freshness.is_stale("drupal"),
    )
