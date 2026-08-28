"""SHED makerspace routes.

Equipment availability is live from their GraphQL API. Hours come from static
config, because their hours feed is broken. See CLAUDE.md section 8 decision 3.
"""

from fastapi import APIRouter, Query

from app.api.schemas import Equipment, MakerSpaceHours, RoomSummary
from app.config import get_config
from app.models import makerspace as makerspace_model

router = APIRouter(prefix="/makerspace", tags=["makerspace"])


@router.get("/equipment", response_model=list[Equipment])
def list_equipment(room: str | None = Query(None)):
    return makerspace_model.list_equipment(room)


@router.get("/rooms", response_model=list[RoomSummary])
def list_rooms():
    return makerspace_model.room_summary()


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
