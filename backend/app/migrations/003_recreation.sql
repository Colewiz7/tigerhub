-- Gym, fitness and pool hours, scraped from RIT Recreation and Wellness.
--
-- One row per facility per date per span. A facility can genuinely have
-- several sessions in a day: the Aquatics Center runs a morning lap swim, a
-- lunch block and an evening block, and collapsing those into one open-to-close
-- range would tell people the pool is open when it is not.
CREATE TABLE IF NOT EXISTS recreation_hours (
    facility     TEXT    NOT NULL,
    service_date TEXT    NOT NULL,
    opens_at     TEXT,
    closes_at    TEXT,
    closed       INTEGER NOT NULL DEFAULT 0,
    note         TEXT,
    updated_at   TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_recreation_date ON recreation_hours(service_date);
CREATE INDEX IF NOT EXISTS idx_recreation_facility ON recreation_hours(facility);
