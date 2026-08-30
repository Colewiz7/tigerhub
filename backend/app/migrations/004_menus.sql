-- Menus with allergen and dietary tags, from FD MealPlanner.
--
-- One row per dish per location per date. FD publishes a whole month per
-- request, so a single fetch fills weeks at a time.
--
-- Allergens and dietary tags are stored verbatim as RIT publishes them. They
-- are not interpreted, corrected, or extended, because getting an allergen
-- wrong is not a cosmetic bug.
CREATE TABLE IF NOT EXISTS menu_dish (
    location_id  INTEGER NOT NULL,
    service_date TEXT    NOT NULL,
    name         TEXT    NOT NULL,
    category     TEXT,
    allergens    TEXT,
    dietary      TEXT,
    calories     REAL,
    updated_at   TEXT    NOT NULL,
    PRIMARY KEY (location_id, service_date, name)
);
CREATE INDEX IF NOT EXISTS idx_menu_dish_date ON menu_dish(location_id, service_date);
