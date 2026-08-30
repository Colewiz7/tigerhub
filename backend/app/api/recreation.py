"""Gym, fitness and pool hours."""

from datetime import date, datetime, timedelta

from fastapi import APIRouter, Query

from app import freshness, settings
from app.api.schemas import Collection, RecreationDay, RecreationFacility, RecreationSpan
from app.models import recreation as recreation_model

router = APIRouter(prefix="/recreation", tags=["recreation"])


@router.get("/hours", response_model=Collection[RecreationFacility])
def hours(days: int = Query(7, ge=1, le=14)):
    """Grouped by facility, then by date.

    A facility can have several spans in one day. The Aquatics Center runs a
    morning lap swim, a lunch block and an evening block, so those stay
    separate rather than collapsing into one misleading range.
    """
    today = datetime.now(settings.CAMPUS_TZ).date()
    rows = recreation_model.between(today, today + timedelta(days=days - 1))

    by_facility: dict[str, dict[str, list[dict]]] = {}
    for row in rows:
        by_facility.setdefault(row["facility"], {}).setdefault(
            row["service_date"], []
        ).append(row)

    facilities = []
    for name, dates in by_facility.items():
        day_models = []
        for service_date, entries in sorted(dates.items()):
            closed = all(entry["closed"] for entry in entries)
            day_models.append(
                RecreationDay(
                    service_date=date.fromisoformat(service_date),
                    closed=closed,
                    note=next((e["note"] for e in entries if e["note"]), None),
                    spans=[
                        RecreationSpan(opens_at=e["opens_at"], closes_at=e["closes_at"])
                        for e in entries
                        if not e["closed"] and e["opens_at"] and e["closes_at"]
                    ],
                )
            )
        facilities.append(RecreationFacility(name=name, days=day_models))

    facilities.sort(key=lambda f: f.name)
    return Collection[RecreationFacility](
        data=facilities,
        stale=freshness.is_stale("recreation_hours"),
        last_updated=freshness.last_success("recreation_hours"),
    )
