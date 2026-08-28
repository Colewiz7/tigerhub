"""Housing address lookup and post office hours, both from static config."""

from fastapi import APIRouter, HTTPException, Query

from app.api.schemas import MailingAddress, PostOffice, ResidenceHall
from app.config import get_config

router = APIRouter(tags=["campus"])


def _post_office_model(office) -> PostOffice:
    return PostOffice(
        id=office.id,
        name=office.name,
        building=office.building,
        email=office.email,
        phone=office.phone,
        last_verified=office.last_verified.isoformat() if office.last_verified else None,
        hours=[rule.model_dump() for rule in office.hours],
    )


@router.get("/post-offices", response_model=list[PostOffice])
def list_post_offices():
    return [_post_office_model(o) for o in get_config().post_offices.offices]


@router.get("/housing/halls", response_model=list[ResidenceHall])
def list_halls():
    return [
        ResidenceHall(
            id=hall.id,
            name=hall.name,
            area=hall.area,
            post_office=hall.post_office,
            last_verified=hall.last_verified.isoformat() if hall.last_verified else None,
        )
        for hall in get_config().residence_halls.halls
    ]


@router.get("/housing/halls/{hall_id}/address", response_model=MailingAddress)
def hall_address(hall_id: str, name: str = Query("Your Name", description="Name for line one")):
    """The correct mailing format for a hall.

    `verified` is false while the underlying entry has no last_verified date.
    The client should show a caution note rather than presenting it as gospel.
    """
    config = get_config()
    hall = config.hall(hall_id)
    if hall is None:
        raise HTTPException(status_code=404, detail="residence hall not found")

    office = config.office(hall.post_office)
    return MailingAddress(
        hall_id=hall.id,
        hall_name=hall.name,
        lines=hall.mailing_address(name),
        address_note=hall.address_note,
        post_office=_post_office_model(office) if office else None,
        last_verified=hall.last_verified.isoformat() if hall.last_verified else None,
        verified=hall.last_verified is not None,
    )
