# RIT Times

A personal, non commercial campus information app for RIT. Dining hours, campus
events, housing mailing addresses, post office hours, and live SHED makerspace
equipment availability, in one place.

> **Not affiliated with, endorsed by, or officially connected to Rochester
> Institute of Technology.** This is a student built, student maintained
> project. All data comes from public RIT endpoints. No login gated endpoint is
> ever contacted, and no credentials are ever stored.

## Layout

```
backend/          FastAPI app, scrapers, APScheduler jobs, SQLite cache
  app/scrapers/   one module per source, each with fetch() and parse()
  app/models/     every SQL statement in the project lives here
  app/api/        typed routes, served from cache only
  app/config/     validated static JSON (post offices, SHED, residence halls)
  tests/fixtures/ saved real responses, the suite never touches the network
client/           Flutter app (android, linux, web), not yet scaffolded
assets/prompts/   asset generation prompts, placeholders until generated
docs/recon/       captured sample payloads from the recon phase
```

## Running the backend

```bash
cd backend
python3.12 -m venv .venv
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest          # 58 tests, no network
.venv/bin/uvicorn app.main:app --reload
```

Then open http://127.0.0.1:8000/docs.

## Deploying

```bash
cd backend
docker compose up -d --build
```

The compose file carries Traefik labels for a homelab behind a Cloudflare
Tunnel. The SQLite cache lives on a named volume so it survives a rebuild.

## Data sources

| Source | What it gives | Auth |
|---|---|---|
| TigerCenter `dining-all` | dining locations, hours, visiting chefs | none |
| CampusGroups iCal | student club events | none |
| RIT Drupal JSON:API | official university events | none |
| make.rit.edu GraphQL | live SHED equipment availability | none |
| maps.rit.edu `.data` | live occupancy for 5 dining locations | none |
| static JSON config | post office hours, SHED hours, mailing addresses | n/a |

Full endpoint detail, response shapes, and the reasoning behind each choice are
in [CLAUDE.md](CLAUDE.md).

## Scraping etiquette

Enforced in code, not just documented:

- Scheduled scrapes only. No route ever triggers a live upstream fetch.
- Every outbound call goes through one client wrapper that sets an honest,
  identifiable User-Agent with a contact address, plus timeouts and backoff.
- Cadence: dining hourly, events every 3 hours, makerspace every 15 minutes,
  occupancy every 5 minutes.
- Occupancy polls only the locations that actually publish it (5 of 24), which
  cuts that job from about 6,900 requests a day to about 1,400.
- Login gated endpoints are never contacted. Dining dollars is out of scope.

## Health

- `GET /health` liveness.
- `GET /health/sources` per scraper last success, last error, and consecutive
  failures, plus static config entries that are unverified or older than 120
  days. Returns 503 when anything is unhealthy, so a broken parser surfaces
  before the UI does.

## Known gaps

- Residence hall street addresses in `backend/app/config/data/residence_halls.json`
  are **unverified placeholders**. They ship with `last_verified: null`, so
  `/health/sources` reports them stale and the API returns `verified: false`
  on the address lookup. Confirm against rit.edu/housing before shipping.
- SHED hours are hardcoded because the upstream GraphQL hours feed is buggy.
  Cross check against rit.edu/shed.
