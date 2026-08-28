"""Shared scraper plumbing.

Every scraper is a fetch() plus a parse() plus a store step. run_scraper wraps
that so success and failure are always recorded against source_health, which is
what /health/sources reports. A scraper that raises never takes the app down.
"""

import logging
import time
from collections.abc import Awaitable, Callable

from app.models import health

log = logging.getLogger(__name__)


async def run_scraper(source: str, job: Callable[[], Awaitable[int]]) -> bool:
    """Run one scrape, recording health either way. Returns success."""
    health.record_attempt(source)
    started = time.monotonic()
    try:
        count = await job()
    except Exception as exc:
        health.record_failure(source, f"{type(exc).__name__}: {exc}")
        log.exception("scraper %s failed", source)
        return False

    elapsed = time.monotonic() - started
    health.record_success(source, count)
    log.info("scraper %s ok, %d record(s) in %.1fs", source, count, elapsed)
    return True
