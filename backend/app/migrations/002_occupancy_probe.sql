-- Only a handful of dining locations actually have occupancy sensors. Verified
-- 2026-08-28: 5 of 24 return a densityData block, the other 19 have no such key
-- upstream at all.
--
-- Polling all 24 every 5 minutes would send about 5,400 pointless requests a
-- day to maps.rit.edu. This table remembers which locations are worth polling,
-- so the steady state is 5 requests per cycle instead of 24.
CREATE TABLE IF NOT EXISTS occupancy_probe (
    mdo_id         INTEGER PRIMARY KEY,
    has_density    INTEGER NOT NULL DEFAULT 0,
    last_probed_at TEXT    NOT NULL
);
