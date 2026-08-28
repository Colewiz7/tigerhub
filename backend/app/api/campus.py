"""Housing mail addresses and post office hours, both from static config.

RIT runs a zone based mail system, verified against
https://www.rit.edu/fa/campus-post-offices. There are no per hall street
addresses and no mailbox numbers. Every housing area routes to one of two
campus post offices, and line 2 carries a building/room designator whose
format varies by area.
"""

from fastapi import APIRouter, HTTPException, Query

from app.api.schemas import Collection, HousingArea, MailingAddress, PostOffice
from app.config import get_config

router = APIRouter(tags=["campus"])


def _post_office_model(office) -> PostOffice:
    return PostOffice(
        id=office.id,
        name=office.name,
        side=office.side,
        building=office.building,
        location_note=office.location_note,
        street=office.street,
        city=office.city,
        state=office.state,
        zip=office.zip,
        email=office.email,
        phone=office.phone,
        last_verified=office.last_verified.isoformat() if office.last_verified else None,
        hours=[rule.model_dump() for rule in office.hours],
    )


@router.get("/post-offices", response_model=Collection[PostOffice])
def list_post_offices():
    config = get_config()
    return Collection[PostOffice](
        data=[_post_office_model(o) for o in config.post_offices.offices]
    )


@router.get("/housing/areas", response_model=Collection[HousingArea])
def list_areas():
    """Mail zones, including the two locations that bypass campus post offices."""
    config = get_config()
    areas = [
        HousingArea(
            id=area.id,
            name=area.name,
            post_office=area.post_office,
            line2_format=area.line2_format,
            line2_example=area.line2_example,
            last_verified=area.last_verified.isoformat() if area.last_verified else None,
        )
        for area in config.housing.areas
    ]
    areas += [
        HousingArea(
            id=direct.id,
            name=direct.name,
            direct_delivery=True,
            last_verified=direct.last_verified.isoformat() if direct.last_verified else None,
        )
        for direct in config.housing.direct_delivery
    ]
    return Collection[HousingArea](data=areas)


@router.get("/housing/areas/{area_id}/address", response_model=MailingAddress)
def area_address(
    area_id: str,
    name: str = Query("Your Name", description="Line one of the address"),
    unit: str | None = Query(
        None,
        description="Your building and room, for example 'Peterson 1234' or 'GV 400 1020'. "
        "When omitted, the area's documented format is shown as a placeholder.",
    ),
):
    config = get_config()
    lines = config.address_for(area_id, name, unit)
    if lines is None:
        raise HTTPException(status_code=404, detail="housing area not found")

    direct = config.direct(area_id)
    if direct is not None:
        return MailingAddress(
            area_id=direct.id,
            area_name=direct.name,
            lines=lines,
            unit_supplied=True,
            direct_delivery=True,
            note=direct.note,
            source_url=config.housing.source_url,
            last_verified=direct.last_verified.isoformat() if direct.last_verified else None,
            verified=direct.last_verified is not None,
        )

    area = config.area(area_id)
    office = config.office(area.post_office)
    return MailingAddress(
        area_id=area.id,
        area_name=area.name,
        lines=lines,
        line2_format=area.line2_format,
        line2_example=area.line2_example,
        unit_supplied=unit is not None,
        post_office=_post_office_model(office) if office else None,
        source_url=config.housing.source_url,
        last_verified=area.last_verified.isoformat() if area.last_verified else None,
        verified=area.last_verified is not None,
    )
