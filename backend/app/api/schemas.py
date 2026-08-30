"""Response models. These are the contract the Flutter client codes against."""

from datetime import date, datetime
from typing import Generic, TypeVar

from pydantic import BaseModel

T = TypeVar("T")


class Collection(BaseModel, Generic[T]):
    """Envelope for every list endpoint.

    A cold cache answers 200 with an empty `data` array and stale: true, never
    a 503. The client shows a subtle indicator, not an error screen.
    """

    data: list[T]
    stale: bool = False
    last_updated: datetime | None = None


class OpenSpan(BaseModel):
    opens_at: datetime
    closes_at: datetime
    is_exception: bool
    menu_types: list[str] = []


class Occupancy(BaseModel):
    count: int | None = None
    max_occ: int | None = None
    open_status: str | None = None
    percent_full: int | None = None
    # True when the live count exceeds the published capacity. RIT's max_occ is
    # frequently too low (Midnight Oil reads 46 against a stated 38), so the
    # percentage is not trustworthy in that case and the client should say
    # "busy" rather than quote a precise figure.
    over_capacity: bool = False


class DiningLocation(BaseModel):
    id: int
    name: str
    # From static config. TigerCenter publishes no usable category of its own.
    category: str = "other"
    category_name: str = "Everything else"
    category_order: int = 999
    summary: str | None = None
    description: str | None = None
    maps_url: str | None = None
    mdo_id: int | None = None
    is_open: bool
    closes_at: datetime | None = None
    opens_at: datetime | None = None
    next_transition: datetime | None = None
    today: list[OpenSpan] = []
    occupancy: Occupancy | None = None


class MenuItem(BaseModel):
    id: int
    location_id: int
    location_name: str
    name: str
    description: str | None = None
    price: float | None = None
    category: str | None = None


class Event(BaseModel):
    uid: str
    source: str
    title: str
    description: str | None = None
    location: str | None = None
    building: str | None = None
    room: str | None = None
    organizer: str | None = None
    organizer_key: str | None = None
    event_type: str | None = None
    url: str | None = None
    starts_at: datetime
    ends_at: datetime | None = None
    all_day: bool


class Organizer(BaseModel):
    organizer_key: str | None = None
    organizer: str | None = None
    source: str
    event_count: int


class Equipment(BaseModel):
    id: str
    name: str
    sub_name: str | None = None
    room: str | None = None
    num_available: int
    num_in_use: int


class RoomSummary(BaseModel):
    room: str | None = None
    machines: int
    available: int
    in_use: int


class RecreationSpan(BaseModel):
    opens_at: str
    closes_at: str


class RecreationDay(BaseModel):
    service_date: date
    closed: bool
    note: str | None = None
    # Several sessions in one day is normal for the pool.
    spans: list[RecreationSpan] = []


class RecreationFacility(BaseModel):
    name: str
    days: list[RecreationDay] = []


class HoursRule(BaseModel):
    days: list[str]
    opens_at: str
    closes_at: str
    season: str
    service: str = "general"


class PostOffice(BaseModel):
    id: str
    name: str
    side: str
    building: str
    location_note: str | None = None
    street: str
    city: str
    state: str
    zip: str
    email: str | None = None
    phone: str | None = None
    last_verified: str | None = None
    hours: list[HoursRule]


class MakerSpaceHours(BaseModel):
    id: str
    name: str
    location: str
    last_verified: str | None = None
    hours: list[HoursRule]


class HousingArea(BaseModel):
    id: str
    name: str
    post_office: str | None = None
    line2_format: str | None = None
    line2_example: str | None = None
    direct_delivery: bool = False
    last_verified: str | None = None


class MailingAddress(BaseModel):
    area_id: str
    area_name: str
    lines: list[str]
    line2_format: str | None = None
    line2_example: str | None = None
    unit_supplied: bool
    direct_delivery: bool = False
    note: str | None = None
    post_office: PostOffice | None = None
    source_url: str | None = None
    last_verified: str | None = None
    verified: bool


class SourceHealth(BaseModel):
    source: str
    last_success_at: str | None = None
    last_attempt_at: str | None = None
    last_error: str | None = None
    last_error_at: str | None = None
    consecutive_failures: int
    last_record_count: int | None = None
    state: str
    healthy: bool


class StaleConfigEntry(BaseModel):
    kind: str
    id: str
    name: str
    last_verified: str | None = None
    age_days: int | None = None
    reason: str


class SourcesReport(BaseModel):
    sources: list[SourceHealth]
    stale_config: list[StaleConfigEntry]
    all_healthy: bool
    priming: bool


class Health(BaseModel):
    status: str
    app: str
    version: str
    disclaimer: str
