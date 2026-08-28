# Python 3.12: the pinned pydantic has no 3.12+ wheel gap, and it matches what
# the test suite runs against.
FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv

# Dependencies first, so a code change does not invalidate the wheel layer.
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# The SQLite file lives on a volume so the cache survives a redeploy.
RUN mkdir -p /srv/data && \
    useradd --system --uid 10001 --home /srv rittimes && \
    chown -R rittimes:rittimes /srv
USER rittimes

ENV RIT_TIMES_DB=/srv/data/rit_times.db

EXPOSE 8000

# The container is unhealthy when a scraper has been failing, which is what
# /health/sources encodes. That way Docker surfaces a broken parser too.
HEALTHCHECK --interval=60s --timeout=5s --start-period=90s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=4).status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
