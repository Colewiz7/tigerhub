"""The single outbound HTTP client.

Every upstream call goes through here. This is the only place that sets the
User-Agent, timeouts, and retry policy, so scraping etiquette is enforced by
construction rather than by convention.
"""

import asyncio
import logging

import httpx

from app import settings

log = logging.getLogger(__name__)

# Retry only on transport errors and these transient statuses. A 404 or a 400
# is a real answer, so retrying it just adds load upstream for no benefit.
RETRY_STATUSES = {429, 500, 502, 503, 504}


class UpstreamError(RuntimeError):
    """An upstream source failed after exhausting retries."""


def _client(**kwargs) -> httpx.AsyncClient:
    return httpx.AsyncClient(
        headers={"User-Agent": settings.USER_AGENT},
        timeout=settings.HTTP_TIMEOUT_SECONDS,
        follow_redirects=True,
        **kwargs,
    )


async def request(method: str, url: str, **kwargs) -> httpx.Response:
    """Make one upstream request with retry and backoff. Raises UpstreamError."""
    last: Exception | None = None
    async with _client() as client:
        for attempt in range(settings.HTTP_MAX_RETRIES):
            try:
                response = await client.request(method, url, **kwargs)
            except httpx.HTTPError as exc:
                last = exc
            else:
                if response.status_code not in RETRY_STATUSES:
                    response.raise_for_status()
                    return response
                last = UpstreamError(f"{response.status_code} from {url}")

            if attempt < settings.HTTP_MAX_RETRIES - 1:
                backoff = 2**attempt
                log.warning("retry %s %s in %ss (%s)", method, url, backoff, last)
                await asyncio.sleep(backoff)

    raise UpstreamError(f"{method} {url} failed after {settings.HTTP_MAX_RETRIES} attempts: {last}")


async def get_json(url: str, **kwargs) -> dict:
    return (await request("GET", url, **kwargs)).json()


async def get_text(url: str, **kwargs) -> str:
    return (await request("GET", url, **kwargs)).text


async def get_bytes(url: str, **kwargs) -> bytes:
    return (await request("GET", url, **kwargs)).content


async def post_json(url: str, payload: dict, **kwargs) -> dict:
    response = await request("POST", url, json=payload, **kwargs)
    return response.json()
