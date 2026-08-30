-- Points of interest from the RIT campus map: water fountains, blue light
-- phones, AEDs, all-gender and accessible restrooms, bus stops and so on.
--
-- This is physical infrastructure, so it changes rarely. It is scraped twice a
-- day rather than continuously.
CREATE TABLE IF NOT EXISTS campus_place (
    id           INTEGER NOT NULL,
    kind         TEXT    NOT NULL,
    kind_name    TEXT    NOT NULL,
    name         TEXT    NOT NULL,
    building     TEXT,
    building_no  TEXT,
    floor        TEXT,
    room         TEXT,
    note         TEXT,
    mdo_id       INTEGER,
    updated_at   TEXT    NOT NULL,
    PRIMARY KEY (kind, id)
);
CREATE INDEX IF NOT EXISTS idx_place_kind ON campus_place(kind);
CREATE INDEX IF NOT EXISTS idx_place_building ON campus_place(building);
