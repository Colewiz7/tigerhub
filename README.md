# TigerHub

A personal, non commercial campus information app for RIT. Dining hours, campus
events, housing mailing addresses, post office hours, and live SHED makerspace
equipment availability, in one place.

> **Not affiliated with, endorsed by, or officially connected to Rochester
> Institute of Technology.** This is a student built, student maintained
> project. All data comes from public RIT endpoints. No login gated endpoint is
> ever contacted, and no credentials are ever stored.

## Layout

```
client/                  the app, and the only thing that ships
  lib/data/              the scrapers, cadence, and storage
    sources/             one file per upstream
    upstream.dart        the single outbound client, sets the User-Agent
    local_backend.dart   routes a path to a source, holds the cadence
    store.dart           snapshots on disk, one JSON file per source
    hours.dart           the TigerCenter recurrence resolver
    campus_time.dart     America/New_York without a timezone package
    turbo_stream.dart    the decoder for the campus map's payload format
  assets/config/         hand maintained JSON, each with a last_verified date
  test/golden/           pinned output, and captured upstream payloads
assets/generated/        the wordmark, glyphs and icon art, plus SPEC.md
docs/notes.md            endpoints, recon findings, and the decisions
docs/backlog.md          decided but not built
docs/recon/              captured sample payloads from the recon phase
```

## There is no server

The app scrapes RIT directly on the device. There is nothing to deploy, nothing
to keep running, and no account to create.

It used to be a FastAPI service on a homelab. That box gets rebuilt and rebooted
for other projects, so its uptime could not be promised for something you check
between classes, and the server was removed on 2026-08-30.

**The cost was the Web target.** Four of the six upstreams send no
`Access-Control-Allow-Origin`, so a browser cannot reach them:

```
tigercenter.rit.edu           no ACAO
www.rit.edu                   no ACAO
maps.rit.edu                  no ACAO
ritathletics.com              no ACAO
make.rit.edu                  ACAO: https://make.rit.edu   (its own origin only)
locations.fdmealplanner.com   ACAO: *
```

Native platforms have no such restriction, so **Linux, Android and iOS** are
unaffected. Web is not a target.

## Local development

Everything runs on the laptop. There is no service to start.

```bash
scripts/dev build        # build the linux release
scripts/dev app          # launch it
scripts/dev app --dev    # flutter run, with hot reload
scripts/dev test         # flutter analyze plus flutter test
scripts/dev data         # what has been scraped, and how old it is
scripts/dev reset        # wipe the snapshots, next launch scrapes fresh
scripts/dev package      # build a single file AppImage into dist/
scripts/dev install      # desktop entry and icons, for launchers
```

## Getting it as one file

```bash
scripts/dev package
```

Produces `dist/TigerHub-<version>-x86_64.AppImage`, about 11 MB. One file,
already executable. Run it, or move it anywhere; nothing needs installing and
nothing is written outside the file until the app starts and creates its own
data directory.

The Flutter Linux bundle is relocatable already (its `RUNPATH` is
`$ORIGIN/lib`), so the AppImage is mostly a wrapper that keeps the binary with
its `lib/` and `data/`, plus a desktop entry and icon the host can read without
installing anything.

**What is not bundled:** GTK3, glib and the usual desktop libraries, which are
expected on the host. That is true of every desktop Linux install, and bundling
a whole toolkit would multiply the size to guard against a case that does not
arise.

`appimagetool` is fetched once into `.tools/` on first run. Both `.tools/` and
`dist/` are gitignored.

Android needs the Android SDK installed, which the development machine does not
currently have; CI builds it. Linux builds and runs with no extra setup. iOS
builds only on Codemagic: see `codemagic.yaml` and docs/notes.md section 11.

## Data sources

| Source | What it gives | Auth |
|---|---|---|
| TigerCenter `dining-all` | dining locations, hours, visiting chefs | none |
| CampusGroups iCal | student club events | none |
| RIT Drupal JSON:API | official university events | none |
| make.rit.edu GraphQL | live SHED equipment availability | none |
| ritathletics.com iCal | 182 fixtures, September to March | none |
| maps.rit.edu `.data` | live occupancy, and campus points of interest | none |
| FD MealPlanner | menus, allergens and dietary tags | none |
| rit.edu recreation | gym, fitness and pool hours (HTML) | none |
| bundled JSON config | post office hours, SHED hours, mail zones | n/a |

Full endpoint detail, response shapes, and the reasoning behind each choice are
in [docs/notes.md](docs/notes.md).

## Scraping etiquette

Enforced in code, not just documented:

- Scheduled scrapes only. A read is served from the stored snapshot, and a
  source refreshes only when its snapshot is older than that source's cadence,
  so opening a tab five times does not scrape five times.
- **This matters more without a server, not less**, because there is now one
  scraper per install rather than one in total.
- Every outbound call goes through one client wrapper that sets an honest,
  identifiable User-Agent with a contact address, plus timeouts and backoff.
- Cadence: dining hourly, events every 3 hours, makerspace every 15 minutes,
  occupancy every 5 minutes.
- Occupancy polls only the locations that actually publish it, 5 of 24.
- Menus are fetched for the location being viewed and cached for a day. A month
  of menus is about 7 MB, and pulling all twelve locations would spend 84 MB of
  someone's data on places they never open.
- Login gated endpoints are never contacted. Dining dollars is out of scope.

## Offline first

The app must be fully usable with no network at all. This got more important
without a server, not less: there is no longer a warm cache on a machine
somewhere that has already done the scraping, so a device with no network has
only what it stored last time.

- Every response is persisted and replayed on the next launch. Roughly 2 MB.
- Last known data paints instantly. No cold start spinner.
- A stale cache never produces an error screen. An error screen is only correct
  on a first run that has never once succeeded.
- Post office hours, mail zone formats and SHED hours are bundled with the app,
  so the thing you look up standing at a counter with no signal always answers.

Every list endpoint returns an envelope, never a bare array:

```json
{ "data": [], "stale": true, "last_updated": null }
```

That envelope was the server's, and it was kept deliberately when the scraping
moved onto the device, so the presentation layer did not have to be rewritten
alongside everything else.

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
- **iOS has never been built or run.** `client/ios/` exists (iPhone only,
  portrait, iOS 15, bundle id `dev.colewiz.tigerhub`) and `codemagic.yaml`
  defines the build, signing and TestFlight workflows, but no Codemagic build
  has run yet and nothing has been tried on a device. This line goes once a
  signed build installs from TestFlight.
- **Android is not built on the development machine** (no SDK installed here).
  `client/android/` exists and CI builds a debug APK on every PR. A signed
  release APK via GitHub Releases is planned; Google Play is out of scope.
- **Not affiliated with RIT, and no written permission yet.** Each upstream's
  terms have not been audited. See docs/notes.md before any App Store
  submission.
- **Times are campus time, not device time.** Everything goes through
  `CampusTime`/`RitClock`; `DateTime.now()` remains only for elapsed time such
  as cache age. A few model fallbacks still use it; see docs/backlog.md.
- Menus, allergens and dietary tags describe ingredients, not preparation. They
  say nothing about shared fryers or surfaces. **Halal and kosher are not
  published by any source and are never inferred.**
