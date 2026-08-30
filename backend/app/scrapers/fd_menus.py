"""Menus, allergens and dietary tags from FD MealPlanner.

RIT publishes its menus through FD MealPlanner, which is the only source that
carries allergen and dietary information. Verified 2026-08-30 across 771
recipes at one location:

    ALLERGENS  Gluten 561, Wheat 561, Milk 515, Egg 406, Soy 399,
               Coconut 101, Treenut 41, Sesame 20, plus "May Contain
               Traces of ..." variants
    DIETARY    Vegetarian 678, Vegan 128, Pork 40, Beef 5

**Halal and kosher are not tagged at all**, so nothing is ever labelled that
way. Filtering on pork as a proxy would be wrong and the stakes are too high.

Tags are stored exactly as published. They are not interpreted, normalised into
a tidier vocabulary, or extended by inference, because getting an allergen
wrong is not a cosmetic bug. Cross contamination is not in this feed either,
which is why the client shows a blunt caveat next to any dietary filter.

**Cadence.** One response is roughly 7 MB and covers a whole month, and there
are 12 mapped locations. Fetching all of them at once would pull about 80 MB in
one burst for data that changes daily at most. So this rotates: one location per
run, least recently refreshed first, which works out to a full cycle in about
half a day at one request at a time.
"""

import logging
from datetime import date, datetime

from app import http, settings
from app.config import get_config
from app.models import menus as menus_model
from app.scrapers.base import run_scraper

log = logging.getLogger(__name__)

SOURCE = "fd_menus"
BASE = "https://apiservicelocatorstenantrit.fdmealplanner.com/api/v1/data-locator-webapi"

# FD's own "all day" period, which is what RIT publishes against.
MEAL_PERIOD_ID = 8


def _url(tenant: int, account: int, location: int, when: date) -> str:
    return (
        f"{BASE}/{tenant}/meals"
        f"?menuId=0&accountId={account}&locationId={location}"
        f"&mealPeriodId={MEAL_PERIOD_ID}&tenantId={tenant}"
        f"&monthId={when.month}&yearId={when.year}&startDate=&endDate="
    )


async def fetch(tenant: int, account: int, location: int, when: date) -> dict:
    return await http.get_json(_url(tenant, account, location, when))


def _split(raw: str | None) -> list[str]:
    if not raw:
        return []
    return [part.strip() for part in raw.split(",") if part.strip()]


def parse(payload: dict) -> list[dict]:
    """Flatten FD's month of nested recipes into one row per dish per date."""
    days = payload.get("result")
    if not isinstance(days, list):
        return []

    dishes: list[dict] = []
    seen: set[tuple[str, str]] = set()

    for day in days:
        service_date = day.get("strMenuForDate")
        if not service_date:
            continue

        for recipe in day.get("allMenuRecipes") or []:
            # FD sometimes carries entries that are not meant to be shown.
            if recipe.get("isShowOnMenu") in (0, "0", False):
                continue

            name = (
                recipe.get("englishAlternateName")
                or recipe.get("componentName")
                or ""
            ).strip()
            if not name:
                continue

            key = (service_date, name.lower())
            if key in seen:
                continue
            seen.add(key)

            allergens = _split(recipe.get("allergenName"))
            dietary = _split(recipe.get("recipeProductDietaryName"))
            calories = recipe.get("calories")

            dishes.append(
                {
                    "service_date": service_date,
                    "name": name,
                    "category": (recipe.get("category") or "").strip() or None,
                    # Stored verbatim, joined only for storage.
                    "allergens": ",".join(allergens) or None,
                    "dietary": ",".join(dietary) or None,
                    "calories": float(calories) if isinstance(calories, (int, float)) else None,
                }
            )

    return dishes


async def scrape() -> int:
    config = get_config().fd_locations
    mapping = {loc.dining_id: loc for loc in config.locations}
    target = menus_model.oldest_refreshed(list(mapping))
    if target is None:
        return 0

    entry = mapping[target]
    when = datetime.now(settings.CAMPUS_TZ).date()

    payload = await fetch(config.tenant_id, entry.fd_account_id, entry.fd_location_id, when)
    dishes = parse(payload)
    if not dishes:
        raise ValueError(f"FD returned no dishes for {entry.fd_name}")

    stored = menus_model.replace_location(target, dishes)
    log.info("menus refreshed for %s, %d dishes", entry.fd_name, stored)
    return stored


async def run() -> bool:
    return await run_scraper(SOURCE, scrape)
