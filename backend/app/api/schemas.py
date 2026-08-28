"""Response models. These are the contract the Flutter client codes against."""

from datetime import datetime

from pydantic import BaseModel


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


class DiningLocation(BaseModel):
    id: int
    name: str
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


class HoursRule(BaseModel):
    days: list[str]
    opens_at: str
    closes_at: str
    season: str


class PostOffice(BaseModel):
    id: str
    name: str
    building: str
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


class ResidenceHall(BaseModel):
    id: str
    name: str
    area: str
    post_office: str
    last_verified: str | None = None


class MailingAddress(BaseModel):
    hall_id: str
    hall_name: str
    lines: list[str]
    address_note: str | None = None
    post_office: PostOffice | None = None
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


class Health(BaseModel):
    status: str
    app: str
    version: str
    disclaimer: str
