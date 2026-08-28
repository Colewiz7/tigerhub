"""FastAPI application entrypoint."""

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app import db, scheduler as scheduler_module, settings
from app.api import campus, dining, events, health, makerspace
from app.config import ConfigError, load_config
from app.config.static import set_config

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
)
log = logging.getLogger(__name__)

DESCRIPTION = (
    "Campus information API for RIT Times.\n\n"
    "Not affiliated with, endorsed by, or officially connected to Rochester "
    "Institute of Technology. Student built and student maintained.\n\n"
    "All data is served from a scheduled cache. No endpoint triggers a live "
    "scrape of an upstream RIT service."
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Static config is load bearing, so a typo crashes the container here
    # rather than quietly serving a wrong mailing address in October.
    try:
        set_config(load_config())
    except ConfigError:
        log.critical("static config is invalid, refusing to start")
        raise

    db.migrate()

    scheduler = scheduler_module.build_scheduler()
    scheduler.start()
    app.state.scheduler = scheduler

    if settings.SCRAPE_ON_STARTUP:
        # Background task so a slow upstream cannot block the port binding.
        app.state.priming = asyncio.create_task(scheduler_module.run_all_once())

    log.info("%s %s ready", settings.APP_NAME, settings.APP_VERSION)
    try:
        yield
    finally:
        scheduler.shutdown(wait=False)


app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description=DESCRIPTION,
    lifespan=lifespan,
)

# The Flutter web build is a separate origin, so the PWA needs CORS.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(dining.router)
app.include_router(events.router)
app.include_router(makerspace.router)
app.include_router(campus.router)


@app.get("/", tags=["meta"])
def root():
    return {
        "app": settings.APP_NAME,
        "version": settings.APP_VERSION,
        "docs": "/docs",
        "disclaimer": health.DISCLAIMER,
    }
