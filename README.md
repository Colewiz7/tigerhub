# TigerHub

Campus info app for RIT. Dining hours and menus, events, SHED equipment availability, post office hours and campus mail, all in one place. It is built with Flutter and has no server: the app reads RIT's public endpoints on the device and keeps working with no network.

<p>
  <img src="screenshots/dashboard.webp" alt="Today dashboard with dining and events" width="200">
  <img src="screenshots/dining-detail.webp" alt="Dining location with today's menu and dietary tags" width="200">
  <img src="screenshots/map.webp" alt="Campus map with building categories" width="200">
  <img src="screenshots/settings.webp" alt="Settings for events, dining, appearance and home screen" width="200">
</p>

<p>
  <img src="screenshots/desktop.webp" alt="Desktop layout of the dining view" width="640">
</p>

Not affiliated with or endorsed by RIT. It only contacts public endpoints, and no credentials are ever stored.

## What it does

- **Today** is a dashboard of cards for dining, events and campus status, with a reorderable home screen.
- **Dining** shows what is open now, hours per location, and each location's menu with dietary tags and allergens you can filter on.
- **Events** merges student club events and official university events, with muting and keyword rules.
- **Map** draws campus buildings by category, with walking paths and a search.
- **Campus** covers post office hours, mail zones and live SHED makerspace equipment availability.

## How it works

There is no backend. It used to be a FastAPI service on a homelab, but that box gets rebuilt for other projects and could not promise uptime for something you check between classes, so the scraping moved onto the device.

**Scraping is polite and enforced in code.** Every outbound call goes through one client that sets an identifiable User-Agent, timeouts and backoff. A source refreshes only when its stored snapshot is older than that source's cadence (dining hourly, events every 3 hours, makerspace every 15 minutes, occupancy every 5 minutes), so opening a tab five times does not scrape five times. Menus are fetched only for the location being viewed and cached for a day. Login-gated endpoints are never contacted.

**Offline first.** Every response is stored and replayed on the next launch, so the last known data paints instantly. A stale cache never produces an error screen. Post office hours, mail zone formats and SHED hours ship inside the app, so the lookup you do at a counter with no signal still answers.

**Data sources**

| Source | What it gives |
|---|---|
| TigerCenter | dining locations and hours |
| rit.edu dining pages | visiting chefs and times |
| CampusGroups iCal | student club events |
| RIT Drupal JSON:API | official university events |
| make.rit.edu GraphQL | SHED equipment availability |
| ritathletics.com iCal | athletics fixtures |
| maps.rit.edu | live occupancy and campus points of interest |
| FD MealPlanner | menus, allergens and dietary tags |
| rit.edu recreation | gym, fitness and pool hours |

Four of the upstreams send no CORS headers, so a browser cannot reach them. Web is not a target. Linux, Android and iOS are.

## Run it

```sh
scripts/dev build     # linux release build
scripts/dev app       # launch it
scripts/dev app --dev # flutter run with hot reload
scripts/dev test      # analyze and test
scripts/dev data      # what has been scraped and how old it is
scripts/dev reset     # wipe the snapshots
scripts/dev package   # single-file AppImage in dist/
```

`scripts/dev package` produces one executable AppImage of about 11 MB that needs nothing installed beyond the usual desktop libraries.

## Layout

- `client/` the Flutter app. `lib/data/sources/` has one scraper per upstream, and `lib/data/local_backend.dart` routes a request to a source and holds the cadence.
- `client/test/golden/` pinned parser output and captured upstream payloads.
- `client/assets/config/` hand-maintained JSON, each file with a last-verified date.
- `assets/` wordmark, glyphs and icon art.
- `design/` UI tokens.
- `scripts/` dev tooling, plus CI and Codemagic config for Android and iOS builds.
