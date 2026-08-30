"""Campus points of interest: fountains, blue lights, restrooms and the rest."""

from fastapi import APIRouter, Query

from app import freshness
from app.api.schemas import CampusPlace, Collection, PlaceKind
from app.models import places as places_model

router = APIRouter(prefix="/campus", tags=["campus"])


@router.get("/places", response_model=Collection[PlaceKind])
def kinds():
    """What kinds exist and how many of each."""
    return Collection[PlaceKind](
        data=[PlaceKind(**row) for row in places_model.kinds()],
        stale=freshness.is_stale("campus_places"),
        last_updated=freshness.last_success("campus_places"),
    )


@router.get("/places/{kind}", response_model=Collection[CampusPlace])
def of_kind(
    kind: str,
    building: str | None = Query(None, description="Building abbreviation, e.g. GOL"),
):
    return Collection[CampusPlace](
        data=[CampusPlace(**row) for row in places_model.of_kind(kind, building)],
        stale=freshness.is_stale("campus_places"),
        last_updated=freshness.last_success("campus_places"),
    )
