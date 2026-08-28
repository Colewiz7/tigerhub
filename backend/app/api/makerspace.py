"""SHED makerspace routes.

Equipment availability is live from their GraphQL API. Hours come from static
config, because their hours feed is broken. See CLAUDE.md section 8 decision 3.
"""

from fastapi import APIRouter, Query

from app import freshness
from app.api.schemas import Collection, Equipment, MakerSpaceHours, RoomSummary
from app.config import get_config
from app.models import makerspace as makerspace_model

router = APIRouter(prefix="/makerspace", tags=["makerspace"])


@router.get("/equipment", response_model=Collection[Equipment])
def list_equipment(room: str | None = Query(None)):
    return Collection[Equipment](
        data=makerspace_model.list_equipment(room),
        stale=freshness.is_stale("makerspace_equipment"),
        last_updated=freshness.last_success("makerspace_equipment"),
    )


@router.get("/rooms", response_model=Collection[RoomSummary])
def list_rooms():
    return Collection[RoomSummary](
        data=makerspace_model.room_summary(),
        stale=freshness.is_stale("makerspace_equipment"),
        last_updated=freshness.last_success("makerspace_equipment"),
    )


@router.get("/hours", response_model=list[MakerSpaceHours])
def list_hours():
    config = get_config()
    return [
        MakerSpaceHours(
            id=space.id,
            name=space.name,
            location=space.location,
            last_verified=space.last_verified.isoformat() if space.last_verified else None,
            hours=[rule.model_dump() for rule in space.hours],
        )
        for space in config.shed.spaces
    ]
