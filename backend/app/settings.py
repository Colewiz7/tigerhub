"""Runtime settings. Environment driven, with sane defaults for local dev."""

import os
from pathlib import Path
from zoneinfo import ZoneInfo

APP_NAME = "RIT Times"
APP_VERSION = "0.1.0"

# All RIT scheduling is Eastern. Every date resolution goes through this.
CAMPUS_TZ = ZoneInfo("America/New_York")

BASE_DIR = Path(__file__).resolve().parent
CONFIG_DATA_DIR = BASE_DIR / "config" / "data"
MIGRATIONS_DIR = BASE_DIR / "migrations"

DB_PATH = Path(os.getenv("RIT_TIMES_DB", BASE_DIR.parent / "data" / "rit_times.db"))

# Honest, identifiable User-Agent with a contact. Required on every outbound call.
CONTACT = os.getenv("RIT_TIMES_CONTACT", "colewiz72@gmail.com")
USER_AGENT = (
    f"RITTimes/{APP_VERSION} (personal non-commercial campus info app; "
    f"not affiliated with RIT; contact {CONTACT})"
)

HTTP_TIMEOUT_SECONDS = float(os.getenv("RIT_TIMES_HTTP_TIMEOUT", "20"))
HTTP_MAX_RETRIES = int(os.getenv("RIT_TIMES_HTTP_RETRIES", "3"))

# Scrape cadence, in minutes. Scheduled only, never per request.
INTERVAL_DINING_MINUTES = int(os.getenv("RIT_TIMES_INTERVAL_DINING", "60"))
INTERVAL_EVENTS_MINUTES = int(os.getenv("RIT_TIMES_INTERVAL_EVENTS", "180"))
INTERVAL_MAKERSPACE_MINUTES = int(os.getenv("RIT_TIMES_INTERVAL_MAKERSPACE", "15"))
INTERVAL_OCCUPANCY_MINUTES = int(os.getenv("RIT_TIMES_INTERVAL_OCCUPANCY", "5"))
# Recreation hours are a weekly schedule that changes rarely, so this is slow
# on purpose. It is an HTML scrape, and hammering a page is worse manners than
# hitting an API.
INTERVAL_RECREATION_MINUTES = int(os.getenv("RIT_TIMES_INTERVAL_RECREATION", "360"))
# Menus rotate one location per run. Each response is about 7 MB and covers a
# whole month, so fetching all twelve at once would pull roughly 80 MB in a
# burst for data that changes daily at most.
INTERVAL_MENUS_MINUTES = int(os.getenv("RIT_TIMES_INTERVAL_MENUS", "45"))
# Campus points of interest are physical infrastructure. Water fountains do not
# move, so twice a day is generous.
INTERVAL_PLACES_MINUTES = int(os.getenv("RIT_TIMES_INTERVAL_PLACES", "720"))

# Static config entries older than this are reported as stale by /health/sources.
CONFIG_STALE_AFTER_DAYS = int(os.getenv("RIT_TIMES_CONFIG_STALE_DAYS", "120"))

# Run every scraper once on startup so a cold container serves data immediately.
SCRAPE_ON_STARTUP = os.getenv("RIT_TIMES_SCRAPE_ON_STARTUP", "1") == "1"

# Locations without an occupancy sensor are re-probed this often, instead of
# every occupancy cycle. Verified 2026-08-28: only 5 of 24 dining locations
# publish a densityData block at all.
OCCUPANCY_REPROBE_MINUTES = int(os.getenv("RIT_TIMES_OCCUPANCY_REPROBE", "360"))
