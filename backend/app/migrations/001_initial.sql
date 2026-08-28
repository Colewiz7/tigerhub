-- Dining locations from TigerCenter dining-all.
CREATE TABLE IF NOT EXISTS dining_location (
    id           INTEGER PRIMARY KEY,
    name         TEXT    NOT NULL,
    summary      TEXT,
    description  TEXT,
    maps_url     TEXT,
    department   TEXT,
    mdo_id       INTEGER,
    updated_at   TEXT    NOT NULL
);

-- Resolved concrete open/close spans, one row per location per date.
-- The recurrence model from TigerCenter is flattened here so the client
-- never does date math.
CREATE TABLE IF NOT EXISTS dining_hours (
    location_id  INTEGER NOT NULL,
    service_date TEXT    NOT NULL,
    opens_at     TEXT    NOT NULL,
    closes_at    TEXT    NOT NULL,
    closes_next_day INTEGER NOT NULL DEFAULT 0,
    menu_types   TEXT,
    source_event_id INTEGER,
    is_exception INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (location_id, service_date, opens_at, closes_at),
    FOREIGN KEY (location_id) REFERENCES dining_location(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_dining_hours_date ON dining_hours(service_date);

-- Visiting chefs and specials, from menus[] on the same payload.
CREATE TABLE IF NOT EXISTS dining_menu_item (
    id           INTEGER NOT NULL,
    location_id  INTEGER NOT NULL,
    service_date TEXT    NOT NULL,
    name         TEXT    NOT NULL,
    description  TEXT,
    price        REAL,
    category     TEXT,
    PRIMARY KEY (id, service_date),
    FOREIGN KEY (location_id) REFERENCES dining_location(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_menu_date_cat ON dining_menu_item(service_date, category);

-- One merged events table. `source` distinguishes the feeds, `organizer` is a
-- first class column so a noisy source can be grouped, collapsed, or muted.
-- No dedupe for MVP, by design, so the real overlap stays observable.
CREATE TABLE IF NOT EXISTS event (
    uid          TEXT    NOT NULL,
    source       TEXT    NOT NULL,
    title        TEXT    NOT NULL,
    description  TEXT,
    location     TEXT,
    building     TEXT,
    room         TEXT,
    organizer    TEXT,
    organizer_key TEXT,
    event_type   TEXT,
    url          TEXT,
    starts_at    TEXT    NOT NULL,
    ends_at      TEXT,
    all_day      INTEGER NOT NULL DEFAULT 0,
    updated_at   TEXT    NOT NULL,
    PRIMARY KEY (source, uid)
);
CREATE INDEX IF NOT EXISTS idx_event_start ON event(starts_at);
CREATE INDEX IF NOT EXISTS idx_event_organizer ON event(organizer_key);

-- SHED makerspace equipment availability.
CREATE TABLE IF NOT EXISTS equipment (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    sub_name      TEXT,
    room          TEXT,
    in_use        INTEGER NOT NULL DEFAULT 0,
    num_available INTEGER NOT NULL DEFAULT 0,
    num_in_use    INTEGER NOT NULL DEFAULT 0,
    updated_at    TEXT NOT NULL
);

-- Live occupancy from maps.rit.edu, keyed by the TigerCenter mdo_id.
CREATE TABLE IF NOT EXISTS occupancy (
    mdo_id      INTEGER PRIMARY KEY,
    count       INTEGER,
    max_occ     INTEGER,
    open_status TEXT,
    hourly      TEXT,
    updated_at  TEXT NOT NULL
);

-- Per scraper health, so a broken parser surfaces before the UI notices.
CREATE TABLE IF NOT EXISTS source_health (
    source            TEXT PRIMARY KEY,
    last_success_at   TEXT,
    last_attempt_at   TEXT,
    last_error        TEXT,
    last_error_at     TEXT,
    consecutive_failures INTEGER NOT NULL DEFAULT 0,
    last_record_count INTEGER
);
