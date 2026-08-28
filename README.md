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
.venv/bin/python -m pytest          # 71 tests, no network
.venv/bin/uvicorn app.main:app --reload
```

Then open http://127.0.0.1:8000/docs.

## Deploying

Public host: `tigerhub.colewiz.dev`. On campus: `tigerhub.student.rit.edu`.

```bash
cd backend
docker compose up -d --build
```

Runs as **standalone Docker on the Debian box, deliberately outside the k3s
cluster**. That is a conscious choice for a small personal service, not an
oversight, and it is not GitOps managed by Argo CD. SQLite plus APScheduler
means exactly one replica, so the cluster buys nothing here.

TLS terminates at the Cloudflare Tunnel edge, so the container carries no
certresolver and no TLS config. The routing labels are still to be filled in by
copying the existing `lore.colewiz.dev` service pattern verbatim.

The SQLite cache lives on a named volume so it survives a rebuild.

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

- `GET /health` liveness. Answers as soon as the port is bound and never
  depends on scraper state, so a cold cache does not read as a failed rollout.
  This is the one to point a readiness probe at.
- `GET /health/sources` per scraper `state` (`priming`, `ok`, `stale`,
  `failing`), last success, last error, and consecutive failures, plus static
  config entries that are unverified or older than 120 days. Returns 503 only
  for a real problem. A container that just booted reports `priming` with 200.

Every list endpoint returns an envelope, never a bare array:

```json
{ "data": [], "stale": true, "last_updated": null }
```

A cold cache answers 200 with an empty `data` and `stale: true`. The client
shows a subtle indicator, not an error screen.

## Campus mail

RIT runs a **zone based** mail system, verified against
[rit.edu/fa/campus-post-offices](https://www.rit.edu/fa/campus-post-offices).
There are no per hall street addresses and **no mailbox numbers**: mail is
picked up at the counter after an email notification.

Two offices serve campus housing. Global Village (`6000 Reynolds Drive`) covers
the west side, DSP in Perry Hall (`43 Greenleaf Court`) covers the east. Line 2
of the address is a building/room designator whose format varies by area. The
RIT Inn and 175 Jefferson Road bypass both offices.

`1 Lomb Memorial Drive` is **not** a student package address. RIT states mail
sent there is delayed.

## Known gaps

- SHED hours are hardcoded because the upstream GraphQL hours feed is buggy.
  The open and close times came off that payload but the weekday mapping is
  inferred, so treat as provisional and cross check against rit.edu/shed.
- Routing labels in `docker-compose.yml` are intentionally blank pending the
  `lore.colewiz.dev` pattern. Everything else in the compose file is complete.
- The Dockerfile and compose file are unbuilt: no container runtime on the
  development machine.
