"""APScheduler wiring.

Scheduled scrapes only. No route ever triggers an upstream fetch, so the API
always serves the SQLite cache and RIT sees a predictable, low request rate.
"""

import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.interval import IntervalTrigger

from app import settings
from app.scrapers import (
    athletics,
    campusgroups,
    drupal_events,
    fd_menus,
    makerspace,
    maps_occupancy,
    recreation,
    tigercenter,
)

log = logging.getLogger(__name__)

# (job id, runner, interval minutes, stagger seconds)
# Staggered starts so a cold container does not fire five scrapers at once.
JOBS = [
    ("dining", tigercenter.run, settings.INTERVAL_DINING_MINUTES, 0),
    ("campusgroups", campusgroups.run, settings.INTERVAL_EVENTS_MINUTES, 20),
    ("drupal_events", drupal_events.run, settings.INTERVAL_EVENTS_MINUTES, 40),
    ("makerspace", makerspace.run, settings.INTERVAL_MAKERSPACE_MINUTES, 60),
    ("occupancy", maps_occupancy.run, settings.INTERVAL_OCCUPANCY_MINUTES, 80),
    ("recreation", recreation.run, settings.INTERVAL_RECREATION_MINUTES, 100),
    ("menus", fd_menus.run, settings.INTERVAL_MENUS_MINUTES, 120),
    ("athletics", athletics.run, settings.INTERVAL_EVENTS_MINUTES, 140),
]


def build_scheduler() -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler(timezone=settings.CAMPUS_TZ)
    for job_id, runner, minutes, stagger in JOBS:
        scheduler.add_job(
            runner,
            trigger=IntervalTrigger(minutes=minutes, jitter=stagger or None),
            id=job_id,
            name=f"scrape:{job_id}",
            max_instances=1,
            coalesce=True,
            misfire_grace_time=minutes * 30,
        )
        log.info("scheduled %s every %d minute(s)", job_id, minutes)
    return scheduler


async def run_all_once() -> dict[str, bool]:
    """Prime the cache on startup so a fresh container serves data immediately.

    Ordering matters in one place: occupancy polls the mdo_ids discovered by
    the dining scrape, so dining runs first.
    """
    results: dict[str, bool] = {}
    for job_id, runner, _, _ in JOBS:
        try:
            results[job_id] = await runner()
        except Exception:
            log.exception("startup scrape %s raised", job_id)
            results[job_id] = False
    return results
