"""Dining routes. All served from the SQLite cache, never a live scrape."""

from datetime import date, datetime, timedelta

from fastapi import APIRouter, HTTPException, Query

from app import hours as hours_lib
from app import settings
from app.api.schemas import Collection, DiningLocation, MenuItem, Occupancy, OpenSpan
from app.config import get_config
from app import freshness
from app.models import dining, occupancy as occupancy_model

router = APIRouter(prefix="/dining", tags=["dining"])

VISITING_CHEF = "Visiting Chef"


def _occupancy_for(row: dict) -> Occupancy | None:
    """Occupancy is optional by design. A missing reading hides the chip.

    A reading with a count but no usable denominator still returns a chip, with
    percent_full left null. The client shows the raw count rather than silently
    dropping the location, so a missing capacity is visible instead of papered
    over. Verified 2026-08-28: all five sensor locations do publish max_occ, so
    this is a guard, not the normal path.
    """
    count = row.get("occupancy_count")
    if count is None:
        return None

    max_occ = row.get("occupancy_max") or 0
    percent = int(round(100 * count / max_occ)) if max_occ else None

    return Occupancy(
        count=count,
        max_occ=row.get("occupancy_max"),
        open_status=row.get("occupancy_status"),
        percent_full=min(percent, 100) if percent is not None else None,
        over_capacity=bool(max_occ) and count > max_occ,
    )


def _build(row: dict, grouped: dict, now: datetime) -> DiningLocation:
    state = hours_lib.open_state(grouped, now)
    categories = get_config().dining_categories
    category = categories.category_for(row["id"])
    return DiningLocation(
        id=row["id"],
        name=row["name"],
        category=category,
        category_name=categories.name_of(category),
        category_order=categories.order_of(category),
        summary=row.get("summary"),
        description=row.get("description"),
        maps_url=row.get("maps_url"),
        mdo_id=row.get("mdo_id"),
        is_open=state.is_open,
        opens_at=state.opens_at,
        closes_at=state.closes_at,
        next_transition=state.next_transition,
        today=[
            OpenSpan(
                opens_at=s.start_dt(),
                closes_at=s.end_dt(),
                is_exception=s.is_exception,
                menu_types=list(s.menu_types),
            )
            for s in state.spans_today
        ],
        occupancy=_occupancy_for(row),
    )


@router.get("", response_model=Collection[DiningLocation])
def list_dining(open_now: bool = Query(False, description="Only locations open right now")):
    now = datetime.now(settings.CAMPUS_TZ)
    today = now.date()
    rows = dining.hours_between(today - timedelta(days=1), today + timedelta(days=13))

    by_location: dict[int, list[dict]] = {}
    for row in rows:
        by_location.setdefault(row["location_id"], []).append(row)

    out = [
        _build(loc, hours_lib.group_by_date(by_location.get(loc["id"], [])), now)
        for loc in dining.list_locations()
    ]
    data = [loc for loc in out if loc.is_open] if open_now else out
    return Collection[DiningLocation](
        data=data,
        stale=freshness.is_stale("tigercenter_dining"),
        last_updated=freshness.last_success("tigercenter_dining"),
    )


@router.get("/visiting-chefs", response_model=Collection[MenuItem])
def visiting_chefs(on: date | None = Query(None, description="Defaults to today")):
    service_date = on or datetime.now(settings.CAMPUS_TZ).date()
    return Collection[MenuItem](
        data=dining.menu_items_on(service_date, VISITING_CHEF),
        stale=freshness.is_stale("tigercenter_dining"),
        last_updated=freshness.last_success("tigercenter_dining"),
    )


@router.get("/specials", response_model=Collection[MenuItem])
def specials(on: date | None = Query(None, description="Defaults to today")):
    service_date = on or datetime.now(settings.CAMPUS_TZ).date()
    return Collection[MenuItem](
        data=dining.menu_items_on(service_date),
        stale=freshness.is_stale("tigercenter_dining"),
        last_updated=freshness.last_success("tigercenter_dining"),
    )


@router.get("/{location_id}", response_model=DiningLocation)
def get_dining(location_id: int):
    location = dining.get_location(location_id)
    if location is None:
        raise HTTPException(status_code=404, detail="dining location not found")

    now = datetime.now(settings.CAMPUS_TZ)
    today = now.date()
    rows = dining.hours_between(today - timedelta(days=1), today + timedelta(days=13), location_id)

    reading = occupancy_model.get(location["mdo_id"]) if location.get("mdo_id") else None
    enriched = {
        **location,
        "occupancy_count": (reading or {}).get("count"),
        "occupancy_max": (reading or {}).get("max_occ"),
        "occupancy_status": (reading or {}).get("open_status"),
    }
    return _build(enriched, hours_lib.group_by_date(rows), now)


@router.get("/{location_id}/occupancy")
def get_occupancy(location_id: int):
    """The 24 hour series, for the how busy is it chart."""
    location = dining.get_location(location_id)
    if location is None:
        raise HTTPException(status_code=404, detail="dining location not found")
    reading = occupancy_model.get(location.get("mdo_id") or -1)
    if reading is None:
        raise HTTPException(status_code=404, detail="no occupancy reading for this location")
    return reading
